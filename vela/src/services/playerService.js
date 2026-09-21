import audio from '@system.audio'
// 系统媒体音量
import systemVolume from '@system.volume'
import { CONFIG } from '../common/config'
import { clampVolume } from '../common/volume'
import {
  describeNetCode,
  sortForDirectLink,
  directLinkBudget,
  isDirectLinkCapable,
  cdnNodeClass,
  filterFreshUrls,
} from '../common/parse'
import { usesDirectLink } from './api'
import * as audioCache from './audioCache'
import { Storage } from './storage'
import {
  bumpShareState,
  normalizeShareState,
  describeShareState,
  isShareNewer,
  isQueueNewer,
} from '../common/playstate'
import { findTrackIndex, sameTrack } from '../common/tracks'
// Vela 每个 page 跑在独立的 JS VM 里，playerService 模块在每个 VM 里都是独立实例，
// app.ux 里 setUrlResolver 注入的是 app VM 的 urlResolver，list.ux / volume.ux 等
// page VM 里的那份仍是 null。所以直接 import biliApi 并把 resolveTrackUrl 作为
// 默认值；setUrlResolver 仍保留为覆盖入口，未来想换实现/写测试 mock 都能用。
import * as biliApi from './biliApi'

/**
 * 播放服务（**每个 JS VM 一份实例**）
 *
 * 基于 AIoT IDE 本地 API 定义（feature/system/audio.d.ts）+ 官方文档实现。
 * 与通用快应用规范的差异及本实现的处理：
 *  - ontimeupdate 事件存在（4HZ）→ 事件驱动进度，直接读 currentTime/duration 属性
 *  - percent 是 getPlayState() 的返回字段（@OnlyVela），不是模块属性 → 状态对账时优先采用
 *  - 无 seek() 方法 → 写 audio.currentTime 即为跳转
 *  - 另有 onprevious/onnext（1040+）→ 接管通知栏切歌按钮
 *  - 元数据：Vela 文档给的是 meta 对象，本地定义为 title/artist/cover → 两者都写
 *  - src 不支持自定义请求头 → 直链 403 时降级为「落盘再播」
 *  - 网桥机型（没有 @system.fetch / 独立网络）→ **B 档**：v4 流落盘成本地文件再播，
 *    边播边预取下一首；缓存文件的一生（复用/.part 残片/清理/预取取消）由
 *    services/audioCache.js 全权负责，本文件只调它的门面方法
 *  - 音量**不自维护**：读写 @system.volume（系统媒体音量），也不写 audio.volume，
 *    见本文件末尾「音量」小节
 *
 * ⚠️ 跨 VM 语义
 *
 * Vela 给每个 page 起一个独立 JS VM，模块级变量不跨页共享：
 * 来源页点歌时改的是**那一页 VM 的** player 对象，主页那份仍是 queue=[], index=-1
 * → 不做共享的话，回到主页永远显示「未在播放」。
 *
 * 结论：
 *  1. 「当前播哪首」必须落盘到 @system.storage（唯一的跨 VM 通道），见 ./common/playstate.js；
 *     每个 VM 在 onShow / 定时对账 / 控制动作前都要 adopt() 一次。
 *  2. @system.audio 是全局原生服务：任何 VM 都能 set src / play / pause，
 *     也都能通过 getPlayState()、audio.currentTime 读到真实播放进度（与谁起的播无关）。
 *  3. 原生事件回调是「按属性最后设置者生效」还是「按 VM 实例分发」不可知，
 *     所以绑定必须**互相错开**：长生命周期的 app VM 只绑控制事件
 *     （onended/onprevious/onnext），常驻的主页 VM 只绑展示事件（onplay/ontimeupdate…）；
 *     临时页面一律不绑，只做 adopt()。
 *     音量事件（@system.volume 的 onMediaValueChanged）同理只归可见的音量页，
 *     它和 audio 的事件是两套槽位，互不影响。
 */

const STATE = {
  IDLE: 'idle',
  LOADING: 'loading',
  PLAYING: 'playing',
  PAUSED: 'paused',
  ERROR: 'error',
}

// 订阅表同样是「按 VM」的：别的 page 里 emit 的事件不会派发到这里，
// 跨页变化只能靠 adopt() 主动对账，别指望 subscribe 能收到。
const listeners = []

// 默认取 biliApi.resolveTrackUrl，避开 Vela 多 page VM 各持一份 playerService
// 实例导致 urlResolver 跨 VM 不共享的问题
let urlResolver =
  biliApi && typeof biliApi.resolveTrackUrl === 'function' ? biliApi.resolveTrackUrl : null

const player = {
  queue: [],
  index: -1,
  state: STATE.IDLE,
  currentTime: 0,
  duration: 0,
  percent: 0,
  // 系统媒体音量的**只读镜像**（真相在 @system.volume 里）：
  // 只为了让 getSnapshot() 能同步读到值，任何写操作都必须落到系统音量上
  volume: 1,
  loop: false,
  error: '',
  fromCache: false,

  _timer: null,
  _retriedLocal: false,
  // 兜底（重取流 + 落盘）进行中：Vela 的 onerror 不带载荷且同轮故障会连发多次，
  // 兜底又常常要等好几秒，用这个标志吞掉中间的重复 onerror，别把抢救掐死
  _recovering: false,
  _pendingUrl: '',
  _seq: 0,
  // 本次起播的候选地址、已试到第几条、本轮直链最多试几条
  // （直链失败换下一条用，额度由节点类决定，见 handlePlayError 与 parse.directLinkBudget）
  _urls: [],
  _urlIndex: 0,
  _urlBudget: 0,

  // 跨 VM 对账水印：-1 表示本 VM 还没跟共享态对过账
  _shareVer: -1,
  _ownVer: 0,
  _queueVer: -1,
  _adopted: false,

  // 绑定展示事件的那个常驻主页 VM 当前可不可见（页面 onShow/onHide 维护）。
  // 默认 true：首帧就是可见的，且 onShow 可能早于 onInit 触发。
  _visible: true,
}

/* ------------------------------ 事件订阅 ------------------------------ */

export function subscribe(fn) {
  listeners.push(fn)
  return () => {
    const i = listeners.indexOf(fn)
    if (i >= 0) listeners.splice(i, 1)
  }
}

function emit(type, extra) {
  const snap = getSnapshot()
  listeners.forEach((fn) => {
    try {
      fn(type, snap, extra || {})
    } catch (e) {
      console.error('[Player] listener error:', e)
    }
  })
}

export function getSnapshot() {
  return {
    state: player.state,
    index: player.index,
    track: player.queue[player.index] || null,
    queueLength: player.queue.length,
    currentTime: player.currentTime,
    duration: player.duration,
    percent: player.percent,
    volume: player.volume,
    loop: player.loop,
    error: player.error,
    fromCache: player.fromCache,
    isPlaying: player.state === STATE.PLAYING,
  }
}

/* ------------------------------ 初始化 ------------------------------ */

/**
 * 注册取流地址解析器（默认已是本 VM 的 biliApi.resolveTrackUrl）
 * @param {(track:object)=>Promise<string>} fn
 */
export function setUrlResolver(fn) {
  urlResolver = fn
}

let initialized = false
let binding = { display: false, control: false }

/**
 * 逐个绑事件：旧 runtime 不认某个属性时只丢这一个，不影响其余绑定
 * （没这层兜底的话，先抛错的属性会把后面的 onended / 音量恢复一起带走）
 */
function bindEvent(name, handler) {
  try {
    audio[name] = handler
  } catch (e) {
    console.warn('[Player] 绑定 ' + name + ' 失败（机型不支持？）:', e)
  }
}

/**
 * 绑定原生事件（每个 VM 只生效一次）
 *
 * @param {object} [options]
 * @param {boolean} [options.display=true] 绑展示事件（进度/播放态），只有常驻的播放页该开
 * @param {boolean} [options.control=false] 绑控制事件（播完自动下一首、通知栏切歌），只有 app VM 该开
 *
 * 两者故意不重叠：原生回调若按属性「最后设置者生效」，两个 VM 各绑一半才不会互相顶掉；
 * 若按 VM 实例分发，那两边都收得到，也仍然只各有一个人处理，不会重复切歌。
 */
export function init(options) {
  const opt = options || {}
  const wantDisplay = opt.display !== false
  const wantControl = !!opt.control

  if (initialized) {
    console.warn('[Player] init 重复调用，已忽略 | display =', binding.display, '| control =', binding.control)
    return
  }
  initialized = true
  binding = { display: wantDisplay, control: wantControl }

  if (wantDisplay) {
    bindEvent('onplay', () => {
      console.log('[Player] event play')
      setState(STATE.PLAYING)
      startReconcileTimer()
    })

    bindEvent('onpause', () => {
      console.log('[Player] event pause')
      // 来电/蓝牙等被动暂停也会走到这里，状态以系统为准
      if (player.state !== STATE.ERROR) setState(STATE.PAUSED)
      stopReconcileTimer()
      syncPlayState()
    })

    bindEvent('onstop', () => {
      console.log('[Player] event stop')
      stopReconcileTimer()
    })

    bindEvent('onloadeddata', () => {
      console.log('[Player] event loadeddata')
      syncPlayState()
    })

    bindEvent('ondurationchange', () => {
      readProgressFromProperties()
    })

    bindEvent('onerror', (err) => {
      console.warn('[Player] event error:', safeStringify(err))
      handlePlayError(err)
    })

    // 进度：官方文档未列，但本地 API 定义确认存在，4HZ 触发
    bindEvent('ontimeupdate', () => {
      readProgressFromProperties()
      if (player.state !== STATE.PLAYING && player.state !== STATE.ERROR) {
        setState(STATE.PLAYING)
        startReconcileTimer()
      }
    })
  }

  if (wantControl) {
    // 通知栏切歌（[1040+]）与播完自动下一首：全局只由 app VM 处理，避免两个 VM 同时切歌
    bindEvent('onprevious', () => {
      console.log('[Player] 通知栏：上一首')
      prev()
    })
    bindEvent('onnext', () => {
      console.log('[Player] 通知栏：下一首')
      next()
    })
    bindEvent('onended', () => {
      console.log('[Player] event ended')
      if (player.loop) {
        seekTo(0)
        audio.play()
      } else {
        next()
      }
    })
  }

  // 音量不落盘、无需「恢复」：真相是系统媒体音量，读一次把镜像填上即可
  syncVolume()

  console.log('[Player] initialized | display =', wantDisplay, '| control =', wantControl)
}

/* --------------------------- 跨 VM 共享态 --------------------------- */

async function readShareState() {
  const raw = await Storage.getJson(CONFIG.STORAGE_KEYS.PLAY_STATE, null)
  return normalizeShareState(raw)
}

/**
 * 把本 VM 改动过的字段写回共享态（读-改-写，绝不整份覆盖）。
 *
 * 同一 VM 内的写入串成一条链：读-改-写本身不是原子的，
 * 本 VM 并发发起两次写入时，后一次必须读到前一次的结果，否则会把字段改回旧值。
 *
 * @param {object} patch 只放本次真正改动的字段
 */
let publishChain = Promise.resolve()

function publishShareState(patch) {
  publishChain = publishChain.then(
    () => writeShareState(patch),
    () => writeShareState(patch)
  )
  return publishChain
}

async function writeShareState(patch) {
  try {
    const current = await readShareState()
    const next = bumpShareState(current, patch, Date.now())
    await Storage.setJson(CONFIG.STORAGE_KEYS.PLAY_STATE, next)
    // 注意：这里**不能**推进 _shareVer —— 那只表示「本地状态已合并到哪个版本」。
    // 本次只写了 patch 里那几个字段（比如主页 VM 收到 onplay 只写了 state），
    // 若把水位推到 next.ver，本 VM 接下来那次 adopt 就会以为自己已经同步过，
    // 于是 index/queue 永远补不上来（表现为「主页一直不更新歌曲详情」）。
    player._ownVer = next.ver // 本 VM 最近一次写入的版本，用于丢弃并发读到的过期快照
    console.log('[Player] 共享态写入 |', describeShareState(next))
    return next
  } catch (e) {
    console.warn('[Player] 共享态写入失败:', e)
    return null
  }
}

/**
 * 与共享态对账：把别的 VM（或上次运行）留下的播放状态同步到本 VM。
 *
 * **主页显示不更新的根因就在这里** —— 每个 page 是独立 VM，
 * 从 list 页回到主页时必须重新读一遍共享态，否则本 VM 还是那份空队列。
 *
 * 只做「读」，绝不碰 audio（否则会对账时把正在播的歌打断）。
 *
 * @param {boolean} [force] 版本号没变也强制合并一次
 * @returns {Promise<object>} 对账后的快照
 */
export async function adopt(force) {
  const share = await readShareState()
  const first = !player._adopted
  if (!force && !first && !isShareNewer(share.ver, player._shareVer)) {
    return getSnapshot()
  }
  // 读到的记录比本 VM 自己最近一次写入还旧（并发下读到了过期快照）→ 不合并，
  // 否则会把刚 playAt 的 index 倒回上一次的值。下一次对账自然会读到新记录。
  if (!force && share.ver < player._ownVer) {
    player._shareVer = share.ver
    return getSnapshot()
  }

  let queueChanged = false

  // 队列：只在 queueVer 变化时读（队列 JSON 不小，能省则省）
  if (first || isQueueNewer(share.queueVer, player._queueVer)) {
    let queue = await Storage.getJson(CONFIG.STORAGE_KEYS.PLAYLIST, null)
    if (!Array.isArray(queue)) queue = []
    player.queue = queue
    player._queueVer = share.queueVer
    queueChanged = true
  }

  const prevIndex = player.index
  const indexChanged = share.index !== player.index
  if (indexChanged) {
    player.index = share.index
    // 换曲目 → 本 VM 的进度缓存作废（真实进度由本 VM 的 getPlayState/属性直读补回来）
    player.currentTime = 0
    player.duration = 0
    player.percent = 0
    player.error = ''
    player.fromCache = false
    player._retriedLocal = false
    player._recovering = false
    player._pendingUrl = ''
    player._urlBudget = 0 // 别的 VM 起播的曲目：候选额度由那边的 playAt 定，这边不知道
    // 进度缓存在上面被清零了，立刻按原生状态补一次，别让回主页的一瞬间停在 0:00
    if (player.index >= 0) syncPlayState().catch(() => {})
  }

  const prevState = player.state
  const stateChanged = !!share.state && share.state !== player.state
  if (stateChanged) player.state = share.state // 对账结果直接落，不再回写共享态（避免来回写）

  if (share.loop !== player.loop) {
    player.loop = share.loop
    try {
      audio.loop = player.loop
    } catch (e) {
      // 低版本不支持，忽略
    }
  }

  player._shareVer = share.ver
  player._adopted = true

  if (queueChanged || indexChanged || stateChanged) {
    console.log(
      '[Player] 与共享态对账 |',
      describeShareState(share),
      '| index',
      prevIndex,
      '->',
      player.index,
      '| state',
      prevState,
      '->',
      player.state
    )
    emit(indexChanged ? 'track' : queueChanged ? 'queue' : 'state', { adopted: true })
  }

  return getSnapshot()
}

/** 控制动作前先对账：否则 app VM 可能拿着上一次运行的旧队列去切歌 */
async function ensureAdopted() {
  await adopt()
}

/* ------------------------------ 队列 ------------------------------ */

/**
 * 设置播放队列
 * @param {Array} tracks 曲目数组
 * @param {number} startIndex 起始下标
 */
export async function setQueue(tracks, startIndex = 0) {
  player.queue = Array.isArray(tracks) ? tracks.slice() : []
  player.index = -1
  player._queueVer = Date.now() // 队列版本号：时间戳足够区分先后
  audioCache.cancelPrefetch(null) // 换了来源/队列：旧队列的预取全部作废
  await Storage.setJson(CONFIG.STORAGE_KEYS.PLAYLIST, player.queue)
  await publishShareState({ queueVer: player._queueVer })
  emit('queue')
  if (player.queue.length) {
    await playAt(startIndex)
  }
}

/**
 * 追加到队列尾部（不改变当前播放）
 */
export async function appendToQueue(tracks) {
  if (!Array.isArray(tracks) || !tracks.length) return player.queue.length
  player.queue = player.queue.concat(tracks)
  player._queueVer = Date.now()
  await Storage.setJson(CONFIG.STORAGE_KEYS.PLAYLIST, player.queue)
  await publishShareState({ queueVer: player._queueVer })
  emit('queue')
  return player.queue.length
}

export function getQueue() {
  return player.queue
}

/**
 * 点播一首歌（收藏夹 / 官方推荐页的单曲点按语义）
 *
 * 这是「收藏夹与播放列表解耦」的核心：来源列表页**只负责选歌**，
 * 不用整份列表替换队列。队列独立演进：
 *
 *  1. 队列里已有这首歌（按 bvid/avid 匹配，见 common/tracks.js）→ 直接跳播，
 *     不重复插入 —— 对同一首歌连点多次 / 在队列里已有时不攒重复条目；
 *  2. 队列为空 → 以这首歌建队列（等价 setQueue([track])）；
 *  3. 其它情况 → 插到**当前曲目之后**并立即播放，队列原有内容原样保留。
 *     连续点播多首会按点按顺序排在当前曲目后面，旧队列继续跟在其后。
 *
 * 想连播整个来源（「听我的收藏夹」）用来源页的「播放全部」（setQueue）。
 *
 * 跨 VM 语义与 setQueue/appendToQueue 同源：队列改动 = 落盘 + bump queueVer，
 * 读-改-写共享态只写 queueVer，其余字段（index/state）由随后 playAt 自己发布。
 *
 * @param {object} track 与队列条目同构的曲目
 * @returns {Promise<number>} 实际开始播放的队列下标；无曲目时返回 -1
 */
export async function playTrackNow(track) {
  await ensureAdopted() // 队列可能是别的 VM 建的，先对账再动刀
  if (!track) return -1

  // 已在队列里：跳播即可，绝不重复插入
  const existing = findTrackIndex(player.queue, track)
  if (existing >= 0) {
    await playAt(existing)
    return existing
  }

  // 空队列：直接建队列
  if (!player.queue.length) {
    await setQueue([track], 0)
    return 0
  }

  // 有队列：插到当前曲目之后，立刻播这首（队列原有内容原样保留）
  const at = player.index + 1
  player.queue.splice(at, 0, track)
  player._queueVer = Date.now()
  await Storage.setJson(CONFIG.STORAGE_KEYS.PLAYLIST, player.queue)
  await publishShareState({ queueVer: player._queueVer })
  emit('queue')
  await playAt(at)
  return at
}

/**
 * 从队列移除一条（播放队列页的 × 按钮）
 *
 * 跨 VM 语义与 setQueue/appendToQueue 同源：队列改动 = 落盘 + bump queueVer，
 * 只写自己改过的字段，绝不整份覆盖共享态。
 *
 * @param {number} index 待移除的队列下标
 * @returns {Promise<boolean>} 是否真的移除了
 */
export async function removeFromQueue(index) {
  await ensureAdopted() // 队列可能是别的 VM 建的，先对账再动刀
  const i = Math.floor(Number(index))
  if (!(i >= 0) || i >= player.queue.length) return false

  const wasCurrent = i === player.index
  player.queue.splice(i, 1)
  player._queueVer = Date.now()
  await Storage.setJson(CONFIG.STORAGE_KEYS.PLAYLIST, player.queue)

  // 移除的曲目在当前曲目之前 → 当前曲目下标整体前移一位。
  // 本地与共享态必须在同一次 publish 里改掉：否则别的 VM 对账回来按旧 index
  // 取到错的歌（显示错、切歌也错）。
  const shifted = !wasCurrent && i < player.index
  if (shifted) player.index -= 1
  await publishShareState(
    shifted ? { queueVer: player._queueVer, index: player.index } : { queueVer: player._queueVer }
  )
  emit('queue')

  if (wasCurrent) {
    if (!player.queue.length) {
      // 移除的正是当前曲目且队列被清空：停播回 idle（主页回到「去「更多」选歌播放」）
      try {
        audio.stop()
      } catch (e) {
        // 未在播时 stop 可能抛错，忽略
      }
      stopReconcileTimer()
      player.currentTime = 0
      player.percent = 0
      player.duration = 0
      player._pendingUrl = ''
      player.index = -1
      await setState(STATE.IDLE, { index: -1 })
      return true
    }
    // 移除的正是当前曲目：从同一位置接下去播。
    // 删的是队尾时环绕回队首（playAt 内部取模，与 next() 的环绕语义一致）。
    await playAt(i % player.queue.length)
  }
  return true
}

/* ------------------------------ 播放控制 ------------------------------ */

export async function playAt(index) {
  if (!player.queue.length) await adopt() // 队列可能是别的 VM 建的
  if (!player.queue.length) {
    console.warn('[Player] playAt: 队列为空')
    return
  }
  const i = (index + player.queue.length) % player.queue.length
  player.index = i
  player._retriedLocal = false
  player._recovering = false
  player.fromCache = false
  player.error = ''
  player.currentTime = 0
  player.percent = 0
  player.duration = 0
  player._urls = []
  player._urlIndex = 0
  player._urlBudget = 0
  player._seq++
  const seq = player._seq
  const track = player.queue[i]

  console.log(`[Player] playAt ${i}: ${track.title || track.name}`)
  // index 与 state 一次写完，并且**等落盘**：取流结束后音频就起来了，
  // 那时别的 VM 收到 onplay 会立刻读-改-写共享态；若此刻 index 还在路上，
  // 它们读到的就是旧 index，回写时会把刚切的歌冲掉。
  await setState(STATE.LOADING, { index: i })
  emit('track', { track })

  // B 档（网桥机型）：没有独立网络，直链到不了设备 —— 唯一能出声的方式是
  // 「落盘 → 播本地文件」。缓存命中即秒开；未命中先落盘再播，起播后预取下一首。
  if (!usesDirectLink()) {
    // 与新曲目无关的预取一律掐断，把带宽让给这首；目标恰好是本曲的预取
    // 会被 ensureTrackFile 复用（await 同一条在途 promise，不重复下载）
    audioCache.cancelPrefetch(track)
    return playFromCache(i, track, seq)
  }

  // 原生机型三级取音（按代价从低到高，次序别随手改）：
  //
  //   ① 命中本地缓存 → 秒开，零网络。这是「第二次播同一首」的常态。
  //   ② 直链播放（audio.src 直接指向 CDN）。注意它**发不了 Referer**，
  //      而 B 站的 mcdn 节点不校验、upos 节点校验 —— 所以直链是「有些歌能、
  //      有些歌 403」的，命中就最快，不命中反而比落盘还慢，因此只试一次、
  //      失败立刻转 ③，不纠缠。
  //   ③ 落盘到持久缓存再播（Range 分块 + 断点续传，见 audioCache）：
  //      慢（蓝牙 60-70 KiB/s，一首要几十秒）但**只付一次**，之后走 ①。
  const cached = await audioCache.getCachedFile(track)
  if (cached) {
    console.log('[Player] 命中本地缓存，直接播放:', audioCache.buildCacheKey(track))
    player._pendingUrl = cached
    player.fromCache = true
    startUrl(cached)
    schedulePrefetch(seq)
    return
  }

  if (seq !== player._seq) return

  let url = ''
  let urls = []
  try {
    urls = sortForDirectLink(normalizeUrls(await resolveUrl(track)))
    if (!urls.length) throw new Error('取流未返回可用地址')
    player._urls = urls
    player._urlIndex = 0
    // 直链能试几条、什么时候必须转落盘，由地址的节点类决定（见 parse.js 的
    // directLinkBudget）：一条 mcdn 都没有时只试 1 条 —— upos/edge 直链必 403，
    // 多试几条只是让用户多等几次失败。
    player._urlBudget = directLinkBudget(urls, CONFIG.PLAY && CONFIG.PLAY.DIRECT_TRIES)
    url = urls[0]
    console.log(
      '[Player] 直链候选', urls.length, '条（mcdn', urls.filter(isDirectLinkCapable).length,
      '条），本轮最多试', player._urlBudget, '条'
    )
  } catch (e) {
    console.error('[Player] 取流失败:', e)
    return fail('取流失败：' + describeError(e))
  }
  if (seq !== player._seq) {
    console.log('[Player] 已切歌，丢弃过期取流结果')
    return
  }

  // 候选全是 upos/edge → 直链必 403（这两类校验 Referer，audio.src 发不了请求头；
  // 实测打表见 parse.cdnNodeClass）。那一次直链尝试纯属白等一次往返（兜底里还要
  // 搭上一次强制重取流），直接落盘：有边下边播兜着，出声并不会更慢。
  // 节点类是 'other'（不认识的主机）时不跳，维持「先直链」的次序。
  const knownRefererChecked =
    urls.length > 0 &&
    urls.every((u) => {
      const c = cdnNodeClass(u)
      return c === 'upos' || c === 'edge'
    })
  if (knownRefererChecked) {
    console.log('[Player] 候选全是 upos/edge（直链必 403）：跳过直链，直接落盘')
    player._urls = urls
    player._urlIndex = 0
    player._urlBudget = 0 // 直链额度清零：本地播放再出错也不该回去撞 403
    return playFromCache(i, track, seq)
  }

  player._pendingUrl = url
  startUrl(url)
}

/** 当前曲目 + 前后各一首的缓存键：pruneCache 的保留名单（CONFIG.AUDIO_CACHE.MAX_KEEP 份） */
function cacheKeysAround(index) {
  const len = player.queue.length
  if (!len) return []
  const keys = []
  ;[(index - 1 + len) % len, index % len, (index + 1) % len].forEach((ix) => {
    const key = audioCache.buildCacheKey(player.queue[ix])
    if (key && keys.indexOf(key) < 0) keys.push(key)
  })
  return keys
}

/** 取流地址规范化：字符串 / 字符串数组都收（candidates 由 biliApi 给出） */
function normalizeUrls(value) {
  const list = Array.isArray(value) ? value : [value]
  const out = []
  for (let i = 0; i < list.length; i++) {
    const u = list[i]
    if (typeof u === 'string' && u && out.indexOf(u) < 0) out.push(u)
  }
  return out
}

/**
 * 直链额度还没用完？
 *
 * 额度 = min(本轮额度, 候选条数)，而本轮额度由**节点类**决定（parse.directLinkBudget：
 * 有 mcdn 给 3 条，没有只给 1 条）。用完就必须转落盘 —— 判断的是「额度」而不是
 * `_urls.length`，否则候选一多就会把落盘兜底一直挡在后面。
 */
function isDirectLinkRetryLeft() {
  const budget = Math.min(Math.max(1, player._urlBudget || 1), player._urls.length)
  return player._urlIndex + 1 < budget
}

/**
 * 落盘进度日志：每 512 KB 一条。蓝牙上落一首要几十秒到几分钟，
 * 这条日志是看是否正常落盘的。
 */
function logDownloadProgress(received, total) {
  if (!total || received === total || received % (512 * 1024) < 4096) {
    console.log(
      '[Player] 落盘进度:',
      audioCache.formatBytes(received),
      total ? '/ ' + audioCache.formatBytes(total) : ''
    )
  }
}

/** playFromCache / 兜底落盘共用的进度回调（打日志）。
 * **必须带 seq 守卫**：切歌不掐在途下载（它要给缓存落整份），旧下载的进度
 * 不能刷到新曲目的日志里。
 */
function onCacheProgress(seq) {
  return (received, total) => {
    if (seq !== player._seq) return
    logDownloadProgress(received, total)
  }
}

/** 落盘后播本地文件（网桥机型唯一路径；原生机型的第三级兜底也走这里） */
async function playFromCache(index, track, seq) {
  try {
    const local = await audioCache.ensureTrackFile(track, {
      resolveUrl,
      keepKeys: cacheKeysAround(index),
      onProgress: onCacheProgress(seq),
    })
    if (seq !== player._seq) {
      // 已切歌：文件已完整落盘（校验全过），留在缓存里给下一次用
      console.log('[Player] 已切歌，落盘结果留给缓存')
      return
    }
    player._pendingUrl = local.uri
    player.fromCache = true
    startUrl(local.uri)
    if (local.progressive && local.done && typeof local.done.then === 'function') {
      // 边下边播：已经在出声，剩余字节还在路上。
      // 失败**不掐当前播放** —— 已落盘的部分照常播（不够时提前结束走 onended）；
      // 收尾（改名转正）由 audioCache 在下一次查询该曲目时做，这里不用管。
      local.done.then(null, (e) => {
        if (seq === player._seq) {
          console.warn('[Player] 边播边下的剩余下载失败（已落盘部分继续播）:', describeError(e))
        }
      })
    }
    schedulePrefetch(seq)
  } catch (e) {
    if (seq !== player._seq) {
      console.log('[Player] 落盘失败时已切歌，错误不再打扰新曲目:', describeError(e))
      return
    }
    console.error('[Player] 音频落盘失败:', e)
    fail('取流失败：' + describeError(e))
  }
}

/**
 * 边播边预取下一首。
 *
 * 两种机型都值得预：
 *  - 网桥机型：落一首要十几秒到几十秒，预取是切歌体验的全部；
 *  - 原生机型：走蓝牙的链路只有 60-70 KiB/s，首播同样要几十秒，预取让「下一首」
 *    在真正切过去之前就落好盘（切歌零等待）。带宽是连续占用，但对播放本身无害
 *    —— 当下这首已经在播本地文件了。
 *
 * 只在起播的那个 VM 里跑一遍 —— 每个页面 VM 的 playerService 都是独立实例，
 * 对账（adopt）路径绝不触发下载，不会出现两个 VM 重复预取同一首。
 *
 * 调用点之前一定先 cancelPrefetch(当前曲) 把上一首的预取掐断：蓝牙带宽是独木桥。
 */
function schedulePrefetch(seq) {
  if (seq !== player._seq) return
  if (CONFIG.PLAY && CONFIG.PLAY.PREFETCH === false) return
  const len = player.queue.length
  if (len < 2) return // 单曲队列环绕到自己，没有「下一首」可预
  const current = player.queue[player.index]
  const nextTrack = player.queue[(player.index + 1) % len]
  if (!nextTrack || sameTrack(nextTrack, current)) return
  audioCache.cancelPrefetch(current)
  audioCache
    .prefetchTrack(nextTrack, {
      resolveUrl,
      keepKeys: cacheKeysAround(player.index),
    })
    .promise.catch((e) => {
      console.warn('[Player] 预取下一首失败（不影响当前播放）:', describeError(e))
    })
}

/**
 * 取流地址解析：返回**候选地址数组**（主地址在前，backupUrl 跟上）。
 *
 * 为什么是数组：B 站每条流都给多个 CDN 节点，直链与落盘都要「一条不行换下一条」
 * （实测：主地址是 upos 时 audio.src 必 403，备地址换节点就能成）。
 * 单个字符串仍然被接受 —— 调用方（audioCache / 测试桩）两边都兼容。
 *
 * **带时效**：曲目对象上的 `track.streams` 是缓存，但 CDN 地址的 `deadline` 实测
 * 只有 120 分钟，而队列里的曲目会活一整个会话（预取还更早取回来放着）。过期地址
 * 请求回来正是 403，报错文案却是「防盗链或直链已过期」——两者的处置完全相反
 * （换节点 vs 重新取流），所以这里主动把过期地址判死，交给解析器重新取。
 *
 * @param {object} track
 * @param {object} [opts] force=true 时无视缓存强制重新取流（直链+落盘都失败后用）
 * @returns {Promise<string[]|string>}
 */
async function resolveUrl(track, opts) {
  const force = !!(opts && opts.force)
  if (!force && track) {
    if (track.playUrl) return track.playUrl
    if (Array.isArray(track.streams) && track.streams.length) {
      const fresh = filterFreshUrls(track.streams, 0, urlTtlMargin())
      if (fresh.length) return fresh
      console.warn('[Player] 曲目上的取流地址已全部过期，重新取流')
    }
    if (track.url) return track.url
  }
  if (typeof urlResolver === 'function') return urlResolver(track, opts)
  throw new Error('该曲目没有可用播放地址，且未注入取流解析器')
}

/** 取流地址的有效期余量（秒）：蓝牙链路上「下一首要下几十秒」，别卡在过期边缘开工 */
function urlTtlMargin() {
  const m = CONFIG.PLAY && CONFIG.PLAY.URL_TTL_MARGIN
  return typeof m === 'number' && m >= 0 ? m : 300
}

function startUrl(url) {
  console.log('[Player] set src =', url.length > 120 ? url.slice(0, 120) + '…' : url)
  try {
    audio.stop()
  } catch (e) {
    // 未播放时 stop 可能抛错，忽略
  }

  const track = player.queue[player.index]
  if (track) applyMeta(track)

  audio.src = url
  audio.play()
}

/**
 * 元数据双写：Vela 用 meta，QuickApp 用 title/artist/cover
 */
function applyMeta(track) {
  const title = track.title || track.name || '未知'
  const artist = track.artist || track.artists || ''
  const album = track.album || 'BiliMusic'
  const cover = track.cover || ''

  try {
    audio.meta = { title, artist, album }
  } catch (e) {
    console.warn('[Player] set meta 失败:', e)
  }
  try {
    audio.title = title
    audio.artist = artist
    audio.cover = cover
  } catch (e) {
    // 非 1040+ 设备不支持，忽略
  }
}

export async function toggle() {
  await ensureAdopted()

  if (player.state === STATE.PLAYING || player.state === STATE.LOADING) {
    try {
      audio.pause()
    } catch (e) {
      console.warn('[Player] pause 失败:', e)
    }
    setState(STATE.PAUSED)
    return
  }

  if (player.state === STATE.ERROR) {
    await playAt(player.index)
    return
  }

  // 暂停中：本 VM 有 pendingUrl，或原生播放器仍有已加载媒体（duration 读得到）→ 直接续播
  if (player._pendingUrl || player.duration > 0) {
    try {
      audio.play()
      setState(STATE.PLAYING)
    } catch (e) {
      console.warn('[Player] play 失败:', e)
      await playAt(player.index)
    }
    return
  }

  await playAt(player.index >= 0 ? player.index : 0)
}

export async function next() {
  await ensureAdopted()
  if (!player.queue.length) return
  await playAt(player.index + 1)
}

export async function prev() {
  await ensureAdopted()
  if (!player.queue.length) return
  // 播放超过 3 秒时先回到本曲开头（与主流播放器一致）
  if (player.currentTime > 3) {
    seekTo(0)
    return
  }
  await playAt(player.index - 1)
}

export function stop() {
  try {
    audio.stop()
  } catch (e) {
    // 忽略
  }
  stopReconcileTimer()
  player.currentTime = 0
  player.percent = 0
  setState(STATE.PAUSED)
  emit('progress')
}

/**
 * 按百分比拖动（0-100）
 */
export function seekPercent(percent) {
  const p = Math.max(0, Math.min(100, Number(percent) || 0))
  if (!player.duration) return
  seekTo((p / 100) * player.duration)
}

/**
 * 按秒拖动（Vela 无 seek 方法，写 currentTime 即为跳转）
 */
export function seekTo(seconds) {
  const t = Math.max(0, seconds)
  console.log('[Player] seek to', t)
  try {
    audio.currentTime = t
    player.currentTime = t
    player.percent = player.duration ? (t / player.duration) * 100 : 0
    emit('progress')
  } catch (e) {
    console.error('[Player] seek 失败:', e)
  }
}

/* ------------------------------ 音量 ------------------------------ */

/**
 * 音量：**系统媒体音量（@system.volume）是唯一真相**，本模块不自己维护一份。
 *
 * 为什么不写 `audio.volume`：它的默认值本来就是「当前系统媒体音量」（见
 * system/audio.d.ts），一旦写它，播放器音量与系统音量就变成两级串联 ——
 * 用户按实体键或去系统设置把系统音量调小，应用里的数字纹丝不动；
 * 反过来在音量页拉到 50% 也只是压掉播放器那一半，跟外面的音量谁也对不上。
 *
 * 现在：
 *  - setVolume(v) → `volume.setMediaValue`：改的就是系统音量本身，与外部同一个旋钮；
 *  - syncVolume() → `volume.getMediaValue`：任何时刻都能把真值读回来；
 *  - startVolumeWatch / stopVolumeWatch：可见页面临时接管 `onMediaValueChanged`，
 *    外部改音量时 UI 立刻跟上；
 *  - **不写 `audio.volume`**：保持它的默认值 = 跟随系统音量，避免两级串联；
 *  - 不进共享态、不落盘：跨 VM 也能对齐，因为读的是同一个系统音量。
 *
 * 事件绑定纪律（与 audio 事件同理，两边不重叠）：`onMediaValueChanged` 只由
 * **可见的音量页**在挂载时绑、销毁时解绑；app VM 与主页 VM 都不绑
 * （原生回调若是「按属性最后设置者生效」，两边都绑会互相顶掉）。
 *
 * 机型不支持 `@system.volume`（拿不到 getMediaValue/setMediaValue，例如本地 API
 * 定义标了 @OnlyQuickApp 的老设备）时降级：只读写 `audio.volume`。
 * 这时音量页仍能调，但那是播放器音量，与系统音量是两回事，日志里会写明。
 */

const hasSystemVolume =
  !!systemVolume &&
  typeof systemVolume.getMediaValue === 'function' &&
  typeof systemVolume.setMediaValue === 'function'

if (!hasSystemVolume) {
  console.warn('[Player] @system.volume 不可用，音量降级为播放器自身音量（audio.volume）')
}

let volumeWatchTimer = null

/**
 * 把音量落到镜像并广播出去。
 * 轮询与事件是两个来源，值没变就不广播，UI 不会因此抖动。
 */
function publishVolume(value, source) {
  const v = clampVolume(value, player.volume)
  if (v === player.volume) return player.volume
  player.volume = v
  console.log('[Player] 音量 =', v, '| 来源:', source)
  emit('volume')
  return player.volume
}

/** 降级路径专用：直接写播放器音量（正常路径下绝不碰 audio.volume） */
function applyPlayerVolume(v) {
  try {
    audio.volume = v
  } catch (e) {
    console.error('[Player] 设置播放器音量失败:', e)
  }
}

/**
 * 读回系统音量（真相），并刷新镜像。
 *
 * @returns {Promise<number|null>} 读不到（机型不支持 / 原生失败）时返回 null，
 *   调用方保留上一次的值即可，不要拿 null 去覆盖音量
 */
export function syncVolume() {
  if (!hasSystemVolume) {
    publishVolume(audio.volume, 'player')
    return Promise.resolve(player.volume)
  }

  return new Promise((resolve) => {
    try {
      systemVolume.getMediaValue({
        success: (data) => resolve(publishVolume(data && data.value, 'system')),
        fail: (data, code) => {
          console.warn('[Player] getMediaValue 失败, code =', code)
          resolve(null)
        },
      })
    } catch (e) {
      console.warn('[Player] getMediaValue 异常:', e)
      resolve(null)
    }
  })
}

/**
 * 设置音量（写系统音量，与实体键/系统设置同一个旋钮）
 *
 * @param {number} value 0.0-1.0
 * @returns {Promise<number>} 落定后的音量（原生失败时返回我们请求的值）
 */
export function setVolume(value) {
  const v = clampVolume(value, player.volume)
  // 先本地落值再广播：setMediaValue 的回调要等原生，UI 不该等它
  publishVolume(v, 'set')

  if (!hasSystemVolume) {
    applyPlayerVolume(v)
    return Promise.resolve(v)
  }

  return new Promise((resolve) => {
    try {
      systemVolume.setMediaValue({
        value: v,
        success: () => resolve(v),
        fail: (data, code) => {
          console.warn('[Player] setMediaValue 失败, code =', code)
          resolve(v)
        },
      })
    } catch (e) {
      console.warn('[Player] setMediaValue 异常:', e)
      resolve(v)
    }
  })
}

/**
 * 接管音量变化（**只有可见的音量页该调用**，页面销毁时必须 stopVolumeWatch）
 *
 * 双来源，缺一不可：
 *  1. `volume.onMediaValueChanged` —— 官方文档给了这个事件，但本地 API 定义没有，
 *     旧机型可能不触发或者直接不支持这个属性（赋值会抛错，故 try/catch）；
 *  2. 可见期间 1 秒一次 getMediaValue 对账 —— 兜底，保证「按实体键 / 去系统设置
 *     改音量」时页面上的数字也能跟上（音量页是临时页面，这点轮询开销可接受）。
 * 两者都经 publishVolume，值没变不广播。
 */
export function startVolumeWatch() {
  if (hasSystemVolume) {
    try {
      systemVolume.onMediaValueChanged = (res) => {
        publishVolume(res && res.value, 'event')
      }
    } catch (e) {
      console.warn('[Player] 绑定 onMediaValueChanged 失败（机型不支持？）:', e)
    }
  }

  syncVolume()
  if (volumeWatchTimer) return
  volumeWatchTimer = setInterval(() => {
    syncVolume()
  }, CONFIG.VOLUME_POLL_INTERVAL)
}

/** 页面不可见/销毁时解绑（不这么做会一直轮询，且占着原生回调槽） */
export function stopVolumeWatch() {
  if (volumeWatchTimer) {
    clearInterval(volumeWatchTimer)
    volumeWatchTimer = null
  }
  if (!hasSystemVolume) return
  try {
    systemVolume.onMediaValueChanged = null
  } catch (e) {
    // 低版本不支持该属性，忽略
  }
}

/**
 * 一次性清理历史遗留的「应用自己存的音量」。
 *
 * 老版本把音量写在 `bilimusic_settings_volume` 里（以及共享态的 volume 字段），
 * 现在音量以系统为准，这些记录已无用 —— 留着只会让人误以为应用还在自维护音量。
 * 只在键确实存在时才删除，避免每次都白打一次失败的 delete。
 */
export async function retireLegacyVolume() {
  try {
    const saved = await Storage.get(CONFIG.STORAGE_KEYS.LEGACY_VOLUME, '')
    if (saved === '') return false
    await Storage.remove(CONFIG.STORAGE_KEYS.LEGACY_VOLUME)
    console.log('[Player] 已清理历史遗留音量键（音量改由系统音量持有）')
    return true
  } catch (e) {
    console.warn('[Player] 清理历史音量键失败:', e)
    return false
  }
}

export function setLoop(loop) {
  player.loop = !!loop
  try {
    audio.loop = player.loop
  } catch (e) {
    console.error('[Player] 设置循环失败:', e)
  }
  emit('state')
  publishShareState({ loop: player.loop })
}

/* ------------------------------ 进度与状态同步 ------------------------------ */

function setState(state, patch) {
  if (player.state === state) {
    // 状态没变但带了别的字段（如 playAt 的 index）时仍然要广播出去
    if (patch) return publishShareState(Object.assign({}, patch, { state }))
    return null
  }
  player.state = state
  emit('state', { state })
  return publishShareState(Object.assign({}, patch || {}, { state }))
}

/**
 * 进度事件该不该广播。
 *
 * 为什么需要这道闸：进度是**原生事件驱动**的，ontimeupdate 4HZ + 1 秒对账每秒一次
 * syncPlayState，合计约 5 次/秒；而原生事件绑在常驻主页 VM 上，页面切到别的页
 * （更多 / 推荐 / 收藏夹…）时**不会解绑** —— 只停「1 秒对账」挡不住那 4HZ。
 * 不可见时进度没人看，emit 一次就是订阅方一次全量 applySnapshot
 * （≈10 次 setField + 封面归一化 + session.isLoggedIn），表盘上纯属白烧电。
 *
 * 只挡广播、不挡镜像刷新：currentTime / duration / percent 照常更新，
 * 页面 onShow 时 adopt()/syncPlayState() 一读就是最新值，不存在「回来要等一秒才动」。
 * 状态类事件（state / track / queue / error / fallback）一律不受影响，只挡 progress。
 */
function shouldEmitProgress() {
  return player._visible !== false
}

/**
 * 页面可见性（主页 onShow → true，onHide → false）。
 *
 * 页面不可见时：进度不再广播（见 shouldEmitProgress），订阅方的快照计算随之归零。
 * 幂等：重复 set 同一个值没有副作用。
 */
export function setVisible(visible) {
  player._visible = visible !== false
}

/**
 * 从模块属性直读进度（ontimeupdate 4HZ 调用，无异步开销）
 */
function readProgressFromProperties() {
  try {
    const ct = audio.currentTime
    if (typeof ct === 'number' && ct >= 0) player.currentTime = ct
    const d = audio.duration
    if (typeof d === 'number' && !isNaN(d) && d > 0) player.duration = d
  } catch (e) {
    // 忽略读取异常
  }
  player.percent = player.duration
    ? Math.min(100, (player.currentTime / player.duration) * 100)
    : 0
  // 页面不可见时到此为止，不 emit（见 shouldEmitProgress）
  if (!shouldEmitProgress()) return
  emit('progress')
}

function promisifyState() {
  return new Promise((resolve) => {
    try {
      if (typeof audio.getPlayState !== 'function') {
        resolve(null)
        return
      }
      audio.getPlayState({
        success: (data) => resolve(data),
        fail: () => resolve(null),
      })
    } catch (e) {
      resolve(null)
    }
  })
}

/**
 * 用系统真实状态对账，防止 UI 与底层不一致（音频焦点被抢占等）。
 * getPlayState 为 [1050+]，低版本返回 null 时退化为属性直读。
 *
 * 任何 VM 调用都能拿到**全局**播放状态（谁起的播都一样）——
 * 主页的进度环就靠它在跨 VM 场景下也能走起来。
 */
export async function syncPlayState() {
  const st = await promisifyState()
  if (!st) {
    readProgressFromProperties()
    return null
  }

  if (typeof st.currentTime === 'number' && st.currentTime >= 0) {
    player.currentTime = st.currentTime
  }
  if (typeof st.duration === 'number' && !isNaN(st.duration) && st.duration > 0) {
    player.duration = st.duration
  }
  // percent 为 @OnlyVela 字段，优先采用
  if (typeof st.percent === 'number') {
    player.percent = st.percent
  } else {
    player.percent = player.duration
      ? Math.min(100, (player.currentTime / player.duration) * 100)
      : 0
  }

  if (st.state === 'play' && player.state !== STATE.PLAYING) {
    setState(STATE.PLAYING)
  } else if (player.state === STATE.PLAYING && (st.state === 'pause' || st.state === 'stop')) {
    // 对账发现底层其实没在播（刚启动、被系统抢占、来电等）→ 状态跟着系统走。
    // 注意只从 PLAYING 降级：LOADING 期间原生 src 还没设上，原生报 stop 是正常的。
    setState(STATE.PAUSED)
  }

  // 进度镜像已刷新，但不可见时不必广播（见 shouldEmitProgress）
  if (shouldEmitProgress()) emit('progress')
  return st
}

/**
 * 低频对账定时器：进度主链路是 ontimeupdate（4HZ），
 * 这里 1 秒一次做两件事：
 *   1. syncPlayState() —— 兜底 duration 迟到、状态被系统改变
 *   2. adopt()        —— 跟上别的 VM 的切歌/暂停（跨 VM 唯一通道是 storage）
 *
 * 只在「需要看的页面可见时」跑：主页 onShow 开、onHide 关。
 * 注意它只是省电的一半 —— 原生 ontimeupdate 不受定时器约束，
 * 不可见时那 4HZ 由 setVisible(false) 挡住广播，两者要成对使用。
 */
function startReconcileTimer() {
  if (player._timer) return
  player._timer = setInterval(onTick, CONFIG.PROGRESS_INTERVAL)
}

function stopReconcileTimer() {
  if (player._timer) {
    clearInterval(player._timer)
    player._timer = null
  }
}

function onTick() {
  // 连「当前曲目」都没有时没什么可对账的，别白跑原生查询
  if (player.index < 0 && player.state === STATE.IDLE) return
  // 先跟上别的 VM 的切歌，再按原生状态刷新进度（谁起的播都一样）
  adopt()
    .then(() => syncPlayState())
    .catch((e) => console.warn('[Player] 定时对账失败:', e))
}

/** 页面可见时开启对账（主页 onShow 调用） */
export function startTicking() {
  startReconcileTimer()
}

/** 页面离开时停掉，省电（主页 onHide 调用） */
export function stopTicking() {
  stopReconcileTimer()
}

/* ------------------------------ 错误与兜底 ------------------------------ */

async function handlePlayError(err) {
  stopReconcileTimer()
  const track = player.queue[player.index]

  // Vela 的 onerror 不带任何参数（audio.d.ts: `onerror(): void`），同一轮故障系统
  // 可能连发多次；而兜底要重取流 + 整文件落盘，常常一走就是好几秒。两条守卫：
  //   1) 兜底已在路上 → 吞掉重复 onerror，别把进行中的抢救掐死（否则当场报个没有
  //      上下文的「播放失败：未知错误」，用户看到的就是这条而不是真正的病因）；
  //   2) 已停在错误态 → 同理吞掉，别让晚到的 onerror 把更准确的报错冲掉。
  if (player._recovering) {
    console.warn('[Player] 兜底进行中，忽略重复 onerror')
    return
  }
  if (player.state === STATE.ERROR) {
    console.warn('[Player] 已在错误态，忽略重复 onerror')
    return
  }

  // 抢救：直链失败/本地文件坏了都从这里走。三条路按代价排序，一条一条试：
  //
  //   ① 还有没试过的候选地址（主地址 403 了，备地址在别的 CDN 节点）→ 换下一条直链，
  //      纯起播、没有下载成本；
  //   ② 直链额度用完（或本来就没有直链可用）→ 落盘到持久缓存再播；
  //   ③ 全都不成 → 报错。
  //
  // **额度**（player._urlBudget）由节点类决定，见 parse.directLinkBudget：有 mcdn
  // 候选就给 3 条，一条都没有只给 1 条（upos/edge 直链必 403，多试只是多等一次失败）。
  // 额度用完必须落到 ②，不能在这里提前放弃 —— 否则落盘兜底永远轮不到。
  //
  // 跨 VM 注意：起播的可能是选歌页 VM，而 `onerror` 是绑在常驻主页 VM 上的，
  // 那边没有起播 VM 的 `_pendingUrl`，所以这里要就地重新取流一次。
  if (!player._retriedLocal && track && isDirectLinkRetryLeft()) {
    player._urlIndex += 1
    const next = player._urls[player._urlIndex]
    console.warn(
      '[Player] 直链失败，换候选地址',
      player._urlIndex + 1, '/', player._urlBudget,
      '(' + cdnNodeClass(next) + ')'
    )
    emit('fallback', { reason: describeError(err) })
    setState(STATE.LOADING)
    player._pendingUrl = next
    startUrl(next)
    return
  }

  if (!player._retriedLocal && track) {
    player._retriedLocal = true
    player._recovering = true
    const seq = player._seq
    try {
      setState(STATE.LOADING)
      emit('fallback', { reason: describeError(err) })

      // ② 落盘（网桥机型是常态路径；原生机型是直链全军覆没后的兜底）。
      // 全机型都走缓存：网桥机型播的本来就是落盘文件，还能错只可能是文件坏了
      // —— 删掉重下；原生机型则可能是这批直链 403 了，落一份到持久缓存，
      // 第二次播就秒开。
      //
      // **强制重新取流**：刚失败的就是曲目上那批地址，死链重试多少次都还是死链
      // （过期地址回的同样是 403，和防盗链拒绝长得一模一样）。
      const local = await audioCache.refreshTrackFile(track, {
        resolveUrl: (t) => resolveUrl(t, { force: true }),
        keepKeys: cacheKeysAround(player.index),
        onProgress: onCacheProgress(seq),
      })
      if (seq !== player._seq) {
        console.log('[Player] 落盘完成时已切歌，结果留给缓存')
        return
      }
      if (player.queue[player.index] && sameTrack(player.queue[player.index], track)) {
        player.fromCache = true
        player._pendingUrl = local.uri
        startUrl(local.uri)
        schedulePrefetch(player._seq)
      }
      return
    } catch (e) {
      if (seq !== player._seq) {
        // 兜底失败时用户已切歌：别把旧歌的错甩到新歌头上（state/error 都不动）
        console.log('[Player] 兜底失败时已切歌，错误不再打扰新曲目:', describeError(e))
        return
      }
      console.error('[Player] 落盘兜底失败:', e)
      return fail('直链与落盘均失败：' + describeError(e))
    } finally {
      player._recovering = false
    }
  }

  // 能走到这里：兜底播过仍出错（或无曲可兜）。Vela 的 onerror 没有载荷，
  // err 恒为 undefined，「未知错误」没信息量，把阶段交代出来才有排查价值。
  const stage = player.fromCache ? '重播本地文件仍失败' : '直链播放失败'
  fail('播放失败：' + stage + (err ? '：' + describeError(err) : ''))
}

function fail(message) {
  player.error = message
  setState(STATE.ERROR)
  stopReconcileTimer()
  emit('error', { message })
}

function describeError(err) {
  if (!err) return '未知错误'
  if (typeof err === 'string') return err
  if (err.code !== undefined) {
    // 底层传输码（Vela fetch 透传 libcurl，28=超时等）翻成人话，业务码原样保留
    const hint = describeNetCode(err.code)
    return `code=${err.code}${hint ? ' ' + hint : ''} ${err.data || err.message || ''}`.trim()
  }
  if (err.message) return err.message
  return safeStringify(err)
}

function safeStringify(obj) {
  try {
    return JSON.stringify(obj)
  } catch (e) {
    return String(obj)
  }
}

/**
 * 清空错误（UI 关闭错误提示时调用）
 */
export function clearError() {
  player.error = ''
  if (player.state === STATE.ERROR) setState(STATE.PAUSED)
}

export { STATE }

export default {
  init,
  subscribe,
  getSnapshot,
  setUrlResolver,
  adopt,
  setQueue,
  appendToQueue,
  removeFromQueue,
  playTrackNow,
  getQueue,
  playAt,
  toggle,
  next,
  prev,
  stop,
  seekPercent,
  seekTo,
  setVolume,
  syncVolume,
  startVolumeWatch,
  stopVolumeWatch,
  retireLegacyVolume,
  setLoop,
  syncPlayState,
  startTicking,
  stopTicking,
  setVisible,
  clearError,
  STATE,
}
