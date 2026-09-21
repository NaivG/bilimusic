/**
 * 纯解析工具（不 import 任何模块，也不 import @system.*）
 * 抽出来的目的：这些是最容易出错、也最需要先用 Node 验证的逻辑；
 * 离线自检（vela/scripts/verify.mjs）用静态 import 直接加载本文件。
 *
 * **保持零 import 是刻意的**：verify.mjs 用静态 import 直接加载本文件，
 * 而把无扩展名的相对导入补齐成 .js 的解析钩子要等脚本体执行时才注册 ——
 * 这里一旦 import 别的源码文件，自检脚本会在装载阶段就挂掉（ERR_MODULE_NOT_FOUND）。
 */

/**
 * 把 @system.fetch 的返回归一化为 { httpCode, body, headers }
 *
 * **状态码字段名是 `code`，不是 `status`**（官方文档「success 返回值」表：
 * code=服务器状态 code / data / headers）。本文件把三种形态都认下来：
 *   A. { code, data, headers }              —— 本地 d.ts 的 Promise 形态 / 官方回调形态
 *   B. { data: { code, data, headers } }    —— 官方文档的 Promise 示例形态
 *   C. { code, data }                       —— 本地 d.ts 的回调形态（无 headers）
 * 另外顺手认 `status` 别名（个别 runtime / 我们自己写的网桥插件用过这个命名），
 * 但那是**兜底**，不是主路径：真机上给的就是 `code`。
 */
export function normalizeFetchResult(raw) {
  if (raw === undefined || raw === null) {
    return { httpCode: 0, body: null, headers: {} }
  }

  if (looksLikeEnvelope(raw)) {
    return {
      httpCode: httpCodeOf(raw),
      body: raw.data,
      headers: raw.headers || {},
    }
  }

  if (raw.data && looksLikeEnvelope(raw.data)) {
    return {
      httpCode: httpCodeOf(raw.data),
      body: raw.data.data,
      headers: raw.data.headers || {},
    }
  }

  return {
    httpCode: 0,
    body: raw && typeof raw === 'object' && 'data' in raw ? raw.data : raw,
    headers: (raw && raw.headers) || {},
  }
}

/** 状态码：`code` 优先，`status` 只是别名兜底；都没有则 0（调用方应据此报错） */
function httpCodeOf(o) {
  if (typeof o.code === 'number') return o.code
  if (typeof o.status === 'number') return o.status
  return 0
}

function looksLikeEnvelope(o) {
  if (!o || typeof o !== 'object') return false
  if ('headers' in o) return true
  if (!('data' in o)) return false
  // `status` 只在它确实是 HTTP 状态码（数字）时才算信封 ——
  // 否则业务体里一个叫 status 的字符串字段就能把普通返回值错认成信封
  return 'code' in o || typeof o.status === 'number'
}

/**
 * 排查用：把 fetch 回来的原始对象「长什么样」写成人话。
 *
 * 归一化拿不到状态码时，真正需要知道的不是「失败了」，而是**这台设备给的是什么字段**
 * —— 一句话的字段清单就能立刻定位。
 */
export function describeFetchShape(raw) {
  if (raw === undefined) return 'undefined'
  if (raw === null) return 'null'
  if (typeof raw !== 'object') return typeof raw
  const keys = Object.keys(raw)
  if (!keys.length) return '空对象'
  return keys
    .map((k) => k + '=' + typeof raw[k])
    .join(', ')
}

/* --------------------------- 响应体（拿到字节才算数） --------------------------- */

/**
 * 排查用：响应体「长什么样」。与上面 describeFetchShape 同源思路 ——
 * 字节拿不到时，需要的不是「失败了」，而是**这台设备给的到底是什么**：
 * undefined / 空字符串 / 0 字节的 ArrayBuffer / 一个没有 byteLength 的怪对象。
 * （实测有的机型 `responseType:'arraybuffer'` 的 Range 请求会回
 * **206 + 合法 Content-Range**，请求头也没问题，`data` 却是空的。）
 */
export function describeBodyShape(body) {
  if (body === undefined) return 'undefined'
  if (body === null) return 'null'
  if (typeof body === 'string') return 'string(' + body.length + ')'
  if (typeof body === 'number' || typeof body === 'boolean') return typeof body + '(' + body + ')'
  if (typeof body !== 'object') return typeof body
  const tag = Object.prototype.toString.call(body)
  if (tag === '[object ArrayBuffer]') return 'ArrayBuffer(' + (body.byteLength || 0) + ')'
  if (ArrayBuffer.isView(body)) {
    const name = (body.constructor && body.constructor.name) || 'TypedArray'
    return name + '(' + (body.byteLength || 0) + ')'
  }
  const keys = Object.keys(body)
  const bl = typeof body.byteLength === 'number' ? 'byteLength=' + body.byteLength + ',' : ''
  return 'object{' + bl + 'keys=' + (keys.length ? keys.join('|') : '空') + '}'
}

/**
 * 响应体 → Uint8Array；**拿不到就返回 null**（绝不返回空数组冒充成功）。
 *
 * 要认识这么多形态，是因为「字节」在这条链路上被三个不同的层依次搬运过：
 *   - `responseType:'arraybuffer'`  → 官方就是 ArrayBuffer，但真机上可能是
 *     二进制字符串（部分 runtime 只给 string）、或跨 realm 的 ArrayBuffer
 *     （`instanceof` 会失手，得用 toString 标签认）；
 *   - `responseType:'file'`         → 是临时文件 uri，不是字节（调用方先判 uri）；
 *   - `file.readArrayBuffer` 的返回 → `{buffer: Uint8Array}`，也是「包装」形态之一。
 *
 * 最后那道 `view.length === body.byteLength` 是防呆：一个只有 byteLength 属性、
 * 并不是真 ArrayBuffer 的对象，`new Uint8Array(obj)` 会按 array-like 处理并得到
 * **0 长度**（静默的假成功）；长度对不上就说明它不是缓冲区，宁可当「拿不到」。
 */
export function bytesOfBody(body) {
  if (body === undefined || body === null) return null
  if (typeof body === 'string') return body.length ? binaryStringToBytes(body) : null
  if (Array.isArray(body)) return body.length ? Uint8Array.from(body) : null
  if (typeof body !== 'object') return null
  if (Object.prototype.toString.call(body) === '[object ArrayBuffer]') {
    return body.byteLength > 0 ? new Uint8Array(body) : null
  }
  if (ArrayBuffer.isView(body)) {
    return body.byteLength > 0
      ? new Uint8Array(body.buffer, body.byteOffset || 0, body.byteLength)
      : null
  }
  // {buffer: …} 包装（file.readArrayBuffer 的返回形态）；递归一次即可
  if (body.buffer) {
    const inner = bytesOfBody(body.buffer)
    if (inner) return inner
  }
  if (typeof body.byteLength === 'number') {
    try {
      const view = new Uint8Array(body)
      if (view.length > 0 && view.length === body.byteLength) return view
    } catch (e) {
      return null
    }
  }
  return null
}

/**
 * 二进制字符串 → Uint8Array（每字符一个字节，按 latin1 取低 8 位）。
 *
 * 与 common/fetchbridge.binaryToUint8 是同一件事，这里刻意各留一份：fetchbridge 是给
 * 网桥协议用的，而本文件要保持零 import（见文件头注释），合并会让自检脚本装载不了。
 * 只在这一个地方用、语义也只有一行，重复的代价小于那个约束。
 */
function binaryStringToBytes(binary) {
  const s = String(binary === undefined || binary === null ? '' : binary)
  const out = new Uint8Array(s.length)
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff
  return out
}

/* --------------------------- CDN 地址（防盗链按节点类生效） --------------------------- */

/**
 * 主机名（去掉协议与路径）；取不到返回 ''
 */
export function hostOfUrl(url) {
  const m = String(url || '').match(/^https?:\/\/([^/]+)/)
  return m ? m[1] : ''
}

/**
 * CDN 节点类别：'mcdn' | 'upos' | 'edge' | 'other'
 *
 * **这个分类是有业务含义的，不是给日志看的**：B 站防盗链按节点类生效，而
 * `@system.audio` 的 `audio.src` **发不了 Referer**（原生播放器不给我们设请求头的机会），
 * 于是「哪些地址能用直链播」是**可以预测**的：
 *
 *   mcdn（P2P/分享节点）  不校验 Referer → 直链能播（带不带 Referer 都 206）
 *   upos / edge          校验 Referer   → 直链必 403，只能「带 Referer 落盘再播」
 *
 * 实测（PC 端同一地址 × 6 种请求头组合）：
 *   upos：Referer+Origin+UA / Referer+Origin / Referer+UA 全 206；仅 UA / 什么都不带 / 裸 Range 全 403
 *   mcdn：六种组合全 206（UA 无关、Referer 无关）
 */
export function cdnNodeClass(url) {
  const host = hostOfUrl(url).toLowerCase()
  if (!host) return 'other'
  if (host.indexOf('mcdn') >= 0) return 'mcdn'
  if (host.indexOf('upos') >= 0) return 'upos'
  if (host.indexOf('edge') >= 0) return 'edge'
  return 'other'
}

/** 这条地址有没有可能被 `audio.src` 直接播出来（只有 mcdn 类不校验 Referer） */
export function isDirectLinkCapable(url) {
  return cdnNodeClass(url) === 'mcdn'
}

/**
 * 直链播放的候选顺序：能直链播的（mcdn 类）排前面，其余保持原序垫底。
 * 稳定排序 —— 同一类里仍然按调用方给的好坏顺序（带宽高的档在前）。
 */
export function sortForDirectLink(urls) {
  const list = Array.isArray(urls) ? urls : []
  const can = []
  const rest = []
  for (let i = 0; i < list.length; i++) {
    ;(isDirectLinkCapable(list[i]) ? can : rest).push(list[i])
  }
  return can.concat(rest)
}

/**
 * 直链要试几条才转落盘。
 *
 * 直链失败一次就是一次可见的起播失败（`onerror` → 界面闪一下错误态），所以不能把
 * 候选地址全试一遍再落盘：候选可能是 9 条（3 个音质档 × 3 个节点）。
 *
 *   有 mcdn 候选 → 给 `tries` 条（默认 3）：这类地址本来就能直链播，值得多试；
 *   一条 mcdn 都没有 → 只给 1 条：按实测（upos/edge 都要 Referer）它们**不可能**
 *     直链成功，试第 2 条只是让用户多等一次，落盘才是正路。
 */
export function directLinkBudget(urls, tries) {
  const list = Array.isArray(urls) ? urls : []
  if (!list.length) return 0
  const limit = typeof tries === 'number' && tries > 0 ? tries : 3
  const hasMcdn = list.some((u) => isDirectLinkCapable(u))
  return hasMcdn ? Math.min(limit, list.length) : 1
}

/** 地址里的 `deadline`（unix 秒）；解析不出返回 0。B 站 CDN 地址带它，实测有效期 120 分钟 */
export function urlDeadline(url) {
  const m = String(url || '').match(/[?&]deadline=(\d{6,})/)
  if (!m) return 0
  const n = Number(m[1])
  return isFinite(n) && n > 0 ? Math.floor(n) : 0
}

/**
 * 地址是否还在有效期内。`marginSec` 是给「刚取回来就要下几十秒」留的余量：
 * 蓝牙链路上下一首歌要几十秒，卡在过期前一分钟才开始取就必然半路 403。
 * 没有 deadline 参数的地址（合流 durl 等）一律当有效 —— 不做无根据的猜测。
 */
export function isUrlFresh(url, now, marginSec) {
  const deadline = urlDeadline(url)
  if (!deadline) return true
  const t = typeof now === 'number' && now > 0 ? now : Math.floor(Date.now() / 1000)
  const margin = typeof marginSec === 'number' && marginSec >= 0 ? marginSec : 300
  return deadline - t > margin
}

/** 滤掉已过期（或即将过期）的地址；全都过期就是空数组，调用方据此重新取流 */
export function filterFreshUrls(urls, now, marginSec) {
  const list = Array.isArray(urls) ? urls : []
  return list.filter((u) => isUrlFresh(u, now, marginSec))
}

/** 去重但保持首次出现的顺序 */
function uniq(list) {
  const seen = {}
  const out = []
  for (let i = 0; i < list.length; i++) {
    const u = list[i]
    if (!u || seen[u]) continue
    seen[u] = true
    out.push(u)
  }
  return out
}

/**
 * `dash.audio[]` → 一个候选地址列表（音质档从高到低，档内 baseUrl → backupUrl，去重）。
 *
 * **为什么要跨档拍平**：防盗链按节点类生效，而同一条流的 `backupUrl[]` 常常整档都是
 * upos —— 「最高档全是 upos」的稿件，那条唯一的 mcdn 地址可能躺在**别的档**里；
 * 只取带宽最高一档的话，这类稿件的直链必 403（upos 要 Referer），候选换到底也还是 upos。
 */
export function flattenAudioTiers(audioTiers) {
  const tiers = (Array.isArray(audioTiers) ? audioTiers : [])
    .slice()
    .sort((a, b) => (b && b.bandwidth ? b.bandwidth : 0) - (a && a.bandwidth ? a.bandwidth : 0))
  let list = []
  for (let i = 0; i < tiers.length; i++) {
    const t = tiers[i] || {}
    const primary = t.baseUrl || t.base_url || ''
    const backups = t.backupUrl || t.backup_url || []
    list = list.concat([primary].concat(backups).filter(Boolean))
  }
  return uniq(list)
}

/**
 * 底层传输错误码 → 人话（可单测），翻不出来返回 ''。
 *
 * Vela 的 @system.fetch 没有失败码表（官方文档与本地 d.ts 都没有），实测
 * fail(data, code) 透传的是底层网络栈（libcurl）的错误码：code=28 即
 * CURLE_OPERATION_TIMEDOUT（操作超时）。1000+ 是快应用的业务码、负数是 B 站的
 * 业务码（-403 等），都不在这里翻。
 */
const NET_CODE_HINTS = {
  6: '域名解析失败',
  7: '无法连接服务器',
  28: '网络超时',
  35: 'SSL 握手失败',
  47: '重定向过多',
  56: '接收数据失败（传输中断）',
  60: '证书校验失败',
}

export function describeNetCode(code) {
  return (typeof code === 'number' && NET_CODE_HINTS[code]) || ''
}

/**
 * 解析「请求头 Cookie」（分号分隔的 name=value 串）
 *
 * 注意：这不是响应头 Set-Cookie 的解析（后者含 Path/Domain/Expires 等属性）。
 * 扫码登录的 Cookie 不走响应头 —— TV 端直接从响应体 cookie_info 取（见下），
 * 所以这里只服务「读回自己存的 Cookie」这一种场景（如退出登录取 bili_jct）。
 */
export function parseCookieHeader(raw) {
  const out = {}
  if (!raw || typeof raw !== 'string') return out
  raw.split(';').forEach((part) => {
    const eq = part.indexOf('=')
    if (eq <= 0) return
    const k = part.slice(0, eq).trim()
    const v = part.slice(eq + 1).trim()
    if (k) out[k] = v
  })
  return out
}

/**
 * 拼 query 字符串（encodeURIComponent 语义，空格编码为 %20）
 */
export function buildQuery(params) {
  return Object.keys(params || {})
    .filter((k) => params[k] !== undefined && params[k] !== null)
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`)
    .join('&')
}

/** 登录必需的关键 Cookie 项 */
export const KEY_COOKIES = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']

/**
 * 解析 TV 端登录返回的 cookie_info.cookies[]
 *
 * 这是扫码登录唯一的 Cookie 来源，也是最可靠的一条路：Cookie 直接躺在响应体里，
 * 不依赖响应头透出、也不依赖跨域地址，因此不受运行时合并 Set-Cookie 的影响。
 *
 * @param {object} cookieInfo 形如 { cookies: [{name, value, ...}], domains: [...] }
 */
export function parseTvCookieInfo(cookieInfo) {
  const out = {}
  if (!cookieInfo || !Array.isArray(cookieInfo.cookies)) return out
  cookieInfo.cookies.forEach((c) => {
    if (c && c.name) out[c.name] = c.value
  })
  return out
}

/**
 * 官方推荐流单条 → 播放曲目（/x/web-interface/index/top/feed/rcmd 的 data.item[]）
 *
 * 该接口是官方推荐流，会混入非稿件内容（`goto: 'ad'` 推广空壳、直播/资源位等），
 * 只有 `goto: 'av'` 的条目才带 bvid/cid，能走 UGC 取流链路 —— 其余一律丢弃，
 * 不靠调用方逐个判断。
 *
 * @returns {object|null} 与 biliApi.toTrack 同构的曲目；不可播放的条目返回 null
 */
export function parseRecommendItem(item) {
  if (!item || typeof item !== 'object') return null
  if (item.goto !== 'av') return null
  if (!item.bvid) return null
  const owner = item.owner || {}
  return {
    id: item.id,
    bvid: item.bvid,
    cid: item.cid || 0, // 推荐流直接带 cid，取流时无需再查稿件信息
    title: item.title || '未知',
    artist: owner.name || '未知',
    cover: item.pic || '',
    duration: item.duration || 0,
  }
}

/**
 * 综合热门单条 → 播放曲目（/x/web-interface/popular 的 data.list[]）
 *
 * 官方推荐流（rcmd）整页失败时的兜底来源。带 `redirect_url` 的是番剧/影视等
 * PGC 内容（UGC playurl 接口取不了流）→ 丢弃；缺 bvid 的同样丢弃。
 *
 * @returns {object|null} 与 biliApi.toTrack 同构的曲目；不可播放的条目返回 null
 */
export function parsePopularItem(item) {
  if (!item || typeof item !== 'object') return null
  if (item.redirect_url) return null
  if (!item.bvid) return null
  const owner = item.owner || {}
  return {
    id: item.aid,
    bvid: item.bvid,
    cid: item.cid || 0,
    title: item.title || '未知',
    artist: owner.name || '未知',
    cover: item.pic || '',
    duration: item.duration || 0,
  }
}

/**
 * 组织 Cookie 诊断信息（登录页会展示，便于真机定位）
 */
export function buildCookieDiagnostics(cookies, sources) {
  const obtained = Object.keys(cookies || {})
  return {
    obtained,
    missingKeyCookies: KEY_COOKIES.filter((k) => !cookies || !cookies[k]),
    ...(sources || {}),
  }
}
