/**
 * 音频本地缓存管理（B 档的核心：一个 service 单独管住落盘文件的一生）
 *
 * 背景：网桥机型（Redmi Watch 4 / Xiaomi Watch H1 E 这类没有 @system.fetch、
 * 也没有独立网络的设备）想出声只有一条路 —— 把音频经网桥 v4 流落到本地文件，
 * 再让 @system.audio 播本地 uri。落了盘就必须有人管：
 *
 *   - **复用**：同一首歌第二次播直接命中本地文件，不打 CDN（取流 playurl 仍要打，
 *     但那是几 KB 的 JSON，真正的大头是几 MB 的音频流）；
 *   - **清理**：官方文档明确提醒 IoT 设备要及时清理无用文件，否则内存/存储过载。
 *     这里的策略是「常驻只留 MAX_KEEP 份：当前 + 下一首 + 上一首，其余即删」；
 *     下载中的残片（.part）在任何失败/取消路径上立即删除，绝不冒充可播缓存。
 *   - **预取**：播放中后台落盘下一首，切歌时零等待（prefetchTrack/cancelPrefetch）。
 *   - **边下边播**：`@system.request.download` 不给 Range/进度，但落点是边下边长的；
 *     落够阈值（PROGRESSIVE_MIN）就把落点直接交给播放器出声，剩余字节在播放的同时
 *     继续落。收尾（搬进缓存目录 + 改名转正）延到**下一次查询该曲目**时做
 *     （finalizeFor）—— 音频还握着落点路径的时候，绝不动那个文件。
 *
 * 命名与目录来自 CONFIG.AUDIO_CACHE，写入一律走 .part 临时名，完整后改名：
 *   internal://cache/bilimusic_audio/bm_a_bv_BV1xxx.m4a.part → bm_a_bv_BV1xxx.m4a
 * 改名是「完成」的唯一标志 —— 崩溃/断电留下的 .part 会被 bootCleanup 删掉，
 * 绝不会被 access() 命中，所以播到的本地文件一定是 CRC 全过的完整文件。
 *
 * 跨 VM 语义：本服务与 playerService 一样是**每个 VM 一份实例**。在途下载表
 * （inflight）只在下载发起的那个 VM 里可见 —— 别的 VM 看不到它，但共享的是同一个
 * 文件系统，access() 命中即复用；极端情况下两个 VM 可能为同一首歌各下一份
 * （同名 .part 互相覆盖，落盘字节由 CRC 逐帧保证一致），不会产生孤儿文件。
 */

import file from '@system.file'
import { CONFIG } from '../common/config'
import { trackKey, sameTrack } from '../common/tracks'
import { binaryToUint8, base64Decode, utf8Decode, makeBridgeError, BRIDGE_ERRORS } from '../common/fetchbridge'
// 状态码字段名归一化：@system.fetch 给的是 `code`，网桥插件给的是 `status`
// —— 两份都认，但统一走这一个函数，业务代码不要各自读 res.status。
import {
  normalizeFetchResult,
  describeFetchShape,
  describeBodyShape,
  bytesOfBody,
  cdnNodeClass,
  urlDeadline,
} from '../common/parse'
// api.js 的 nativeBroken 是模块级单向锁存（一台设备要么有 fetch 要么没有），
// 离线自检切换机型时由 api.js 暴露的 __resetNativeProbe() 复位。
import { resolveProvider } from './api'
import { requestStream } from './interconnBridge'
// 设备能力锁存的落盘通道（loadDlCaps / saveDlCaps）：storage 是全局原生服务，
// 各 page VM、各次启动读到的是同一份 —— 探明一次，全设备不再撞墙。
import { Storage } from './storage'

const CACHE_CFG = CONFIG.AUDIO_CACHE
const DIR_URI = CACHE_CFG.DIR
const PREFIX = CACHE_CFG.PREFIX
const EXT = CACHE_CFG.EXT
const PART_SUFFIX = '.part'
/** 应用缓存分区根：`@system.request.download` 的落点（我们的子目录由 DIR_URI 管） */
const CACHE_ROOT_URI = 'internal://cache/'
// 原生机型（有 @system.fetch）的分块下载参数：见 config.js 里的「为什么必须分块」
const CHUNK_BYTES = CACHE_CFG.CHUNK_BYTES || 262144
// Range 档位阶梯（首档 = CHUNK_BYTES）：上一档拿不到字节就往下走，见 config.js
const RANGE_STEPS = CACHE_CFG.CHUNK_STEPS && CACHE_CFG.CHUNK_STEPS.length ? CACHE_CFG.CHUNK_STEPS : [CHUNK_BYTES]
const CHUNK_RETRIES = CACHE_CFG.CHUNK_RETRIES || 4
// 'file' 读法下搬临时文件的单片字节数（见 config.js：手表堆小，必须远小于 CHUNK_BYTES）
const READ_SLICE = CACHE_CFG.READ_SLICE || 65536
// 网桥 v4 流落盘的攒批阈值（见 config.js 的 WRITE_BATCH）：攒够这么多字节才写一次盘
const WRITE_BATCH = CACHE_CFG.WRITE_BATCH || 32768

/** 「这不像音频，像 CDN 的错误页」的体积上限（403 页实测几百字节） */
const DENY_PAGE_MAX = 4096
/** 探不到总长时，一份能信的音频至少得有这么长（一首歌不可能比这还小） */
const MIN_AUDIO_BYTES = 16384
/**
 * `@system.request.download` 的 header 打包形态（它要的是 **String**，见 downloadViaRequest 的注释）。
 * 顺序 = 尝试顺序：line（单行 UA）→ crlf / lf（整组头两种分行）→ json（整组头的 JSON 串）。
 */
const HEADER_SHAPES = ['line', 'crlf', 'lf', 'json']

/* ------------------------------ @system.file 包装 ------------------------------ */

/** 官方回调形态 → Promise（与 storage.js 的 promisify 同一写法） */
function callFs(method, args) {
  return new Promise((resolve, reject) => {
    try {
      file[method](
        Object.assign({}, args, {
          success: (data) => resolve(data),
          fail: (data, code) => reject(new Error(`file.${method} 失败 code=${code}${data ? ' ' + data : ''}`)),
        })
      )
    } catch (e) {
      reject(e)
    }
  })
}

/** 文件/目录是否存在（access 对任何失败码都返回 false：不存在/无权限一视同仁） */
async function access(uri) {
  try {
    await callFs('access', { uri })
    return true
  } catch (e) {
    return false
  }
}

async function deleteFile(uri) {
  try {
    await callFs('delete', { uri })
    return true
  } catch (e) {
    // 尽力而为：删除失败不打断主流程（残片清理还有 bootCleanup 与 prune 兜底）
    return false
  }
}

async function moveFile(srcUri, dstUri) {
  return callFs('move', { srcUri, dstUri })
}

/**
 * 原生整文件拷贝（`file.copy`）。**这是把 tmp 分区里的文件搬出来的唯一路子**，
 * 见 pumpTmpFile 的注释：官方参数表里 copy 只禁止 dstUri 是 tmp，srcUri 不限。
 */
async function copyFile(srcUri, dstUri) {
  return callFs('copy', { srcUri, dstUri })
}

/**
 * 列某个目录（默认缓存目录）。目录还没建过 / 列不出来 → 按空目录处理
 * （调用方各自决定下一步）。官方返回 {fileList: [{uri, length, lastModifiedTime}]}。
 */
async function listDir(uri) {
  try {
    const data = await callFs('list', { uri: uri || DIR_URI })
    return (data && data.fileList) || []
  } catch (e) {
    return []
  }
}

let dirReady = false

/** 首次落盘前确保目录存在（mkdir recursive；目录已在时静默忽略失败） */
async function ensureDir() {
  if (dirReady) return
  try {
    await callFs('mkdir', { uri: DIR_URI, recursive: true })
  } catch (e) {
    if (!(await access(DIR_URI))) throw e
  }
  dirReady = true
}

/* ------------------------------ 命名 ------------------------------ */

/**
 * 缓存键：曲目 bvid 优先、avid 兜底（复用 common/tracks.trackKey 的同一性判断），
 * 清洗成文件名安全字符。**刻意不含 cid** —— 键要跨「解析取流前后」保持稳定，
 * 否则解析前算的键和解析后算的键对不上，keep 名单会失手删掉刚落盘的文件；
 * 同 bvid 多 P 在本应用的内容形态（音乐单曲）下可以视为同一份音频。
 */
export function buildCacheKey(track) {
  const key = trackKey(track)
  if (!key) return ''
  return key.replace(/[^A-Za-z0-9_-]/g, '_')
}

function fileNameOf(key) {
  return PREFIX + key + EXT
}

function partNameOf(key) {
  return PREFIX + key + EXT + PART_SUFFIX
}

function uriOf(name) {
  return DIR_URI + name
}

/** list 返回的 uri（或文件名）→ 纯文件名 */
function baseName(uri) {
  const s = String(uri || '')
  const i = s.lastIndexOf('/')
  return i >= 0 ? s.slice(i + 1) : s
}

/**
 * 文件名 → 缓存键；不是本服务命名规则的返回 ''（prune 不碰外来文件）
 *
 * `.part` **及其派生物**都要能认回同一个键：`…m4a.part`（下载中的残片）与
 * `…m4a.part.tmp262144`（file 读法从 tmp 分区拷出的中转文件，见 pumpTmpFile）。
 * 认不回来的后果很具体：pruneCache 会把在途下载的中转文件当外来文件删掉，
 * 那一块就下载失败、白重试一遍。
 */
function keyFromName(name) {
  if (String(name).indexOf(PREFIX) !== 0) return ''
  let rest = name.slice(PREFIX.length)
  const cut = rest.indexOf(PART_SUFFIX)
  if (cut >= 0) rest = rest.slice(0, cut)
  if (EXT && rest.slice(-EXT.length) === EXT) rest = rest.slice(0, -EXT.length)
  return rest
}

/** 残片判定（`.part` 全家：下载中的、拷出中转到一半的）—— 都不算「已缓存」 */
function isPartName(name) {
  return String(name).indexOf(PART_SUFFIX) >= 0
}

/* ------------------------------ 在途下载表 ------------------------------ */

/**
 * key -> { kind: 'play'|'prefetch', track, promise, cancel, cancelled }
 * 同一首歌的「预取」与「正式播放」共用同一条在途 promise：切歌时 ensureTrackFile
 * 直接 await 它，预取下完就等于正式播的文件已就绪 —— 不会双份下载。
 */
const inflight = new Map()

function registerInflight(key, kind, track) {
  const entry = { kind, track, promise: null, cancel: null, cancelled: false }
  inflight.set(key, entry)
  return entry
}

function cancelEntry(entry, reason) {
  entry.cancelled = true
  if (typeof entry.cancel === 'function') {
    try {
      entry.cancel(reason)
    } catch (e) {
      // 取消是尽力而为：传输可能刚好自己结束了
    }
  }
}

/* --------------------------- 边下边播：提前交付与收尾 --------------------------- */

/**
 * 已开播但还没转正的完整文件表：key -> {srcUri, finalUri, bytes}。
 *
 * 边下边播的落点就是音频**正在读**的那个文件 —— 收尾（搬进缓存目录、改名转正）必须
 * 等到没人读它的时候再做。这里只登记，动手的永远是 finalizeFor：在下一次查询该曲目
 * 时（ensureTrackFile / getCachedFile / prefetchTrack 的缓存判断之前）触发，那时旧的
 * audio.src 已被换掉，动文件是安全的。改名是「完成」的唯一标志，延后不豁免 ——
 * 没转正之前 access(finalUri) 永远不命中，绝不会拿在长的文件冒充完整缓存。
 */
const pendingFinalize = new Map()

/**
 * 把一首「边下边播」下完的文件收尾转正（幂等；没有待收尾项时是零开销的查表）。
 * 失败不重试（先摘牌再动手）：残片交给启动清理 / 重下时的孤儿收编，别让一次
 * move 失败变成每次查询都撞一遍的固定动作。
 */
async function finalizeFor(key) {
  const p = pendingFinalize.get(key)
  if (!p) return
  pendingFinalize.delete(key)
  try {
    if (p.srcUri !== p.finalUri) {
      if (await access(p.finalUri)) await deleteFile(p.finalUri) // 旧的坏/过期文件让位（与转正路径同一纪律）
      await moveIntoPlace(p.srcUri, p.finalUri)
    }
    console.log('[AudioCache] 边播边下的缓存已转正:', key, p.bytes, 'bytes')
  } catch (e) {
    console.warn('[AudioCache] 边播边下收尾失败（残片交给启动清理/重下收编）:', e && e.message ? e.message : e)
  }
}

/**
 * 组装一次下载的「边下边播」钩子；不该启用时返回 null（走整份等待的老路）。
 *
 * shouldFire 的两条判据：①总长至少是阈值的 2 倍 —— 几秒就能下完的曲子没必要赌
 * growing file 的兼容性；②已落字节够阈值。fire 只发生一次（多次交付没有意义，
 * 播放器拿到落点后剩下的路它自己会走）。
 */
function makeProgressive(kind, firePlayable) {
  if (kind !== 'play') return null // 预取没人急着出声，仍静默整份
  if (useBridgeDownload()) return null // 网桥的 v4 流走 JS 堆分帧，另一套写盘节奏
  const min = CACHE_CFG.PROGRESSIVE_MIN || 0
  if (CACHE_CFG.PROGRESSIVE === false || !(min > 0)) return null
  const prog = {
    fired: false,
    playableUri: '',
    shouldFire(got, total) {
      return !!(total && total >= min * 2 && got >= min)
    },
    fire(uri, got) {
      if (prog.fired) return
      prog.fired = true
      prog.playableUri = uri
      if (typeof firePlayable === 'function') firePlayable({ uri, got })
    },
  }
  return prog
}

/* ------------------------------ 下载到文件 ------------------------------ */

/**
 * 走网桥 v4 流把 url 的响应体分帧追加写入 partUri。
 *
 * 写盘**串行化 + 攒批**（两道纪律，缺一不可）：
 *
 *   串行：帧到达顺序与写入完成顺序不保证同步（writeArrayBuffer 是异步回调），
 *   用一条 promise 链保证「上一批写成功才写下一批」—— append 模式的落点由系统维护，
 *   一旦乱序整份文件就是坏的。任何一批写失败 → 取消传输 → 整笔拒绝。
 *
 *   攒批：v4 是 4 KB 一帧，逐帧一次 file.writeArrayBuffer 就是每首几百上千次原生 IPC
 *   （外加同数量的短命 Promise）。攒到 WRITE_BATCH（默认 32 KB ≈ 8 帧）才写一次，
 *   落盘写次数降 8 倍。攒批**不推迟交付**：进度按批报（32 KB 粒度看不出来），
 *   而网桥机型本来就不启用边下边播（makeProgressive 返回 null），播放器等的始终是整份。
 *
 * 记账分两个数，别混：`received` = 已被 StreamAssembler 连续交付的字节（= 下一帧
 * 声明的 offset），`written` = **已真正落盘**的字节。已缓冲未写的那截算在 received 里，
 * 不算 written —— 所以 settleWrites() 必须**先 flush 再判完成**，否则结尾那批会漏写，
 * 而 move 转正会拿着一个少一截的文件当完整缓存。
 *
 * 堆占用上限 ≈ ACK 窗口在途字节 + 一批二进制字符串 + 该批的 Uint8Array（各一份），
 * 与整首歌的体积无关 —— 这正是分块落盘的意义。
 *
 * @returns {{promise: Promise<{status:number, totalBytes:number}>, cancel:(reason?:string)=>void}}
 */
function streamToFile(url, headers, partUri, onProgress, entry) {
  // tail 永远指向**最新**的写链（每批重新赋值）；绝不能把链提前钉进 Promise.all ——
  // 那会钉住空的旧引用，结束帧一到就误判「写完了」，move 抢在写盘前面跑
  let tail = Promise.resolve()
  // 已交付（连续消费）的字节数：帧声明的 offset 与它对齐；也是「文件最终该有多长」的数
  let received = 0
  // 已落盘字节数：写成功的字节才算，用于进度与结束时的长度对账
  let written = 0
  // 已缓冲未写的帧（二进制字符串，攒批用）。**不预先转成 Uint8Array** ——
  // 攒的这批在写之前只是普通字符串，flush 时才合并成一份 Uint8Array（省掉每帧一次分配）
  const buf = []
  let buffered = 0
  let contentLength = null
  // 写盘失败的一次性标记：不抛进 promise 链，而是记在这里 —— 链上任何一环 reject 都会
  // 让后续 flush 造出一条**起点就是 rejected** 的新链，那一批不会真写（静默短一截），
  // 还会顺带留下一个没人认领的 rejection。所以链永远只有 resolve 态，失败只走这个变量。
  let writeError = null

  const failWrite = (e) => {
    if (writeError) return
    writeError = e
    ctrl.cancel('写盘失败：' + (e && e.message ? e.message : ''))
  }

  /**
   * 把已缓冲的帧串成一笔写下来，返回追加到 tail 上的那条链。
   *
   * 两种「不写」都是零开销的：缓冲为空（结束时的常规情况）直接返回 tail；
   * 已经写坏过（writeError）只把缓冲丢掉 —— 传输正在被取消，这些字节不会再落盘。
   * `size` 在清缓冲**之前**抓：切缓冲是同步的、写是异步的，期间新到的帧进新 buf，
   * 绝不能算进这一笔的记账。
   */
  const flush = () => {
    if (!buffered) return tail
    const binary = buf.join('')
    const size = buffered
    buf.length = 0
    buffered = 0
    if (writeError) return tail
    tail = tail
      .then(
        () =>
          new Promise((resolve, reject) => {
            try {
              file.writeArrayBuffer({
                uri: partUri,
                // Uint8Array（官方要求）；一份一批，堆里同时只有一批的缓冲
                buffer: binaryToUint8(binary),
                append: true,
                success: () => {
                  written += size
                  if (typeof onProgress === 'function') {
                    try {
                      onProgress(written, contentLength)
                    } catch (e) {
                      // 进度回调不许影响下载
                    }
                  }
                  resolve()
                },
                fail: (data, code) => {
                  reject(new Error('音频落盘失败 code=' + code + (data ? ' ' + data : '')))
                },
              })
            } catch (e) {
              reject(e)
            }
          })
      )
      .catch(failWrite) // 失败只记账（链保持 resolve，见 writeError 的注释）
    return tail
  }

  /**
   * 等在途写全部落定（成功或失败都不抛）：失败/取消路径删残片前必须先等它。
   * **末尾必须再 flush 一次** —— 取消 / 空闲超时 / 结束帧都可能正好停在半批上，
   * 那半批还只在内存里，不冲出去的话调用方会把一个少一截的 .part 当成完整的搬走。
   */
  const settleWrites = () => {
    tail = flush()
    return tail
  }

  const ctrl = requestStream({
    url,
    headers,
    fixedChunks: true,
    onHeader: (info) => {
      contentLength = info.contentLength
    },
    onChunk: (binary, offset) => {
      if (writeError) return // 已经写坏了：不再收字节（传输正在被 ctrl.cancel 掐断）
      if (offset !== received) {
        // 理论上到不了：StreamAssembler 已按运行偏移校验过。再查一道，
        // 因为 append 写的落点就是文件末尾，偏移错位 = 文件报废
        failWrite(
          makeBridgeError(
            BRIDGE_ERRORS.PROTOCOL,
            '落盘偏移不连续：已交付 ' + received + ' 字节，帧声明 ' + offset
          )
        )
        return
      }
      received += binary.length
      buf.push(binary)
      buffered += binary.length
      // 没攒够就不动 tail：既不写盘也不造 Promise（这正是攒批的意义）。
      // 写失败由 flush 内部记进 writeError（链不会 reject），下一帧进来时上面那道门会拦住
      if (buffered < WRITE_BATCH) return
      tail = flush()
    },
  })

  // ctrl.promise 落定时（结束帧已过/已失败），tail 必然已经收齐全部写 ——
  // 因为 push() 是先同步派发 onChunk（把写排进 tail）再返回 ended，之后才 finish；
  // settleWrites 再冲一次末尾那半批，兜住「结束时刚好没攒够」的情况
  const promise = ctrl.promise.then(
    async (meta) => {
      await settleWrites()
      if (writeError) throw writeError
      return { status: meta.status, totalBytes: written }
    },
    async (e) => {
      await settleWrites()
      throw writeError || e // 写盘错误优先暴露（cancel 只是被它牵连的后果）
    }
  )

  // 包装一层：ctrl.cancel 在传输注册前后会被 requestStream 换实现，
  // 调用方永远拿到的必须是「当下那份」—— 固定引用会漏掉注册前的取消
  return { promise, cancel: (reason) => ctrl.cancel(reason) }
}

/**
 * CDN 请求头。这三样一个都不能少（实测：upos 系按头过滤）：
 *
 *   Referer      upos 系必需 —— 不带 Referer 一律 403（“什么都不带”那行就是 audio.src 的处境）
 *   User-Agent   upos 系**按 UA 过滤**：空 UA 403、`curl/x.y` 403，浏览器 UA 与 node 默认 UA 才 206
 *                （Vela 的 fetch 底层是 libcurl，默认 UA 形如 `curl/8.x`，正好在被拒那一类）
 *   Origin       可有可无，跟着 Referer 一起发（B 站接口与 CDN 的约定）
 *
 * mcdn 系则完全不挑：不带 Referer、空 UA、curl UA 全部 206 —— 这正是「有些歌能直链播」
 * 的由来（见 parse.cdnNodeClass），也是 @system.audio 不发请求头还能出声的原因。
 */
function cdnHeaders() {
  return {
    'User-Agent': CONFIG.USER_AGENT,
    Accept: '*/*',
    Referer: CONFIG.BILI_REFERER,
    Origin: CONFIG.BILI_ORIGIN,
  }
}

/**
 * 被 CDN 拒绝时，把「为什么」凑成一句话塞进报错里。
 *
 * 手表上没有日志可看，屏幕上的报错就是唯一线索，所以宁可长一点，把判据都带上：
 *
 *   节点类  —— mcdn 不校验 Referer、upos/edge 校验（见 parse.cdnNodeClass）；
 *   Referer —— 落盘这条路**是带了 Referer 的**（直链带不了，那是另一条路），
 *              所以这里写「已带」是事实陈述，方便区分「没带」；
 *   直链余  —— 地址里的 `deadline`（实测 120 分钟）。过期与防盗链同样回 403，
 *              但处置相反：过期要重新取流，防盗链要换节点；
 *   响应正文 —— B 站 403 的正文很短，有时直接写明原因（比如 referer 相关字样）。
 */
function describeRejection(url, res) {
  const parts = ['节点 ' + cdnNodeClass(url), 'UA/Referer 已带']
  const deadline = urlDeadline(url)
  parts.push(
    deadline ? '直链余 ' + Math.round((deadline - Date.now() / 1000) / 60) + ' 分钟' : '直链无 deadline'
  )
  const snippet = bytesToText(res.bytes, 80)
  // 标准的 403 正文是 openresty 的通用错误页（实测：`<html>…403 Forbidden…openresty…
  // Node_info/Request_id`），里面**没有**原因，塞进界面只会把有用信息挤掉；
  // 只有正文不是那一页时才带上（真出现别的正文，那正是要找的线索）。
  if (snippet && snippet.indexOf('openresty') < 0 && snippet.indexOf('403 Forbidden') < 0) {
    parts.push('响应: ' + snippet)
  }
  return parts.join('，')
}

/** 字节 → 可读文本（截断到 maxBytes 并压掉空白），用于把 CDN 的错误正文塞进报错 */
function bytesToText(bytes, maxBytes) {
  if (!bytes || !bytes.length) return ''
  const n = Math.min(bytes.length, maxBytes || 120)
  let binary = ''
  for (let i = 0; i < n; i++) binary += String.fromCharCode(bytes[i])
  return utf8Decode(binary).replace(/\s+/g, ' ').trim()
}

/* --------------------------- 原生机型：分块落盘 --------------------------- */

/**
 * 一个地址 → 分块落盘。**这是原生机型能播上「走蓝牙那类慢链路」的关键**：
 *
 *   Vela 的 fetch 失败码透传 libcurl，28 = CURLE_OPERATION_TIMEDOUT 是**单次操作**超时。
 *   整文件一次下在 60-70 KiB/s 上要几十秒，必超时，
 *   且超时后什么都没留下 → 同一首永远下不完。
 *
 * 这里改成「Range 取 256 KB → 追加写 .part → 记 written」，于是：
 *   1. 单次请求只跑 4 秒左右（60 KiB/s），稳在超时窗口内；
 *   2. 单块超时/断流只重试这一块，`written` 就是断点，**从断点续传**；
 *   3. 完整落盘后由 downloadToCache 改名转正 → 同一首第二次播零网络。
 *
 * 无 Content-Length 或服务器不支持 Range（回了 200 而不是 206）时不硬套分块：
 * 改成一次请求下完再整块追加，只是没有续传能力。
 *
 * 「字节从哪来」有两套读法，由 fetchRangeChunk 决定、拿不到就换（见那里的注释）：
 *   arraybuffer —— responseType:'arraybuffer'，字节直接进 JS 堆；
 *   file        —— responseType:'file'，框架原生落到 tmp 分区的临时文件，我们先把它
 *                  拷出 tmp（`file.copy`；tmp 直接可读的机型就省这一步）再分片读回追加。
 * 这两道兜底都是必需的：实测有机型回 206 + 合法 Content-Range 却给
 * 空 data；同一台机型拿到 tmp uri 后直接读它又回 202 参数错误。
 *
 * @param {object|null} [prog] 边下边播钩子（makeProgressive 的产物；null = 整份等待）
 * @returns {Promise<{bytes:number, chunked:boolean}>}
 */
async function downloadNativeToFile(url, partUri, onProgress, isCancelled, prog) {
  await deleteFile(partUri) // 上一次的残片：从现在这一份重新开始写
  let written = 0
  let total = null
  let stallAt = -1 // 上一轮的 written，用于识别「原地打转」
  const cancelled = typeof isCancelled === 'function' ? isCancelled : () => false

  while (true) {
    if (cancelled()) {
      throw makeBridgeError(BRIDGE_ERRORS.CANCELLED, '传输已被取消（分块下载）')
    }
    const from = written
    const to = from + rangeBytes - 1
    let res
    try {
      res = await fetchRangeWithRetry(url, from, to, cancelled)
    } catch (e) {
      // 「2xx 却没有字节」有两种成因，处置都是在**同一段**上重来而不是换地址：
      //   ①运行时把太大的响应体丢了（快应用规范：fetch 数据不能超过 100k）→ 缩档位
      //   ②真的没有（两种读法都空）→ 缩档位也没用，交给上层的换通道逻辑
      // 缩档位是安全的：一个字节都没写进 .part，重来不会拼出两段来源不同的字节。
      if (e && e.isEmptyBody && shrinkRange()) continue
      throw e
    }
    const code = res.httpCode

    if (code !== 206) {
      if (code === 200) {
        // 服务器忽略 Range 直接给了整份（或本来就不支持 Range）→ 退回「一次下完」
        if (from > 0) throw new Error('服务器忽略 Range 且已写入 ' + from + ' 字节，无法续传')
        // 200 没有 Content-Range 兜底，只能拿 Content-Length 对账：
        // 收少了说明这份是断的，宁可不落盘（上层会换候选地址重来），
        // 因为 .part 一旦转正就会一直冒充「完整缓存」。
        const declared = parseContentLength(getHeader(res.headers || {}, 'Content-Length'))
        const got = await appendChunkBytes(res, partUri, written, declared || null, onProgress)
        if (declared && got !== declared) {
          throw new Error('整份响应被截断（收到 ' + got + '/' + declared + ' 字节）')
        }
        written += got
        console.log('[AudioCache] 本地址不支持 Range，已整份落盘:', written, 'bytes')
        return { bytes: written, chunked: false }
      }
      if (code === 403 || code === 401 || code === 410) {
        // 403 有两种成因、处置完全相反：防盗链（节点要 Referer/UA）与直链过期（要重新取流）。
        // 手表上没有日志可看，报错里把判据一起写进去。
        throw new Error('CDN 拒绝（HTTP ' + code + '，' + describeRejection(url, res) + '）')
      }
      throw new Error('CDN 返回 HTTP ' + code)
    }

    const range = res.headers ? parseContentRange(getHeader(res.headers, 'Content-Range')) : null
    if (!range || !range.total) {
      throw new Error('206 响应缺少可解析的 Content-Range（无法确定落点/总长）')
    }
    if (range.start !== written) {
      throw new Error('响应起点 ' + range.start + ' 与已写入的 ' + written + ' 不一致，内容不可信')
    }
    total = range.total

    // 字节有两个可能的下落：已经在 JS 堆里（arraybuffer 读法），或躺在框架自己落下的
    // 临时文件里（file 读法，见 pumpTmpFile）。**能不能拿到字节由上游
    // fetchRangeWithRetry / assertBodyUsable / pumpTmpFile 判定**，
    // 这里只管把它追加进 .part；进度也由 appendChunkBytes 逐片上报，别在这里重复报一次。
    let got
    try {
      got = await appendChunkBytes(res, partUri, written, total, onProgress)
    } catch (e) {
      // 「字节在临时文件里但怎么都取不出来」：先别急着换地址 —— 缩一档 Range 从头来，
      // 小响应体很可能根本不需要走 tmp（arraybuffer 直接就给字节了）。
      if (e && e.tmpUnreadable && shrinkRange()) continue
      throw e
    }
    if (!got) {
      // 上游已保证 res.bytes / res.tmpUri 至少有一个非空，走到这里说明读法之间出现了空档
      // —— 报错里带上形态与试过的读法，别只说一句「为空」。
      throw new Error('分块响应体为空（' + describeBodyFailure(res, written, total) + '）')
    }
    written += got
    // 边下边播：落够阈值就把 .part 交给播放器（它本来自家就在往里追加，单一写入方）。
    // 之后哪怕这块失败，已开播的这份也不许删（runCandidates / downloadViaRequest 里都有守卫）。
    if (prog && !prog.fired && prog.shouldFire(written, total)) prog.fire(partUri, written)
    // 写满总长即完成。注意不能假设「服务器一定按我们要的长度给」——
    // Range 响应被截短（提前收尾）时 bytes 比请求的小，但 written 会推进，
    // 下一轮就是用新位置再要一次，自然收敛。
    if (written >= total) return { bytes: written, chunked: true }
    // 死循环闸门：万一服务器回了 206 却在原地打转（written 不涨），直接判失败，
    // 让上面的重试/换地址逻辑接得住
    if (written === stallAt) throw new Error('分块下载原地打转（已 ' + written + '/' + total + ' 字节）')
    stallAt = written
  }
}

/* ------------------- 原生机型第二条通道：@system.request 整份原生下载 ------------------- */

/**
 * 用 `@system.request.download` 整份原生下载（官方「下载 request」）。
 *
 * 为什么要有这条路：部分机型上「fetch 分块」根本拿不到字节 —— arraybuffer 回空 data
 * （运行时丢大响应体），file 读法落下的 tmp 分区又读不出来（readArrayBuffer/copy 都 202）。
 * request.download 是**原生下载管理器**：它自己把字节写进应用缓存目录（默认分区，不是 tmp），
 * 不占 JS 堆、也不受 fetch 单次操作超时的约束，随后我们的 @system.file 能正常 move/copy/读它。
 *
 * 代价（必须写清楚，免得误以为这条更好）：
 *   - **不能 Range 续传**：一次整份，失败就得从头（所以它只是兜底，优先还是 fetch 分块）；
 *     也没有分片参数 —— 唯一的「分片感」来自落点文件本身是边下边长的（见 prog 参数，
 *     边下边播就建立在这个事实上）；
 *   - 没有进度回调：进度靠轮询文件大小（进度是听感的事，闸门是稳定性的事）；
 *   - 没有取消接口：放弃后下载可能还在后台跑，落下的文件在缓存分区里，由系统按需回收
 *     （官方：Cache 分区「可能因存储空间不足被系统删除」）。
 *
 * 长度对账是这条路的**验收条件**：先拿 1 字节 Range 探出总长（顺带确认请求头没被吞），
 * 下完再比对文件大小 —— 不比对的话，403 错误页会被当成音频缓存起来（那是"幽灵缓存"，
 * 之后每次播都是那句没头没尾的「播放失败」）。
 *
 * 两条实测纪律：
 *   - `header` 是 **String**（不是 fetch 那样的对象），见 HEADER_SHAPES 的注释；
 *   - 打包格式官方没写，所以形态要**逐档试**，判据只有长度对账 —— 「任务建起来了」
 *     不等于「请求头带上了」：请求头被丢掉时任务照样成功，只是下回来一份错误页。
 *
 * @param {object|null} [prog] 边下边播钩子（makeProgressive 的产物；null = 整份等待）
 * @returns {Promise<number>} 落盘字节数
 */
async function downloadViaRequest(url, partUri, onProgress, isCancelled, prog) {
  const mod = requestModule()
  if (!mod) throw new Error('本机没有 @system.request（无法整份原生下载）')

  const expected = await probeRemoteSize(url)
  const fileName = baseName(partUri)
  // 下载管理器落在应用缓存目录**根**上（不是我们的子目录）：进度要盯着它，
  // 长度对账也要先在这一份上做完，最后才搬进 .part（见 downloadOnceWithShape）。
  const landedUri = CACHE_ROOT_URI + fileName

  // 收编孤儿：上次运行 / 上个 VM 留下的**完整**落点（长度对账通过）直接搬进缓存，
  // 不再下一遍 —— 边下边播的收尾要是没来得及做（VM 随页面销毁），下次播同一首
  // 就从这里把那几十秒的下载成果捡回来。长度不等的一律照常下载（循环第一步会删掉它）。
  if (expected > 0) {
    const orphan = await sizeOf(landedUri)
    if (orphan === expected) {
      await moveIntoPlace(landedUri, partUri)
      const final = await sizeOf(partUri)
      if (final === orphan) {
        console.log('[AudioCache] 收编上次留下的完整落点:', orphan, 'bytes')
        if (typeof onProgress === 'function') {
          try {
            onProgress(orphan, expected)
          } catch (e) {
            // 进度回调不许影响下载
          }
        }
        return orphan
      }
      await deleteFile(partUri) // 搬运后对不上：删掉，照常走下载
    }
  }

  const shapes = headerShapesToTry()
  const tried = []
  let lastErr = null

  for (let i = 0; i < shapes.length; i++) {
    const shape = shapes[i]
    // 每次尝试都从零开始：上一次留下的（下到一半的、下完整份的）一律删干净。
    // 两次尝试的字节绝不混在一起 —— .part 只会见到**长度已对得上**的那一份。
    await deleteFile(landedUri)
    await deleteFile(partUri)
    try {
      const got = await downloadOnceWithShape(
        mod,
        url,
        fileName,
        landedUri,
        partUri,
        shape,
        expected,
        onProgress,
        isCancelled,
        prog
      )
      headerShape = shape // 锁存：下一首直接用这一档，不再从头试
      saveDlCaps() // 设备能力落盘：别的 VM / 下次启动也不再从第一档撞起
      return got
    } catch (e) {
      lastErr = e
      // 收集时**不截短**（设备的原话是有用的凭据），长度由 describeDownloadFailure 统一收口
      tried.push(shape + '→' + shortErr(e, 200))
      if (i === shapes.length - 1 || !canRetryWithAnotherHeader(e)) break
      console.warn('[AudioCache] header 形态 ' + shape + ' 没成（' + shortErr(e) + '），换下一档')
    }
  }
  // 已开播的落点不能删：音频正握着这个路径（失败的字节让它把已落的部分播完）
  if (!(prog && prog.fired)) await deleteFile(landedUri)
  await deleteFile(partUri)
  throw describeDownloadFailure(lastErr, tried, shapes.length, expected)
}

/**
 * 用某一档 header 形态下完一次，返回落盘字节数。**顺序里有铁律**：
 *
 *   建任务 → 等完成 → 在**下载管理器落下的那一份**上对账 → 长度对了才搬进 .part
 *
 * `.part` 写完就会被改名转正成缓存（同一首歌以后一直播它），所以「长度对得上」这道验收
 * 必须发生在它见到字节**之前**——否则失败路径稍有不慎就会留下一份冒充音频的幽灵缓存。
 */
async function downloadOnceWithShape(
  mod,
  url,
  fileName,
  landedUri,
  partUri,
  shape,
  expected,
  onProgress,
  isCancelled,
  prog
) {
  const token = await createDownloadTask(mod, url, headerStringOf(shape), fileName)
  const uri = await waitDownloadComplete(
    mod,
    token,
    landedUri,
    partUri,
    expected,
    onProgress,
    isCancelled,
    prog
  )
  const got = await sizeOf(uri)

  if (expected && got !== expected) {
    const err = new Error('整份下载长度不符（收到 ' + got + '/' + expected + ' 字节，' + shortUri(uri) + '）')
    if (got <= DENY_PAGE_MAX) {
      // 几百字节：CDN 的错误页。下载任务「成功」了，但请求头等于没带 —— 换一档形态重试。
      err.headerShapeSuspect = true
      console.warn('[AudioCache] 整份下载只有 ' + got + ' 字节，像是错误页（header 形态 ' + shape + '）')
    }
    throw err
  }
  if (!expected && got < MIN_AUDIO_BYTES) {
    // 探不到总长（对账无从谈起）时，体积就是唯一判据：错误页一定很小
    const err = new Error('整份下载只有 ' + got + ' 字节（探不到总长，但这不像音频）')
    err.headerShapeSuspect = true
    throw err
  }

  if (prog && prog.fired) {
    // 边下边播已经开播：落点就是音频正在读的文件，搬运/改名留给 finalizeFor
    // （下一次查询该曲目时触发）—— 现在动它等于把在播的歌从脚底下抽走。
    console.log('[AudioCache] request.download 落盘完成（边下边播已开播）:', got, 'bytes（header=' + shape + '）')
    return got
  }
  if (uri !== partUri) await moveIntoPlace(uri, partUri)
  const final = await sizeOf(partUri)
  if (final !== got) throw new Error('搬进 .part 后长度不符（' + final + '/' + got + ' 字节）')
  console.log('[AudioCache] request.download 整份落盘完成:', got, 'bytes（header=' + shape + '）')
  return got
}

/**
 * 建下载任务（官方：success 给 token，fail(data, code)）。
 *
 * `header` **必须是字符串**：`@system.request.download` 的参数表里它是 String
 * （`@system.fetch` 的 header 才是 Object）。给对象会回
 * `code=202 args type error, feature system.request, method: download` ——
 * 任务根本建不起来，一个字节都不会下。这里把「建不起来」标成 noBytes：
 * 没有任何字节落地，所以换一档 header 形态重试是安全的。
 */
function createDownloadTask(mod, url, header, fileName) {
  return new Promise((resolve, reject) => {
    let settled = false
    const gateMs = CACHE_CFG.WHOLE_DOWNLOAD_CREATE || 15000
    // 建任务也要有闸门：`download` 既不回 success 也不回 fail 时（运行时静默吞掉调用）
    // 页面会一直挂着 —— 而拿不到 token 就还轮不到下载过程那两道闸门。
    const timer = setTimeout(() => {
      if (settled) return
      settled = true
      const err = new Error(
        '下载任务创建无响应（' +
          (gateMs >= 1000 ? Math.round(gateMs / 1000) + ' 秒' : gateMs + ' 毫秒') +
          '既没成功也没失败）'
      )
      err.noBytes = true
      reject(err)
    }, gateMs)
    const done = (fn, arg) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      fn(arg)
    }
    const onFail = (data, code) => {
      const msg = data === undefined || data === null ? '' : String(data)
      const err = new Error('下载任务创建失败 code=' + code + (msg ? ' ' + msg : ''))
      err.noBytes = true
      if (code === 202 || /type error|invalid|args/i.test(msg)) err.headerShapeSuspect = true
      done(reject, err)
    }
    try {
      mod.download({
        url,
        header,
        filename: fileName,
        success: (data) => done(resolve, data && data.token),
        fail: onFail,
      })
    } catch (e) {
      // 参数校验失败也可能是**同步抛**的（两种都有）：两条路都要接住，别让异常穿透
      onFail(e && e.message ? e.message : e, 202)
    }
  })
}

/** header 字符串的打包（形态说明见 HEADER_SHAPES） */
function headerStringOf(shape) {
  const h = cdnHeaders()
  if (shape === 'json') return JSON.stringify(h)
  if (shape === 'line') return 'User-Agent: ' + h['User-Agent']
  const sep = shape === 'crlf' ? '\r\n' : '\n'
  return Object.keys(h)
    .map((k) => k + ': ' + h[k])
    .join(sep)
}

/** 探明过的形态排第一（另一条仍留作兜底），没探明时按 HEADER_SHAPES 的顺序 */
function headerShapesToTry() {
  if (!headerShape) return HEADER_SHAPES.slice()
  return [headerShape].concat(HEADER_SHAPES.filter((s) => s !== headerShape))
}

/**
 * 这一档失败之后还该不该换下一档？**只在没拿到可用字节时换**：
 *   noBytes             —— 任务建不起来 / 下完是 0 字节，什么都没落地；
 *   headerShapeSuspect  —— 下回来的只有几百字节，是 CDN 的错误页（请求头等于没带）。
 * 反过来，「像音频但长度对不上」（截断）**不换**：那是网络或服务端的事，换 header 形态
 * 既救不了又要再下一遍整份。
 */
function canRetryWithAnotherHeader(e) {
  return !!(e && (e.noBytes || e.headerShapeSuspect))
}

/** 把下载管理器落下的文件搬进我们的 .part（move 不行就 copy + 删源，都在缓存分区内） */
async function moveIntoPlace(uri, partUri) {
  try {
    await moveFile(uri, partUri)
    return
  } catch (e) {
    console.warn('[AudioCache] 下载文件 move 失败，改 copy：', e && e.message ? e.message : e)
  }
  await copyFile(uri, partUri)
  await deleteFile(uri)
}

/**
 * 所有形态都失败后的收尾报错。同一句话重复四遍没有信息量，所以原因去重：
 * 四档结果一样就说「N 档都一样」，不一样才逐档列出（这时差异本身就是线索）。
 * 长度在**这里**统一收口 —— 收集时不截短，免得把设备原话（`args type error, feature …`）
 * 这种唯一凭据切掉；去重之后通常只剩一句，几乎不会真的触发这个上限。
 */
function describeDownloadFailure(lastErr, tried, shapeCount, expected) {
  const reasons = []
  for (let i = 0; i < tried.length; i++) {
    const r = tried[i].slice(tried[i].indexOf('→') + 1)
    if (reasons.indexOf(r) < 0) reasons.push(r)
  }
  const raw = reasons.length === 1 ? shapeCount + ' 档 header 形态都一样：' + reasons[0] : tried.join('；')
  const detail = raw.length > 170 ? raw.slice(0, 170) + '…' : raw
  const err = new Error('整份原生下载失败（' + detail + '，总长 ' + (expected || '未知') + '）')
  err.noBytes = !!(lastErr && lastErr.noBytes)
  return err
}

/** 一句话、限长的错误摘要（手表屏幕上那行字要装得下；换行会把 marquee 弄乱） */
function shortErr(e, max) {
  const limit = max || 60
  const s = String((e && e.message) || e || '')
    .replace(/\s+/g, ' ')
    .trim()
  return s.length > limit ? s.slice(0, limit) + '…' : s
}

/** `@system.request` 可能不存在（支持明细里部分机型没有）→ require + try/catch，同 api.js 的写法 */
function requestModule() {
  try {
    const mod = require('@system.request')
    const api = mod && typeof mod.download === 'function' ? mod : mod && mod.default
    return api && typeof api.download === 'function' ? api : null
  } catch (e) {
    return null
  }
}

/**
 * 1 字节 Range 探总长。**只认响应头**（arraybuffer 的 data 可能为空，HEAD/GET 都一样），
 * 顺便确认请求头没被吞（拿到 403 就说明这条路也一样被拒，早点说清楚）。
 */
async function probeRemoteSize(url) {
  try {
    const res = await fetchRangeOnce(url, 0, 0, 'arraybuffer')
    if (res.httpCode === 403 || res.httpCode === 401 || res.httpCode === 410) {
      throw new Error('CDN 拒绝（HTTP ' + res.httpCode + '，' + describeRejection(url, res) + '）')
    }
    const range = res.headers ? parseContentRange(getHeader(res.headers, 'Content-Range')) : null
    return range && range.total ? range.total : 0
  } catch (e) {
    if (e && /^CDN 拒绝/.test(e.message || '')) throw e
    console.warn('[AudioCache] 探总长失败（继续下，只是没有长度对账）：', e && e.message ? e.message : e)
    return 0
  }
}

/**
 * 等下载完成。总闸 + 空闲闸都在 config.AUDIO_CACHE 里；进度靠轮询文件大小
 * （轮得到就报，轮不到也不影响正确性 —— 下载任务的完成回调才是唯一的完成信号）。
 *
 * 轮询要盯**下载管理器自己的落点**（landedUri）：它是按 filename 落在缓存目录根上的，
 * 我们要的 .part 在它搬过去之前根本不存在。盯错了位置进度永远是 0、空闲闸门也永远不生效
 * （`seen > 0` 才算数），这条路的两个闸门就只剩总超时一个。
 */
function waitDownloadComplete(mod, token, landedUri, partUri, expected, onProgress, isCancelled, prog) {
  const deadline = Date.now() + (CACHE_CFG.WHOLE_DOWNLOAD_TIMEOUT || 300000)
  const idleLimit = CACHE_CFG.WHOLE_DOWNLOAD_IDLE || 60000
  const pollMs = CACHE_CFG.WHOLE_DOWNLOAD_POLL || 1000
  let seen = 0
  let lastGrow = Date.now()

  return new Promise((resolve, reject) => {
    let settled = false
    let timer = null
    const finish = (fn, arg) => {
      if (settled) return
      settled = true
      if (timer) clearInterval(timer)
      fn(arg)
    }
    try {
      mod.onDownloadComplete({
        token,
        // 拿不到 uri 时退回**我们预测的落点**（下载管理器按 filename 落在缓存目录根上）：
        // 退回 partUri 是错的 —— 那一份要等我们搬过去才存在
        success: (data) => finish(resolve, (data && data.uri) || landedUri),
        fail: (data, code) =>
          finish(reject, new Error('下载失败 code=' + code + (data ? ' ' + data : ''))),
      })
    } catch (e) {
      finish(reject, e)
      return
    }
    // 进度/闸门轮询。timer 在 finish 之前可能还没赋值（onDownloadComplete 同步回调的
    // 极端情况），所以 finish 里对 timer 做了空值保护 —— 别在这里赌回调一定是异步的。
    timer = setInterval(async () => {
      if (settled) return
      if (typeof isCancelled === 'function' && isCancelled()) {
        finish(reject, makeBridgeError(BRIDGE_ERRORS.CANCELLED, '传输已被取消（整份下载）'))
        return
      }
      if (Date.now() > deadline) {
        finish(reject, new Error('整份下载超时（' + Math.round((CACHE_CFG.WHOLE_DOWNLOAD_TIMEOUT || 0) / 1000) + ' 秒没结束）'))
        return
      }
      let got = await sizeOf(landedUri)
      let gotUri = landedUri
      if (!got && landedUri !== partUri) {
        const alt = await sizeOf(partUri)
        if (alt) {
          got = alt
          gotUri = partUri
        }
      }
      if (got > seen) {
        seen = got
        lastGrow = Date.now()
        // 边下边播：落够阈值就把**长着字节的那份**交给播放器（完成回调给的落点 uri
        // 形态可能与预测不同，所以交付的是这次轮询里真有字节的 uri）
        if (prog && !prog.fired && prog.shouldFire(got, expected)) prog.fire(gotUri, got)
        if (typeof onProgress === 'function') {
          try {
            onProgress(got, expected || null)
          } catch (e) {
            // 进度回调不许影响下载
          }
        }
      } else if (seen > 0 && Date.now() - lastGrow > idleLimit) {
        finish(reject, new Error('整份下载停滞（已 ' + seen + ' 字节，' + Math.round(idleLimit / 1000) + ' 秒没动）'))
      }
    }, pollMs)
  })
}

/** 文件字节数（拿不到就当 0：它是进度与对账用的，不是正确性的前提） */
async function sizeOf(uri) {
  try {
    const info = await callFs('get', { uri })
    return (info && Number(info.length)) || 0
  } catch (e) {
    return 0
  }
}

/* ------------------------------ 取一段字节（两种读法） ------------------------------ */

/**
 * 这台设备上「哪种响应体读法真能拿到字节」—— 探明一次就记住，不再每块都试。
 *
 * 为什么要有这个开关：实测部分机型上 `responseType:'arraybuffer'` 会回
 * **206 + 合法 Content-Range + 空 data** —— 状态码、请求头、防盗链全都正常，就是没有字节。
 * 这是一种**读法层面的失败**（重试同一读法不会变），处置是换读法：
 *
 *   arraybuffer  省事、不碰磁盘，字节直接进 JS 堆（正常机型走这条）；
 *   file         `responseType:'file'` 让框架原生把这一段落到临时文件，
 *                我们再分片读回追加（见 appendChunkBytes）。慢链路上一段 256 KB
 *                在 60-70 KiB/s 下要走 4 秒，读法试错一次就是 4 秒，所以**必须记住**，
 *                不能每块都先撞一次墙。
 *
 * 记的是「设备能力」不是「这次请求」：同一台设备上所有地址、所有曲目都通用。
 * 每个 page 一个 JS VM，所以每个 VM 各探一次（可接受：探测只在首次落盘时发生）。
 */
let bodyMode = null // null = 未探测 | 'arraybuffer' | 'file'

/**
 * 本段用多大 Range —— Range 档位阶梯的当前档（探明后锁存，见 config.CHUNK_STEPS）。
 *
 * 为什么除了「换读法」还要「缩段」：256 KB 的 arraybuffer 响应可能回
 * **206 + 合法 Content-Range + 空 data**，而传输本身是通的（头都对）—— 更像运行时
 * 把太大的响应体丢了（快应用规范里 fetch 明写「数据大小不能超过 100k」）。
 * 这类失败光换读法救不回来（file 读法在部分机型上又读不出来），而**把段改小**
 * 是唯一一条不换数据通道还能继续试的路。探明成功过就一直用它。
 */
let rangeBytes = RANGE_STEPS[0]

/**
 * 原生机型走哪条数据通道：'fetch'（Range 分块，可续传，优先）| 'request'
 * （`@system.request.download` 整份原生下载，见 downloadViaRequest）。
 *
 * 只有「fetch 这条路根本取不到字节」（不是网络问题）才换通道，且换过就锁存 ——
 * 一台设备取不到字节的原因不会因为换首歌而改变，没必要每首都先撞一次墙。
 */
let nativeChannel = 'fetch'

/**
 * `@system.request.download` 的 header 打包形态（HEADER_SHAPES 之一）。同 nativeChannel 是
 * 一次性探明就锁存的：一台设备的下载管理器只认一种解析方式，探明了就没必要每首都撞墙。
 * 探明的判据是**长度对账通过**（不是「任务建起来了就算」—— 任务建起来但请求头被丢掉，
 * 下回来的是 CDN 的错误页，那和没带头的区别只有长度对账看得出来）。
 */
let headerShape = null

/* --------------------- 设备能力锁存的落盘（跨 VM / 跨启动） --------------------- */

let capsLoaded = false

/**
 * 把「这台机拿不到字节」这类**设备事实**读回来。每个 VM 只读一次（首次原生下载时）：
 * storage 是全局原生服务，各 page VM、各次启动读到的是同一份 —— 上个 VM（或上次运行）
 * 已经探明 fetch 链路不通、下载器认哪种 header 形态，这边就不用再把整条探测阶梯
 * 撞一遍（蓝牙上那是好几秒的白白下载，而且每换一个页面 VM 都要重来一次）。
 *
 * 只认「设备拒绝」类判定（空响应体 / 临时文件读不回 —— 都是确定性失败，与网络无关），
 * 网络超时（curl 28）一律**不写**：那可能是任何人的网络抖了一下，不是这台机的罪。
 */
async function loadDlCaps() {
  if (capsLoaded) return
  capsLoaded = true
  try {
    const saved = await Storage.getJson(CONFIG.STORAGE_KEYS.DL_CAPS, null)
    if (!saved || typeof saved !== 'object') return
    if (saved.channel === 'request') {
      nativeChannel = 'request'
      console.log('[AudioCache] 设备能力（storage）：fetch 取不到字节，直接走整份原生下载')
    }
    if (saved.headerShape && HEADER_SHAPES.indexOf(saved.headerShape) >= 0) {
      headerShape = saved.headerShape
    }
  } catch (e) {
    // 读不到就当没存过：照常探测，别让一次 storage 异常堵死下载
  }
}

/**
 * 探明即落盘（尽力而为，失败不影响下载）。channelOverride 用于「fetch 判死」的当下 ——
 * 那个判定独立于 request 通道的成败：fetch 取不到字节是这台机的运行时事实，
 * 就算这次 request 也恰好失败（网络抖动），下次也犯不着再撞一遍 fetch 阶梯。
 *
 * **读-合并-写**，不是整份覆盖：两个字段都是设备事实，本 VM 只更新自己这次探明的那个，
 * 别的 VM / 上次运行探明的另一个字段必须原样保留（本 VM 不知道 ≠ 它不存在）。
 */
function saveDlCaps(channelOverride) {
  const channel = channelOverride || (nativeChannel === 'request' ? 'request' : '')
  if (!channel && !headerShape) return
  Storage.getJson(CONFIG.STORAGE_KEYS.DL_CAPS, null)
    .then((prev) => {
      const merged = {
        channel: channel || (prev && prev.channel) || '',
        headerShape: headerShape || (prev && prev.headerShape) || '',
      }
      if (!merged.channel && !merged.headerShape) return
      return Storage.setJson(CONFIG.STORAGE_KEYS.DL_CAPS, merged)
    })
    .catch(() => {})
}

/**
 * 仅供离线自检复位探测状态（真机上单向：探明了就一直用它）。复位的是**三道锁存**：
 * 「响应体读法」（arraybuffer/file，见 bodyMode）、「临时文件读法」（direct/readtext/copy，
 * 见 tmpRecipe）、「数据通道」（fetch/request，见 nativeChannel），并把 Range 档位退回首档、
 * 边下边播的待转正表清空。与 api.js 的 __resetNativeProbe() 同一用途 —— 测试要能装成「另一台设备」。
 *
 * 注意**不动** capsLoaded / storage 里的设备能力：那是全设备共享的事实，
 * 本 VM 已经读过就不会再读第二遍（测试要装「读过 storage 的另一台设备」就开新 VM）。
 */
export function __resetBodyMode() {
  bodyMode = null
  tmpRecipe = null
  nativeChannel = 'fetch'
  headerShape = null
  rangeBytes = RANGE_STEPS[0]
  pendingFinalize.clear()
}

/**
 * 把 Range 档位降到下一档，返回是否降成功（降到最后一档还拿不到字节就认栽）。
 *
 * 降档时要**把两道读法锁存一起清掉**：大响应体拿不到字节的结论不能套到小响应体上
 * （小段很可能 arraybuffer 直接就给字节了，那是最省事的路）。
 */
function shrinkRange() {
  const i = RANGE_STEPS.indexOf(rangeBytes)
  if (i < 0 || i >= RANGE_STEPS.length - 1) return false
  rangeBytes = RANGE_STEPS[i + 1]
  bodyMode = null
  tmpRecipe = null
  console.warn('[AudioCache] Range 档位降到 ' + rangeBytes + ' 字节，读法重新探')
  return true
}

/** 读法顺序：探明过就先用它（另一条仍留作兜底），没探明时先试最省事的那条 */
function bodyModesToTry() {
  return bodyMode === 'file' ? ['file', 'arraybuffer'] : ['arraybuffer', 'file']
}

/** 单块：失败重试同一段（写成独立函数是为了让重试语义一眼可见） */
async function fetchRangeWithRetry(url, from, to, isCancelled) {
  let last = null
  for (let attempt = 1; attempt <= CHUNK_RETRIES; attempt++) {
    if (typeof isCancelled === 'function' && isCancelled()) {
      throw makeBridgeError(BRIDGE_ERRORS.CANCELLED, '传输已被取消（重试前）')
    }
    try {
      const res = await fetchRangeChunk(url, from, to)
      assertBodyUsable(res, from, to)
      return res
    } catch (e) {
      last = e
      // 空响应体是**确定性**失败（运行时丢大响应体 / 读法不适用 —— 重试同一读法不会变），
      // 同段重试只会再白下一整块（蓝牙上一块 256 KB 就是四五秒）—— 立刻交给缩段/换通道。
      if (e && e.isEmptyBody) throw e
      console.warn(
        '[AudioCache] 分块 ' +
          from +
          '-' +
          to +
          ' 第 ' + attempt + '/' + CHUNK_RETRIES + ' 次失败：',
        e && e.message ? e.message : e
      )
    }
  }
  throw last || new Error('分块下载失败')
}

/**
 * 2xx 却没有可落盘的字节 → **当这一块失败**（抛出去让重试接住）。
 *
 * 空响应体起码有两种成因，处置完全不同：
 *   传输被掐断（慢链路/蓝牙抖动）→ 重试同一段就好，而且什么都没写，重试是安全的；
 *   读法不适用（本机 arraybuffer 拿不到字节）→ 换读法（fetchRangeChunk 里做）。
 * 两种都收敛于「把这一块当失败」，所以判定放在重试层。
 *
 * 报错必须带上**本机实际给的响应体形态**：手表上屏幕那行字就是唯一线索。
 *
 * 这个标记会**立刻原样上抛**（不在同段重试）：确定性失败多试一次就多白下一整块，
 * 收敛交给缩段（小段可能根本不需要走丢体的读法）与换通道。
 */
function assertBodyUsable(res, from, to) {
  if (!(res.httpCode >= 200 && res.httpCode < 300)) return // 403 之类原样交给上层
  if (res.bytes || res.tmpUri) return
  const err = new Error('分块响应体为空（' + describeBodyFailure(res, from, 0) + '）')
  // 标记「这不是网络问题，是字节没到手」：上层据此缩 Range 档位、换数据通道，
  // 而不是去换候选地址（同一个地址换个备份节点也拿不到字节）
  err.isEmptyBody = true
  throw err
}

/**
 * 取一段字节：按「本机能拿到字节的读法」来，拿不到就换读法并记住换成了哪条。
 *
 * 只处理「2xx 但没字节」这一种情况；非 2xx 原样返回（403 的正文是错误页，
 * 那是业务层要判的东西，不是读法问题，别在这里换读法重发一遍）。
 */
async function fetchRangeChunk(url, from, to) {
  const modes = bodyModesToTry()
  const tried = []
  let last = null
  for (let i = 0; i < modes.length; i++) {
    const res = await fetchRangeOnce(url, from, to, modes[i])
    last = res
    if (!(res.httpCode >= 200 && res.httpCode < 300)) return res
    if (res.bytes || res.tmpUri) {
      if (bodyMode !== modes[i]) {
        console.log('[AudioCache] 响应体读法：' + modes[i] + (bodyMode ? '（换过来了）' : '（首次探明）'))
        bodyMode = modes[i]
      }
      return res
    }
    tried.push(modes[i] + '→' + describeBodyShape(last.body))
    console.warn('[AudioCache] ' + modes[i] + ' 读法没拿到字节，换读法：' + describeBodyShape(last.body))
  }
  // 两条读法都拿不到字节：把「试过哪些、各自拿到什么」挂在结果上，交给 assertBodyUsable 报出去
  if (last) last.triedShapes = tried
  return last
}

/**
 * 单次 Range 请求。resolve = 拿到响应，reject = 网络层失败（超时等）。
 * 纯网络函数、不碰文件系统 —— 离线自检里可直接喂桩断言重试与续传。
 *
 * @param {'arraybuffer'|'file'} mode 读响应体的方式（见 bodyMode 的注释）
 * @returns {Promise<{httpCode:number, headers:object, bytes:Uint8Array|null,
 *                    tmpUri:string|null, mode:string, body:*}>}
 *   bytes  —— 已在 JS 堆里的字节（arraybuffer 读法，或框架无视 responseType 直接给了字节）
 *   tmpUri —— 框架落下的临时文件 uri（file 读法；不是字节，读回见 pumpTmpFile）
 * 两者可能都为空：那就是「状态码正常但没字节」，由上层判定并报错。
 */
function fetchRangeOnce(url, from, to, mode) {
  return new Promise((resolve, reject) => {
    let settled = false
    const bad = (data, code) => {
      if (settled) return
      settled = true
      // 底层给的人话优先（Vela 的 fetch 把 libcurl 的说明透传在 data 里）；
      // 没有 data 时才自己拼 code —— **不要把两者叠起来**，否则上层
      // describeError 会拼出 "code=28 网络超时 分块请求失败 code=28" 这种重复话
      const detail = typeof data === 'string' && data ? data : ''
      const err = new Error(detail || '分块请求失败' + (code !== undefined ? ' code=' + code : ''))
      err.code = code
      reject(err)
    }
    const ok = (val) => {
      if (settled) return
      // 状态码字段名只在这里认一次：`code`（官方 success 形态）优先，`status` 只是别名兜底。
      // 认不出来时**不猜也不放行**（把 undefined 漏上去就会变成「CDN 返回 undefined」，
      // 排查时完全看不出发生了什么），而是把本机实际给的字段名写进报错里。
      const res = normalizeFetchResult(val)
      if (!(res.httpCode > 0)) {
        bad('CDN 响应没有状态码（字段：' + describeFetchShape(val) + '）')
        return
      }
      settled = true
      // 给的是**文件 uri 形态的字符串**就按临时文件处理 —— 不论 responseType 写了什么。
      // 官方 responseType 表里「不写 responseType 且内容不是文本」本来就回临时文件 uri，
      // runtime 也可能无视 arraybuffer 直接给 uri。不认出来就会走 bytesOfBody
      // （它认字符串为二进制串），把**uri 文本**当音频写进 .part —— 静默的坏缓存，
      // 比报错难查一百倍。
      const isTmpUri = typeof res.body === 'string' && looksLikeFileUri(res.body)
      resolve({
        httpCode: res.httpCode,
        headers: res.headers,
        body: res.body,
        bytes: isTmpUri ? null : bytesOfBody(res.body),
        tmpUri: isTmpUri ? res.body : null,
        mode,
      })
    }

    let fn
    try {
      const mod = require('@system.fetch')
      fn = mod && typeof mod.fetch === 'function' ? mod.fetch : mod
    } catch (e) {
      reject(new Error('本机没有 @system.fetch，无法分块落盘：' + (e && e.message ? e.message : e)))
      return
    }
    if (typeof fn !== 'function') {
      reject(new Error('@system.fetch 形态异常，无法分块落盘'))
      return
    }

    let maybePromise
    try {
      maybePromise = fn({
        url,
        method: 'GET',
        responseType: mode,
        header: Object.assign({ Range: 'bytes=' + from + '-' + to }, cdnHeaders()),
        success: ok,
        fail: bad,
      })
    } catch (e) {
      bad(e)
      return
    }
    if (maybePromise && typeof maybePromise.then === 'function') maybePromise.then(ok, bad)
  })
}

/**
 * uri 形态判断：有 scheme 的（internal://file://tmp://…）或以 / 开头的绝对路径。
 *
 * 判据必须**严**，因为它决定「一串字符串是 uri 还是二进制字节」。官方 uri 字符集是
 * `0-9a-zA-Z_-./%:`，所以这里只认可打印 ASCII：音频字节里出现控制字符或 >0x7e 的概率
 * 在几千字节里几乎是 1，而反过来（把 uri 文本当字节写进 .part）是**静默**的坏缓存 ——
 * 长度不对但看着像下好了，代价大得多。
 */
function looksLikeFileUri(value) {
  const s = String(value || '')
  if (!s || s.length > 512) return false
  if (!/^[\x20-\x7e]+$/.test(s)) return false
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(s) || s.charAt(0) === '/'
}

/**
 * 把这一段字节追加进 .part，返回实际写入的字节数。两种来源：
 *
 *   res.bytes  —— 字节已在 JS 堆里，一次写完；
 *   res.tmpUri —— 框架把这一段原生落在**临时文件**里，要读回来（pumpTmpFile 的两条读法）。
 *
 * 进度在这里逐片上报（调用方不要再报一次，否则同一段会报两遍）。
 * 写盘一律 append：落点由系统维护，我们不赌 position 语义。
 *
 * @returns {Promise<number>} 写入字节数；0 表示这段真的没有字节（上游会报错）
 */
async function appendChunkBytes(res, partUri, base, total, onProgress) {
  const report = (done) => {
    if (typeof onProgress === 'function') onProgress(done, total)
  }
  if (res.bytes && res.bytes.length) {
    await writeAt(partUri, res.bytes, base)
    report(base + res.bytes.length)
    return res.bytes.length
  }
  if (!res.tmpUri) return 0
  return pumpTmpFile(res, partUri, base, report)
}

/**
 * 「临时文件怎么读回来」—— 与 bodyMode 同源的第二道锁存。
 *
 * 实测 `responseType:'file'` 会给出 uri，但拿它直接
 * `file.readArrayBuffer` 回的是 **code=202 invalid arguments**。原因是**分区语义**：
 * 官方「文件存储」章把 Temp 分区写成「从外部映射的临时文件，**只读，只能通过特定
 * API 获取（如 file.readText）**」—— 框架给的是 `internal://tmp/…`，这个分区不是
 * 随便哪个 file 接口都能读的（202 参数错误，而不是 301 不存在，正是「uri 不合法」）。
 *
 * 那怎么把字节取出来？两条官方线索：
 *
 *   'readtext' —— 官方「文件组织」章点名的唯一 tmp 读法：「Temp……只读，**只能通过
 *                 特定 API 获取（如 file.readText）**」。代价是它没有 position/length
 *                 （永远读整个文件），而且二进制要经文本接口 —— 所以必须**自证无损**，
 *                 见 readTmpAsText。
 *   'copy'     —— 官方参数表的不对称：`file.move` 写「srcUri/dstUri **都不能**是 tmp」，
 *                 而 `file.copy` 只写「**dstUri** 不能是 tmp」—— `srcUri` 没有任何限制。
 *                 「原生整份拷出到自己的分区再读」就是官方留的这条路。
 *   'direct'   —— 直接读 tmp uri（省一次原生拷贝；tmp 可读的机型走这条）
 *
 * 与 bodyMode 一样：**探明一次就记住**。探错一次只是一次 IPC（比一次 4 秒的网络
 * 试错便宜得多），但没必要每块都撞一遍墙。每个 page 一个 JS VM，各探各的。
 */
let tmpRecipe = null // null = 未探测 | 'direct' | 'readtext' | 'copy'

/** 中转文件后缀：`<…>.part.tmp<起点>`（属于 .part 家族，见 keyFromName/isPartName） */
const SCRATCH_SUFFIX = '.tmp'

/** 中转文件 uri：**每次拷出都用新名字**（带本段起点），绕开「dst 已存在」的语义分歧 */
function scratchUriOf(partUri, base) {
  return partUri + SCRATCH_SUFFIX + base
}

/**
 * 读法顺序。探明过就先用它（其余仍留作兜底）；没探明时：
 *   direct（不拷不读文本，最省） → readtext（官方点名的 tmp 读法） → copy（原生拷出）
 * 拷出排最后是因为它每块都要多一次原生拷贝 —— 那是 CPU/IO 换来的确定性。
 */
const TMP_RECIPES = ['direct', 'readtext', 'copy']

function tmpRecipesToTry() {
  if (tmpRecipe) {
    const rest = TMP_RECIPES.filter((r) => r !== tmpRecipe)
    return [tmpRecipe].concat(rest)
  }
  return TMP_RECIPES.slice()
}

/**
 * 把框架落在临时文件里的这一段搬进 .part。
 *
 * **铁律：换读法只能发生在「一个字节都没写进 .part」之前。** 所以先只读一片当探针，
 * 读得出来才落第一笔 —— 一旦部分写过再换读法，文件里就是两段来源不同的字节拼在一起，
 * 而 .part 是会转正的（转正即「完整缓存」），那首歌就永久废了。
 * 探针之后中途读不动，就当这段截断，交给上层（got !== span 会暴露）。
 *
 * 三种读法都拿不到字节时抛出的错误带 `tmpUnreadable = true` 标记：**这不是网络问题**，
 * 上层据此缩 Range 档位、换数据通道，而不是去换候选地址。
 *
 * 中转文件用完即删；失败留下的由 cleanupOrphans / pruneCache 按 .part 家族扫掉。
 *
 * @returns {Promise<number>} 写进 .part 的字节数
 */
async function pumpTmpFile(res, partUri, base, report) {
  // 这段该有多少字节：206 认 Content-Range 的跨度，200 认 Content-Length。
  // 认不出来（罕见：B 站两个头总有其一）就只能整段读回，探针那片即整段。
  const span = declaredSpan(res.headers)
  const recipes = tmpRecipesToTry()
  const tmpUri = res.tmpUri
  const failures = []

  for (let i = 0; i < recipes.length; i++) {
    const recipe = recipes[i]
    let scratch = null
    let wrote = 0
    try {
      let srcUri = tmpUri
      if (recipe === 'copy') {
        scratch = scratchUriOf(partUri, base)
        await copyFile(tmpUri, scratch) // 原生整份拷贝：不占 JS 堆
        srcUri = scratch
      }
      let probe = null
      if (recipe === 'readtext') {
        // readText 没有 position/length：这一段必须一次进堆（段大小由 Range 档位控制）
        probe = await readTmpAsText(srcUri, span)
      } else {
        probe = await readTmpAt(srcUri, 0, span ? Math.min(READ_SLICE, span) : undefined)
        if (!probe || !probe.length) throw new Error('读回 0 字节')
      }
      if (tmpRecipe !== recipe) {
        console.log('[AudioCache] 临时文件读法：' + recipe + (tmpRecipe ? '（换过来了）' : '（首次探明）'))
        tmpRecipe = recipe
      }
      await writeAt(partUri, probe, base)
      wrote = probe.length
      report(base + wrote)
      // readText 在探针那一步就把整段读完了（它没有 position/length）；
      // span 为 0（没有声明长度）时同理 —— 两种都不该再进分片循环
      if (recipe === 'readtext' || !span) return wrote
      while (wrote < span) {
        const want = Math.min(READ_SLICE, span - wrote)
        const slice = await readTmpAt(srcUri, wrote, want)
        if (!slice || !slice.length) break
        await writeAt(partUri, slice, base + wrote)
        wrote += slice.length
        report(base + wrote)
      }
      return wrote
    } catch (e) {
      if (wrote > 0) throw e // 已经写进 .part 了：换读法会拼出两段来源不同的字节
      failures.push(recipe + '→' + readFailureText(e))
      console.warn('[AudioCache] 临时文件读法 ' + recipe + ' 没拿到字节：', e && e.message ? e.message : e)
    } finally {
      if (scratch) await deleteFile(scratch)
    }
  }
  // 三种读法都不行：把「试过什么、各是什么结果、uri 长什么样、文件接口能不能看见它」
  // 全写进那一行字 —— 手表屏幕上是唯一的线索来源，下次才不用再猜。
  const err = new Error(
    '临时文件读回失败（' +
      failures.join('；') +
      '，tmp uri「' + shortUri(tmpUri) + '」，' + (await describeTmpProbe(tmpUri)) +
      '）'
  )
  err.tmpUnreadable = true
  throw err
}

/**
 * tmp uri 的两条**只读**探针：文件接口到底"看不看得见"这个文件。
 *
 * 「读不出来」有好几种成因，下一步的修法完全不同，所以顺手把结论写进报错：
 *   access=ok get=ok(N)  —— 文件在、长度也报得出：只是不许 readArrayBuffer/copy 这类用法
 *   access=code=202 …    —— 这个 uri 形态文件接口根本不认：该怀疑 uri 本身，而不是权限
 */
async function describeTmpProbe(uri) {
  const parts = []
  try {
    await callFs('access', { uri })
    parts.push('access=ok')
  } catch (e) {
    parts.push('access=' + readFailureText(e).replace(/^file\.access 失败 /, ''))
  }
  try {
    const info = await callFs('get', { uri })
    parts.push('get=ok(' + ((info && Number(info.length)) || 0) + ')')
  } catch (e) {
    parts.push('get=' + readFailureText(e).replace(/^file\.get 失败 /, ''))
  }
  return parts.join(' ')
}

/**
 * `readText` 读法：官方唯一点了名的 tmp 读法。它没有 position/length，读的永远是
 * **整个临时文件**，所以段的大小就是堆占用（由 Range 档位控制）。
 *
 * 二进制走文本接口有个前提：**字符串与原始字节必须一一对应**。三种映射都试，
 * 每一种都**当场自证**（验不过就当这条不通，绝不把可疑字节写进 .part）：
 *
 *   encoding:'base64' —— base64 文本：字母表必须干净，解出来的长度必须等于声明长度；
 *   默认（UTF-8）      —— 每个码元 ≤ 0xFF、没有替换字符 U+FFFD（真解过 UTF-8 的二进制
 *                        必然留下替换字符或大于 0xFF 的码元），且字符数 === 声明字节数；
 *   encoding:'latin1'  —— 同上（有些实现只在显式给 latin1 时才逐字节映射）。
 *
 * 声明长度是这套自证的锚：UTF-8 解码会把多字节序列压成更少的字符，
 * 「字符数 === 字节数」这一条就能把它挡在门外（实得字符数会写进报错里，可自证）。
 */
async function readTmpAsText(uri, span) {
  const attempts = []
  const tries = [
    { encoding: 'base64', pick: (text) => base64ToBytesStrict(text, span) },
    { encoding: null, pick: (text) => binaryTextToBytesStrict(text, span) },
    { encoding: 'latin1', pick: (text) => binaryTextToBytesStrict(text, span) },
  ]
  for (let i = 0; i < tries.length; i++) {
    const t = tries[i]
    const label = t.encoding || '默认'
    try {
      const text = await readText(uri, t.encoding)
      const bytes = t.pick(text)
      if (bytes && bytes.length) return bytes
      attempts.push(label + ':空文本')
    } catch (e) {
      attempts.push(label + ':' + readFailureText(e))
    }
  }
  throw new Error(attempts.join('，'))
}

/** readText：官方 success 形态是 {text}；失败信息与 readTmpAt 同一种短形态 */
function readText(uri, encoding) {
  return new Promise((resolve, reject) => {
    const opts = { uri }
    if (encoding) opts.encoding = encoding
    try {
      file.readText(
        Object.assign({}, opts, {
          success: (data) => {
            const text =
              data && typeof data.text === 'string'
                ? data.text
                : typeof data === 'string'
                  ? data
                  : ''
            resolve(text)
          },
          fail: (data, code) => reject(new Error('code=' + code + (data ? ' ' + data : ''))),
        })
      )
    } catch (e) {
      reject(e)
    }
  })
}

/**
 * base64 文本 → 字节。字母表不干净、长度对不上都**抛错**（消息会进报错里，可自证）。
 * 这里刻意不做任何容错：把可疑字节写进 .part，等于给那首歌下一个"永久坏缓存"。
 */
function base64ToBytesStrict(text, span) {
  const s = String(text || '').replace(/\s+/g, '')
  if (!s) throw new Error('空文本')
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(s)) throw new Error('不是 base64 文本')
  let binary = ''
  try {
    binary = base64Decode(s)
  } catch (e) {
    throw new Error('base64 解码失败')
  }
  if (!binary) throw new Error('base64 解出 0 字节')
  if (span && binary.length !== span) {
    throw new Error('长度不符（期望 ' + span + ' 实得 ' + binary.length + ' 字节）')
  }
  return binaryToUint8(binary)
}

/** 一字节一字符的文本 → 字节；长度不符或含非字节码元都抛错 */
function binaryTextToBytesStrict(text, span) {
  if (typeof text !== 'string' || !text.length) throw new Error('空文本')
  if (span && text.length !== span) {
    // UTF-8 解码会把多字节序列压成更少的字符 —— 这一条就能把"文本解码"挡在门外
    throw new Error('长度不符（期望 ' + span + ' 实得 ' + text.length + ' 字符）')
  }
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i)
    if (c === 0xfffd) throw new Error('含替换字符 U+FFFD（真按文本解码了）')
    if (c > 0xff) throw new Error('含非字节码元 U+' + c.toString(16))
  }
  return binaryToUint8(text)
}

/**
 * 读文件的一段（file.readArrayBuffer 的官方返回形态是 {buffer}）。
 * position/length 只在确实是数字时才放进参数对象 —— 运行时对 undefined 参数会报
 * `convertValueToNative: string arg is null or undefined`（api.js 里同一个坑）。
 *
 * 失败信息**刻意做短**（`code=202 invalid arguments`）：聚合报错要同时写几条读法的
 * 结论和 uri 形态，屏幕上那一行才装得下。
 */
function readTmpAt(uri, position, length) {
  return new Promise((resolve, reject) => {
    const opts = { uri, position }
    if (typeof length === 'number') opts.length = length
    try {
      file.readArrayBuffer(
        Object.assign({}, opts, {
          success: (data) => resolve(bytesOfBody(data)),
          fail: (data, code) => reject(new Error('code=' + code + (data ? ' ' + data : ''))),
        })
      )
    } catch (e) {
      reject(e)
    }
  })
}

/** 失败信息取一句话（短形态），拼进聚合报错 */
function readFailureText(e) {
  return e && e.message ? e.message : String(e)
}

/** uri 只留开头一段：屏幕那行字要装得下，scheme 才是最要紧的信息 */
function shortUri(uri) {
  const s = String(uri || '')
  return s.length > 44 ? s.slice(0, 44) + '…' : s
}

/** 这一段声明的字节数：206 用 Content-Range 跨度，200/其它用 Content-Length；都没有则 0 */
function declaredSpan(headers) {
  const range = parseContentRange(getHeader(headers || {}, 'Content-Range'))
  if (range && range.end >= range.start) return range.end - range.start + 1
  const len = parseContentLength(getHeader(headers || {}, 'Content-Length'))
  return len > 0 ? len : 0
}

/**
 * 「没有字节」的描述。手表上只有屏幕上这一行字，所以把能自证的都带上：
 *   状态码、这段的起点、声明长度、本机给的响应体形态、试过的读法。
 */
function describeBodyFailure(res, from, total) {
  const parts = ['HTTP ' + res.httpCode]
  if (from > 0) parts.push('起点 ' + from)
  const span = declaredSpan(res.headers)
  if (span) parts.push('声明 ' + span + ' 字节')
  if (total) parts.push('全曲 ' + total + ' 字节')
  parts.push('本机 data ' + describeBodyShape(res.body))
  if (res.triedShapes && res.triedShapes.length) parts.push('试过 ' + res.triedShapes.join('；'))
  return parts.join('，')
}

/** 追加写一块（append 的落点由系统维护，必须串行 —— 见 streamToFile 的同一纪律） */
function writeAt(partUri, buffer, offset) {
  return new Promise((resolve, reject) => {
    try {
      file.writeArrayBuffer({
        uri: partUri,
        buffer,
        append: offset > 0,
        success: () => resolve(),
        fail: (data, code) =>
          reject(new Error('音频落盘失败 code=' + code + (data ? ' ' + data : ''))),
      })
    } catch (e) {
      reject(e)
    }
  })
}

/** headers 键名大小写不可靠，统一小写查 */
function getHeader(headers, name) {
  if (!headers) return ''
  const want = String(name).toLowerCase()
  for (const k in headers) {
    if (String(k).toLowerCase() === want) return headers[k]
  }
  return ''
}

/** 解析 content-length（字符串，可能不存在） */
function parseContentLength(value) {
  const n = parseInt(String(value || ''), 10)
  return isNaN(n) ? 0 : n
}

/** 'bytes 262144-524287/3000000' → {start, end, total} */
function parseContentRange(value) {
  const m = String(value || '').match(/bytes\s+(\d+)-(\d+)\/(\d+|\*)/i)
  if (!m) return null
  return {
    start: parseInt(m[1], 10),
    end: parseInt(m[2], 10),
    total: m[3] === '*' ? 0 : parseInt(m[3], 10),
  }
}

/** 只取起点：用来复核「服务器给的这一块，起点是不是我们要的那个位置」 */
function parseRangeOffset(value) {
  const r = parseContentRange(value)
  return r ? r.start : null
}

/**
 * 下载公共体：解析取流地址 → 落盘 → 转正 → 清理。
 * ensure（正式播放）与 prefetch（预取）共用，只有 keep 名单和日志前缀不同。
 *
 * **候选地址**：B 站每条流都带 backupUrl（不同 CDN 节点），「同一首固定失败」
 * 往往就是主地址那个节点不行。这里逐条试：一条整份失败就删残片换下一条重来
 * （绝不跨地址续传 —— 不同节点可能给出字节不一致的内容）。
 *
 * **边下边播**（kind === 'play' 且未关掉，见 makeProgressive）：正式播放不等整份 ——
 * 落够阈值就把落点提前交付出去（外层 promise 提前 resolve），剩余字节的下载与收尾
 * 挂在返回值里的 done promise 上。整份先下完（小文件/预取/网桥）时行为与从前完全一致。
 *
 * @param {string} kind 'play'（可边下边播）| 'prefetch'（只整份）
 * @returns {Promise<{uri:string, cached:boolean, bytes?:number, progressive?:boolean,
 *                     done?:Promise<{uri:string, cached:boolean, bytes:number}>}>}
 */
async function downloadToCache(key, track, opts, kindLabel, kind) {
  const o = opts || {}
  const finalUri = uriOf(fileNameOf(key))
  const partUri = uriOf(partNameOf(key))

  // 1) 取流地址（可能多条候选）。resolveUrl 会顺手把 cid 补回曲目对象
  //    （预取也算数，正式播直接受益）
  const urls = normalizeCandidates(await o.resolveUrl(track))
  if (!urls.length) throw new Error('取流失败：没有可用的音频地址')
  await ensureDir()

  // 2) 边下边播：交付与收尾分成两个 promise。playableSignal 在落够阈值时兑现
  //    （提前交付），donePromise 在整份下完并登记收尾时兑现（真正完成）。
  //    谁先到算谁的：文件先下完了（小文件/收编），就是普通的一次整份交付。
  let firePlayable = null
  const playableSignal = new Promise((resolve) => {
    firePlayable = resolve
  })
  const prog = makeProgressive(kind, firePlayable)
  if (!prog) {
    const written = await runCandidates(key, urls, partUri, o, null, kindLabel)
    return completeDownload(key, finalUri, partUri, written, null, o, kindLabel)
  }

  const donePromise = (async () => {
    const written = await runCandidates(key, urls, partUri, o, prog, kindLabel)
    return completeDownload(key, finalUri, partUri, written, prog, o, kindLabel)
  })()
  const early = await Promise.race([
    playableSignal,
    donePromise.then(
      (v) => ({ __done: v }),
      (e) => {
        throw e
      }
    ),
  ])
  if (early && early.__done) return early.__done
  return { uri: early.uri, cached: false, bytes: early.got, progressive: true, done: donePromise }
}

/**
 * 逐条候选地址落到 .part。失败删残片换下一条；**已开播（prog.fired）之后两条铁律**：
 * 残片不删（音频正握着它），也不再换候选（换地址就要动在播的文件）。
 *
 * @returns {Promise<number>} 落盘字节数
 */
async function runCandidates(key, urls, partUri, o, prog, kindLabel) {
  let lastErr = null
  for (let i = 0; i < urls.length; i++) {
    const entry = inflight.get(key)
    if (i > 0 && entry) {
      // 换下一条候选时清掉上一条留下的取消标记（那只是「这条地址不行」的后果）。
      // **第一条不能清**：清了就丢掉「下载开始前就被取消」这件事（预取刚发起就被
      // 切歌掐断，正是这个场景），下载会照跑到底、残片也留下来了。
      entry.cancelled = false
      entry.cancel = null
    }
    if (entry && entry.cancelled) {
      throw makeBridgeError(BRIDGE_ERRORS.CANCELLED, '传输已被取消（下载开始前）：' + key)
    }
    if (i > 0) {
      console.warn('[AudioCache]', kindLabel, '换用候选地址', i + 1, '/', urls.length)
    }
    try {
      return await downloadOneCandidate(key, urls[i], partUri, o, prog)
    } catch (e) {
      lastErr = e
      // 已开播的落点绝不删：那是音频正在读的文件，删了等于掐断在播的歌
      if (!(prog && prog.fired)) await deleteFile(partUri) // 残片必删：下一次 access() 绝不能命中半个文件
      const cancelled = !!(
        (inflight.get(key) && inflight.get(key).cancelled) ||
        (e && e.code === BRIDGE_ERRORS.CANCELLED)
      )
      if (cancelled) throw e // 主动取消：换地址没有意义
      if (prog && prog.fired) throw e // 已开播：保住这份在播的，不换候选
      console.warn(
        '[AudioCache]',
        kindLabel,
        '候选地址',
        i + 1,
        '/',
        urls.length,
        '失败：',
        e && e.message ? e.message : e
      )
    }
  }
  throw lastErr || new Error('下载失败')
}

/**
 * 落盘完成后的收尾。已开播（边下边播）时**只登记不搬动** —— 落点还是音频在读的文件，
 * 转正延到 finalizeFor（下一次查询该曲目时）；否则照旧：改名转正 + 按保留名单清理。
 */
async function completeDownload(key, finalUri, partUri, written, prog, o, kindLabel) {
  if (prog && prog.fired) {
    const srcUri = prog.playableUri || partUri
    pendingFinalize.set(key, { srcUri, finalUri, bytes: written })
    console.log('[AudioCache]', kindLabel, '落盘完成（边下边播，转正延后）:', key, written, 'bytes')
    return { uri: srcUri, cached: false, bytes: written, progressive: true }
  }
  if (await access(finalUri)) await deleteFile(finalUri) // 旧的坏/过期文件让位
  await moveFile(partUri, finalUri)
  console.log('[AudioCache]', kindLabel, '完成:', key, written, 'bytes')
  await pruneCache(o.keepKeys || [key])
  return { uri: finalUri, cached: false, bytes: written }
}

/**
 * 单条候选地址 → .part。按机型分两条下载通道：
 *
 *   网桥机型：v4 开放长度流（帧 CRC + ACK + 重传），取消由帧层完成；
 *   原生机型：Range 分块 + 续传（见 downloadNativeToFile），取消走 cancelled 标记。
 *             分块这条路**取不到字节**时（不是网络问题）自动换 `@system.request.download`
 *             整份原生下载，并锁存 —— 见 nativeChannel 与 downloadViaRequest。
 *
 * @returns {Promise<number>} 落盘字节数
 */
async function downloadOneCandidate(key, url, partUri, o, prog) {
  if (useBridgeDownload()) {
    const dl = streamToFile(url, cdnHeaders(), partUri, o.onProgress, inflight.get(key))
    const entry = inflight.get(key)
    if (entry) entry.cancel = dl.cancel
    if (entry && entry.cancelled) {
      // 取消发生在传输注册前：requestStream 内部的 promise 稍后才 reject，
      // 此刻先抛自己的 CANCELLED，同时给内部 rejection 挂上认领者，
      // 否则它会以 unhandled rejection 的形式把整个 VM 炸掉
      dl.cancel('取消于传输开始前')
      dl.promise.catch(() => {})
      throw makeBridgeError(BRIDGE_ERRORS.CANCELLED, '传输已被取消：' + key)
    }
    const meta = await dl.promise
    return meta.totalBytes
  }

  const isCancelled = () => {
    const entry = inflight.get(key)
    return !!(entry && entry.cancelled)
  }
  // 首次原生下载时把「这台机已探明的设备能力」读回来（每个 VM 只读一次）：
  // fetch 已判死就直接走整份下载，header 形态已探明就不再从头试四档
  await loadDlCaps()
  if (nativeChannel === 'request') {
    return downloadViaRequest(url, partUri, o.onProgress, isCancelled, prog)
  }
  try {
    const res = await downloadNativeToFile(url, partUri, o.onProgress, isCancelled, prog)
    return res.bytes
  } catch (e) {
    if (!isByteUnreachable(e)) throw e
    // 本机没有 request 通道时**原样抛出原始错误** —— 别用「没有通道」把这行诊断信息盖掉，
    // 屏幕上那一行字就是全部线索。
    if (!requestModule()) throw e
    // 设备事实落盘（先记下来再试）：这台机 fetch 取不到字节 —— 空响应体 / 临时文件读不回
    // 都是**确定性拒绝**（202 一族，不是网络），写进 storage，以后每个 VM、每次启动
    // 都不再把整条分块阶梯撞一遍。
    saveDlCaps('request')
    // fetch 分块在这台机型上拿不到字节（换地址也没用 —— 同一个运行时问题）。
    // 改走原生下载管理器，并且**锁存**：下一首不用再撞一次墙。
    console.warn('[AudioCache] fetch 分块取不到字节，改走 @system.request：', e && e.message ? e.message : e)
    try {
      const bytes = await downloadViaRequest(url, partUri, o.onProgress, isCancelled, prog)
      nativeChannel = 'request'
      saveDlCaps()
      return bytes
    } catch (e2) {
      // 两条通道都失败：**两条信息都带上**。只留后一条会把「分块为什么不行」丢掉，
      // 而那正是下一轮要判断的东西。整份那条给更宽的额度：它常带着设备自己的原话
      // （`args type error, feature …`），那段原话是对文档/对日志的唯一凭据。
      throw new Error('分块：' + shortErr(e, 60) + ' / 整份：' + shortErr(e2, 140))
    }
  }
}

/**
 * 「这不是网络问题，是这条路取不到字节」—— 只有这类失败才值得换数据通道。
 *
 * 两条判据都来自实测：①2xx 但没有响应体（运行时把大响应体丢了）；
 * ②字节落在 tmp 分区却怎么都读不回来。网络超时/403 换通道毫无意义
 * （另一条通道一样到不了 CDN），那是该换地址或重新取流的事。
 */
function isByteUnreachable(e) {
  return !!(e && (e.isEmptyBody || e.tmpUnreadable))
}

/** 候选地址规范化：字符串 / 字符串数组都收（resolveUrl 两种返回都合法） */
function normalizeCandidates(value) {
  const list = Array.isArray(value) ? value : [value]
  const out = []
  for (let i = 0; i < list.length; i++) {
    const u = list[i]
    if (typeof u === 'string' && u && out.indexOf(u) < 0) out.push(u)
  }
  return out
}

/**
 * 下载走哪条通道：有 @system.fetch 的机型用 Range 分块（可续传、单块超时只重试一块），
 * 没有的走网桥 v4 流。resolveProvider() 与请求层同一判据，不会出现两套判断打架。
 */
function useBridgeDownload() {
  return resolveProvider() === 'bridge'
}

/* ------------------------------ 对外 API ------------------------------ */

/**
 * 确保 track 的音频已在本地，返回可播的本地 uri。
 *
 *   缓存命中 → 直接返回（不解析取流、不联网）；
 *   在途下载 → 复用同一条 promise（预取转正）；
 *   否则     → 解析取流 → 落盘 → 改名 → 顺带清理。
 *
 * **边下边播**（原生机型、正式播放、未关掉时）：不等整份 —— 落够
 * PROGRESSIVE_MIN 就提前 resolve，返回值带 `progressive: true` 与 `done`：
 *
 *   uri    落点（可能是还在长的文件，拿去 audio.src 直接开播）；
 *   done   剩余下载的收尾 promise：resolve = 整份落盘且长度对账通过（此时文件
 *          已登记待转正，finalizeFor 会在下一次查询该曲目时改名）；
 *          reject = 剩余下载失败（已落盘部分照常播，不足时提前结束走 onended）。
 *
 * @param {object} track 队列曲目（需要 bvid 或 avid，见 buildCacheKey）
 * @param {object} opts
 * @param {(track:object)=>Promise<string>} opts.resolveUrl 取流地址解析器（playerService.resolveUrl）
 * @param {string[]} [opts.keepKeys] 落盘后要保留的缓存键名单（当前+前后曲目）
 * @param {(received:number, total:number|null)=>void} [opts.onProgress]
 * @returns {Promise<{uri:string, cached:boolean, bytes?:number, progressive?:boolean,
 *                     done?:Promise<object>}>}
 */
export async function ensureTrackFile(track, opts) {
  if (!track) throw new Error('曲目为空')
  const key = buildCacheKey(track)
  if (!key) throw new Error('曲目缺少 bvid/avid，无法落盘缓存（网桥机型播放要求本地文件）')

  // 上一次边下边播留下的完整文件先转正（可能正是这一首）—— 转正后才轮到缓存判断
  await finalizeFor(key)

  const existing = inflight.get(key)
  if (existing && existing.promise) return existing.promise

  const finalUri = uriOf(fileNameOf(key))
  if (await access(finalUri)) {
    console.log('[AudioCache] 缓存命中:', key)
    const o = opts || {}
    await pruneCache(o.keepKeys && o.keepKeys.length ? o.keepKeys : [key])
    return { uri: finalUri, cached: true }
  }

  const entry = registerInflight(key, 'play', track)
  entry.promise = (async () => {
    try {
      const res = await downloadToCache(key, track, opts, '落盘', 'play')
      if (res && res.progressive && res.done) {
        // 在途表要活到「剩余字节下完」为止：预取复用、prune 跳过、取消机制都靠它
        entry.done = res.done
        const drop = () => {
          if (inflight.get(key) === entry) inflight.delete(key)
        }
        res.done.then(drop, drop)
      }
      return res
    } finally {
      if (!entry.done) inflight.delete(key)
    }
  })()
  return entry.promise
}

/**
 * 只查缓存、不下载：命中返回本地 uri，未命中返回 ''。
 *
 * playerService 的「三级取音」用它判断能不能走最快的路（本地文件零网络）。
 * 与 ensureTrackFile 的区别：这里**绝不**触发下载，也不动 keep 名单。
 *
 * @param {object} track
 * @returns {Promise<string>}
 */
export async function getCachedFile(track) {
  const key = track ? buildCacheKey(track) : ''
  if (!key) return ''
  // 边下边播留下的完整文件先转正，再判缓存 —— 不做这一步，播过的歌会被当成没缓存
  await finalizeFor(key)
  const finalUri = uriOf(fileNameOf(key))
  return (await access(finalUri)) ? finalUri : ''
}

/**
 * 后台预取一首（playerService 起播后调用，播到哪预到哪）。
 * 返回 {promise, cancel}；重复预取同一首/已在播的曲目会复用或直接跳过。
 */
export function prefetchTrack(track, opts) {
  const o = opts || {}
  const key = buildCacheKey(track)
  if (!key) return { promise: Promise.resolve({ skipped: 'no-key' }), cancel: () => {} }

  const existing = inflight.get(key)
  if (existing && existing.promise) return { promise: existing.promise, cancel: () => {} }

  const entry = registerInflight(key, 'prefetch', track)
  entry.promise = (async () => {
    try {
      // 边下边播留下的完整文件先转正（转正后可能直接命中缓存，连下载都省了）
      await finalizeFor(key)
      const finalUri = uriOf(fileNameOf(key))
      if (await access(finalUri)) {
        return { uri: finalUri, cached: true, skipped: 'cached' }
      }
      return await downloadToCache(key, track, opts, '预取', 'prefetch')
    } finally {
      inflight.delete(key)
    }
  })()
  entry.promise.catch(() => {}) // 预取失败只在日志里说，不让 unhandledrejection 炸全局
  return { promise: entry.promise, cancel: (reason) => cancelEntry(entry, reason || '预取已取消') }
}

/**
 * 取消预取。keepTrack 传当前曲目：目标是它的预取（切歌刚好要用）保留，
 * 其余全部掐断 —— 给正式播放的下载让出蓝牙带宽。
 */
export function cancelPrefetch(keepTrack) {
  inflight.forEach((entry, key) => {
    if (entry.kind !== 'prefetch') return
    if (keepTrack && sameTrack(entry.track, keepTrack)) return
    console.log('[AudioCache] 取消预取:', key)
    cancelEntry(entry, '切歌，预取让路')
  })
}

/** 取消所有在途下载（清空缓存前调用，避免清完又被在途写回半个文件） */
export function cancelAll() {
  inflight.forEach((entry, key) => {
    console.log('[AudioCache] 取消在途下载:', key)
    cancelEntry(entry, '缓存被清空')
  })
}

/**
 * 按保留名单清理：名单外的完整文件删掉，所有无人认领的 .part 残片删掉。
 * 在途下载（inflight 表里的）一律跳过 —— 那是正在写的文件。
 *
 * @param {string[]} keepKeys 要保留的缓存键（当前 + 下一首 + 上一首）
 * @returns {Promise<number>} 删除的文件数
 */
export async function pruneCache(keepKeys) {
  const keep = {}
  const list = keepKeys || []
  for (let i = 0; i < list.length; i++) {
    if (list[i]) keep[list[i]] = true
  }
  const files = await listDir()
  let removed = 0
  for (let i = 0; i < files.length; i++) {
    const name = baseName(files[i] && files[i].uri)
    const key = keyFromName(name)
    if (!key) continue // 不是本服务的文件，不碰
    if (inflight.has(key)) continue // 在途下载的 .part（或刚下完待消费的）不动
    if (pendingFinalize.has(key)) continue // 边下边播下完待转正的（可能在播/待收尾），别动
    if (!isPartName(name) && keep[key]) continue
    await deleteFile(files[i].uri)
    removed++
  }
  if (removed) console.log('[AudioCache] 已清理缓存文件', removed, '个')
  return removed
}

/**
 * 启动清理：只删上次运行留下的 `.part` 残片（崩溃/断电来不及改名的那种），
 * 完整缓存文件保留 —— 再次播放同一首仍然秒开。
 *
 * 除了自己的目录，还会去 `internal://cache/` **根**上扫一遍：`@system.request.download`
 * 是先落在应用缓存目录再由我们 move 进来的（默认名字给不了子目录），进程被杀就会在根上
 * 留下一个 `bm_a_*.part`。两个条件同时命中才删 —— **本服务前缀** + `.part` 家族，
 * 别人的文件一律不碰。
 *
 * @returns {Promise<number>} 删除的残片数
 */
export async function cleanupOrphans() {
  // 目录还没建过时，list 在原生侧会留一行 `file doesn't exist ... errno = -2` 的 ERROR。
  // 先把目录建好，日志干净，后面的落盘也少一步。
  // 建不出来不算错：listDir 本来就按空目录处理，清理照做。
  try {
    await ensureDir()
  } catch (e) {
    // 忽略：只影响日志噪音
  }
  const inDir = await sweepParts(DIR_URI)
  const inRoot = await sweepParts(CACHE_ROOT_URI)
  return inDir + inRoot
}

/** 扫一个目录里属于本服务的 `.part` 家族残片（在途下载的除外） */
async function sweepParts(dirUri) {
  const files = await listDir(dirUri)
  let removed = 0
  for (let i = 0; i < files.length; i++) {
    const name = baseName(files[i] && files[i].uri)
    if (!isPartName(name)) continue
    const key = keyFromName(name)
    if (!key) continue // 不是本服务命名的文件，不碰
    if (inflight.has(key)) continue
    await deleteFile(files[i].uri)
    removed++
  }
  return removed
}

/**
 * 清空音频缓存（更多页「清理音频缓存」入口）。
 * 先取消所有在途下载，再把目录里属于本服务的文件全删掉。
 *
 * @returns {Promise<number>} 删除的文件数
 */
export async function clearAudioCache() {
  cancelAll()
  const files = await listDir()
  let removed = 0
  for (let i = 0; i < files.length; i++) {
    const name = baseName(files[i] && files[i].uri)
    if (!keyFromName(name) && !isPartName(name)) continue // 外来文件不碰
    await deleteFile(files[i].uri)
    removed++
  }
  console.log('[AudioCache] 缓存已清空，删除', removed, '个文件')
  return removed
}

/**
 * 缓存概况（更多页展示用）：{count, bytes}
 */
export async function describeCache() {
  const files = await listDir()
  let bytes = 0
  let count = 0
  for (let i = 0; i < files.length; i++) {
    const name = baseName(files[i] && files[i].uri)
    // 只统计完成态：.part 是下载中的半成品，不算「已缓存」
    if (!keyFromName(name) || isPartName(name)) continue
    count++
    bytes += Number(files[i] && files[i].length) || 0
  }
  return { count, bytes }
}

/** 字节数 → 人话（1.8 MB） */
export function formatBytes(bytes) {
  const n = Number(bytes) || 0
  if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + ' MB'
  if (n >= 1024) return Math.round(n / 1024) + ' KB'
  return n + ' B'
}

/**
 * 「重取这首」：本地播放出错时的兜底 —— 删掉缓存与残片后按 ensure 全流程重来。
 * 只重试一次的纪律由 playerService._retriedLocal 把守，这里只管删干净。
 */
export async function refreshTrackFile(track, opts) {
  const key = buildCacheKey(track)
  if (key && !inflight.has(key)) {
    // 在途下载的文件不能删：下载器还在按自己的 written 往里追加，
    // 删了它会把后续字节追加进一个空文件 —— 拼出一份长度对不上的坏缓存。
    // （边下边播更不能删：那可能正是音频在读的文件。）
    await deleteFile(uriOf(fileNameOf(key)))
    await deleteFile(uriOf(partNameOf(key)))
    // 整份原生下载的落点在缓存目录根上（见 downloadViaRequest）：一并清掉
    await deleteFile(CACHE_ROOT_URI + partNameOf(key))
  }
  return ensureTrackFile(track, opts)
}


