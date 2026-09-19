/**
 * @system.request 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 官方语义（iot.mi.com/vela/quickapp/zh/features/network/request.html）：
 *   request.download({url, header, filename, success, fail})
 *     → success({token})；fail(data, code)（1000 下载失败 / 1001 任务不存在）
 *   request.onDownloadComplete({token, success({uri}), fail(data, code)})
 *     → success 的 uri 是**下载文件的 uri**（默认落在应用缓存目录）
 *
 * 为什么需要它：这台真机上「fetch 分块」这条路取不到字节（arraybuffer 给空 data、
 * 临时文件读不回来），而 request.download 是**原生下载管理器**：它自己把字节写进
 * 应用缓存目录，既不经 tmp 分区、也不占 JS 堆 —— 也就绕开了整条读回链路。
 *
 * 桩照抄真机形态的点：
 *   - download 只回 token，内容与 uri 一律走 onDownloadComplete（分两次回调）；
 *   - **先 completion 后注册也要能收到**（真机上代码是在 download 的 success 回调里
 *     才拿到 token 去注册监听的，慢网下这个竞态不存在，但桩不该赌顺序）；
 *   - 文件落到 `internal://cache/<filename>`，并种进 system.file 桩（于是 file.move /
 *     file.get / file.list 都能看到它，和真机一样）；
 *   - **header 必须是 String**：官方参数表里它是 String（`@system.fetch` 的 header 才是
 *     Object）。给对象真机回的是 `code=202 args type error, feature
 *     system.request, method: download` —— 任务根本建不起来。桩必须照样拒绝，
 *     否则这个真机事故在 600+ 项断言里是**隐身**的（历史教训：桩太宽容）；
 *   - 请求头**解析不出来就等于没带**：真机上打包格式不对时任务照样成功，
 *     只是 CDN 不认（upos 按 UA 过滤）→ 落下来一份 403 错误页。
 *     所以这里的「CDN」也只看解析后的 UA，而不是看我们传了什么。
 *
 * 故障注入：
 *   __setDownloadFails(code)       → download 直接 fail（1000 等）
 *   __setIgnoreHeader(on)          → 下载器不认请求头 ⇒ "下载成功"但落下来的是 403 错误页
 *   __setHeaderFormat(fmt)         → 本机认哪种 header 打包形态：
 *                                    'lines' 只认 `Key: value` 行（CRLF/LF 都算，默认）
 *                                    'json'  只认 JSON 串
 *                                    'reject' 一律回 202 args type error（真机现状）
 *   __setDelay(ms)                 → 完成回调延迟（给进度轮询留窗口）
 *   __setCompleteDelay(ms)         → 完成回调额外延迟（验总时长闸门）
 *   __setTrickle({chunk, tickMs})  → 文件**分多次增长**（每 tickMs 长 chunk 字节）：
 *                                    模拟「落点是边下边写的」—— 边下边播的事实前提
 *                                    就靠它扮演（真机的下载管理器就是这么写的）
 *   __setFeatureAvailable(on)      → 这台机型有没有 @system.request（支持明细里部分机型没有）
 */

import { __seed } from './system.file.mjs'
import { __resource } from './system.fetch.mjs'

const COMPLETE_DIR = 'internal://cache/'
/** 403 错误页正文（真机上 upos 拒绝时就是这个形状；几百字节，长度对账一眼识破） */
const DENY_PAGE = '<html><head><title>403 Forbidden</title></head><body><center><h1>403 Forbidden</h1></center><hr><center>openresty</center></body></html>'

let seq = 0
let delayMs = 0
/** 完成回调的额外延迟：模拟「任务创建得很快，但文件迟迟下不完」（验超时闸门用） */
let completeDelayMs = 0
let failCode = 0
let ignoreHeader = false
let featureAvailable = true
/** 本机认哪种打包形态：'lines' | 'json' | 'reject'（见文件头） */
let headerFormat = 'lines'
/** >0 时把落下的内容截到这么长（模拟下到一半断链） */
let truncateTo = 0
/** >0 时先只落这么多字节（模拟下载中，给进度轮询留窗口） */
let partialBytes = 0
/** 边下边播：文件分多次增长（{chunk, tickMs}；null = 一次性落完整份） */
let trickle = null
const trickleTimers = []
/** 建任务后既不 success 也不 fail（运行时静默吞掉调用） */
let createSilent = false

const pending = new Map() // token -> {uri, headers, url, filename, body, parsed}
const listeners = new Map() // token -> {success, fail}
const calls = [] // {url, header, filename, parsed}

/** 真机给参数类型错时的原话 */
const ARGS_TYPE_ERROR = 'args type error, feature system.request, method: download'

/**
 * 把资源裁到 n 字节。注意 `__resource()` 给的是 **Uint8Array**（`__setFile` 存的是 asBytes 的结果），
 * 所以只按字符串裁是裁不动的 —— 桩自己先踩过一次这个坑（截断注入静默失效）。
 */
function cutBytes(served, n) {
  if (!(n > 0) || served === null || served === undefined) return served
  if (typeof served === 'string') return served.length > n ? served.slice(0, n) : served
  if (typeof served.byteLength === 'number') {
    const view = served instanceof Uint8Array ? served : new Uint8Array(served.buffer || served)
    return view.length > n ? view.slice(0, n) : view
  }
  return served
}

/**
 * header 字符串 → 头表。**认不出来就返回 null**（等于这份请求没带定制头）：
 * 这就是「形态不对时任务照样成功、但下回来是错误页」的成因。
 */
function parseHeaderString(raw) {
  if (typeof raw !== 'string' || !raw) return null
  if (headerFormat === 'json') {
    try {
      const o = JSON.parse(raw)
      return o && typeof o === 'object' && !Array.isArray(o) ? o : null
    } catch (e) {
      return null
    }
  }
  if (headerFormat === 'reject') return null
  const out = {}
  const lines = raw.split(/\r\n|\n/).filter((l) => l.trim())
  for (let i = 0; i < lines.length; i++) {
    const at = lines[i].indexOf(':')
    if (at <= 0) return null // 不是 `名字: 值` ⇒ 整串不认
    out[lines[i].slice(0, at).trim()] = lines[i].slice(at + 1).trim()
  }
  return Object.keys(out).length ? out : null
}

export function download(options) {
  const { url, header, filename, success, fail } = options || {}
  const parsed = parseHeaderString(header)
  calls.push({ url, header, filename, parsed })

  if (!featureAvailable) throw new Error('feature not supported: @system.request')

  // 运行时静默吞掉调用：既不 success 也不 fail（页面不能因此一直挂着）
  if (createSilent) return

  // 参数类型错：对象进了 String 的位置（真机现状）。任务建不起来 —— 一个字节都不会下。
  if (header !== undefined && header !== null && typeof header !== 'string') {
    setTimeout(() => {
      if (typeof fail === 'function') fail(ARGS_TYPE_ERROR, 202)
    }, delayMs)
    return
  }
  // 本机连字符串都不收（同样回 202）
  if (headerFormat === 'reject') {
    setTimeout(() => {
      if (typeof fail === 'function') fail(ARGS_TYPE_ERROR, 202)
    }, delayMs)
    return
  }

  if (failCode) {
    const code = failCode
    setTimeout(() => {
      if (typeof fail === 'function') fail('download failed', code)
    }, delayMs)
    return
  }

  const token = 'tok-' + ++seq
  const name = typeof filename === 'string' && filename ? filename.replace(/^.*\//, '') : 'download.bin'
  const uri = COMPLETE_DIR + name
  // 请求头解析不出来（形态不对）或不认请求头 ⇒ 「下载成功」但落下来的是错误页：
  // 长度对账是唯一能识破它的东西（见 audioCache 的 downloadOnceWithShape）
  const ua = parsed && (parsed['User-Agent'] || parsed['user-agent'])
  let served = ignoreHeader || !ua ? DENY_PAGE : __resource(url)
  if (served === null || served === undefined) served = DENY_PAGE
  // 截断注入：下到一半链路断了（**不是**错误页、也不是请求头问题）——
  // 用来验「像音频但长度对不上时不换 header 形态、不重复下一遍整份」
  if (truncateTo > 0) served = cutBytes(served, truncateTo)
  const bytes = served

  setTimeout(() => {
    if (typeof success === 'function') success({ token })
    // 下载中：先只落一部分（进度轮询要看得见「文件在长」）
    if (partialBytes > 0) __seed(uri, cutBytes(bytes, partialBytes))
    // 边下边播的前提：落点是**边下边长**的。每 tickMs 长 chunk 字节，
    // 长满为止（完成回调照旧按 delayMs + completeDelayMs 来，互不干扰）
    if (trickle) {
      const totalLen = bytes.length // 字符串与 Uint8Array 都有 length
      let grown = partialBytes > 0 ? partialBytes : 0
      const timer = setInterval(() => {
        grown = Math.min(totalLen, grown + trickle.chunk)
        __seed(uri, cutBytes(bytes, grown))
        if (grown >= totalLen) clearInterval(timer)
      }, trickle.tickMs)
      trickleTimers.push(timer)
    }
  }, delayMs)

  // 完成回调（真机上是异步的、可能几十秒后才来）：
  // 先落文件再进 pending，最后才通知已注册的监听者 —— 顺序与真机一致
  setTimeout(() => {
    __seed(uri, bytes)
    pending.set(token, { uri, bytes, url, header, parsed, filename: name })
    const listener = listeners.get(token)
    if (listener && typeof listener.success === 'function') listener.success({ uri })
  }, delayMs + completeDelayMs)
  return token
}

export function onDownloadComplete(options) {
  const { token, success, fail } = options || {}
  const done = pending.get(token)
  if (done) {
    setTimeout(() => {
      if (typeof success === 'function') success({ uri: done.uri })
    }, 0)
    return
  }
  listeners.set(token, { success, fail })
}

/* --------------------------- 测试专用入口 --------------------------- */

export function __setDelay(ms) {
  delayMs = Math.max(0, Number(ms) || 0)
}

/** 完成回调的额外延迟（模拟下不完的任务：验总时长闸门） */
export function __setCompleteDelay(ms) {
  completeDelayMs = Math.max(0, Number(ms) || 0)
}

/** 让 download 直接失败（1000 下载失败 / 1001 任务不存在） */
export function __setDownloadFails(code) {
  failCode = Number(code) || 0
}

/** 模拟「下载器不认请求头」：下载成功但落下来的是 403 错误页 */
export function __setIgnoreHeader(on) {
  ignoreHeader = !!on
}

/**
 * 本机认哪种 header 打包形态：'lines'（默认，`Key: value` 行）/ 'json' / 'reject'（回 202）。
 * 换形态是 audioCache 的 HEADER_SHAPES 阶梯要验的东西：形态不对时必须能**自己发现**并换档。
 */
export function __setHeaderFormat(fmt) {
  headerFormat = fmt === 'json' || fmt === 'reject' ? fmt : 'lines'
}

/** >0 时把下载器落下的内容截到这么长（模拟「像音频但长度对不上」） */
export function __setTruncate(n) {
  truncateTo = Math.max(0, Number(n) || 0)
}

/** >0 时**先只落这么多字节**（模拟正在下载中），completeDelayMs 之后才落完整份。
 * 用来验「进度盯的是下载管理器自己的落点」——盯错位置的话进度永远是 0。
 */
export function __setSeedPartialBytes(n) {
  partialBytes = Math.max(0, Number(n) || 0)
}

/**
 * 文件分多次增长（边下边播的事实前提）：每 tickMs 长 chunk 字节，长满为止。
 * 传 null/不传关闭。计时器在 __reset 里统一清掉，测试之间不能互相漏 tick。
 */
export function __setTrickle(opts) {
  trickle =
    opts && Number(opts.chunk) > 0
      ? { chunk: Number(opts.chunk), tickMs: Math.max(1, Number(opts.tickMs) || 10) }
      : null
}

/** 建任务后**既不 success 也不 fail**（运行时静默吞掉调用：验建任务那道闸门） */
export function __setCreateSilent(on) {
  createSilent = !!on
}

/** 这台机型有没有 @system.request（源码走 require + try/catch） */
export function __setFeatureAvailable(on) {
  featureAvailable = !!on
}

/** download 调用记录：{url, header, filename, parsed}[] */
export function __calls() {
  return calls.slice()
}

export function __reset() {
  seq = 0
  delayMs = 0
  completeDelayMs = 0
  failCode = 0
  ignoreHeader = false
  featureAvailable = true
  headerFormat = 'lines'
  truncateTo = 0
  partialBytes = 0
  trickle = null
  trickleTimers.forEach((t) => clearInterval(t))
  trickleTimers.length = 0
  createSilent = false
  pending.clear()
  listeners.clear()
  calls.length = 0
}

export default { download, onDownloadComplete }
