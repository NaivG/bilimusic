import { CONFIG } from '../common/config'
import { normalizeFetchResult, buildQuery } from '../common/parse'
import { getCookieHeader, ready as sessionReady } from './session'
import { BRIDGE_ERRORS, makeBridgeError } from '../common/fetchbridge'
import * as bridge from './interconnBridge'

// 供调用方复用的纯函数（实现见 common/parse.js，可被 Node 单测覆盖）
export { normalizeFetchResult, buildQuery }

/**
 * 请求层：两条通道，一个出口
 *
 *   原生通道：@system.fetch（有这条能力的机型走它，行为与以前完全一致）
 *   网桥通道：@system.interconnect → 手机/PC 端 AstroBox「网桥 FetchBridge」插件代发 HTTP
 *             （给 Redmi Watch 4 / Xiaomi Watch H1 E 这类**没有 @system.fetch** 的机型）
 *
 * 之所以只在这一个文件里做选择：api.js 本来就是全应用唯一的请求收口，且返回值一直是
 * 归一化的 `{ httpCode, body, headers }` —— 所以"抽象接口"这件事在这里就是二十来行的
 * provider 选择，biliApi / authService / 各页面一个字节都不用改。
 *
 * 关于 @system.fetch 的取用方式：require + try/catch（与 crypto.js 取 @system.crypto
 * 同一写法）。这份代码要跑在「连 @system.fetch 都没有」的机型上，静态 import 一个
 * 不存在的系统模块最坏会导致整包模块图加载失败（白屏）。若某些 runtime 不认 require，
 * 日志里会出现 `provider=bridge` 而机型本有 fetch —— 那时再退回静态 import + 机型白名单。
 */

let nativeBroken = false

/**
 * 取原生 @system.fetch 的函数入口；两种导出形态都认（模块对象 / 直接是函数）。
 */
function nativeFetchFn() {
  if (nativeBroken) return null
  try {
    const mod = require('@system.fetch')
    if (mod && typeof mod.fetch === 'function') return mod.fetch
    if (typeof mod === 'function') return mod
    return null
  } catch (e) {
    nativeBroken = true
    console.warn('[API] @system.fetch 不可用：', e && e.message ? e.message : e)
    return null
  }
}

/**
 * 本次请求走哪条通道（导出是为了可断言、也方便日志排查）
 * @returns {'native'|'bridge'}
 */
export function resolveProvider() {
  const mode = CONFIG.FETCH_BRIDGE || 'auto'
  if (mode === 'off') return 'native'
  if (mode === 'force') return bridge.isAvailable() ? 'bridge' : 'native'
  if (nativeBroken) return bridge.isAvailable() ? 'bridge' : 'native'
  if (nativeFetchFn()) return 'native'
  return bridge.isAvailable() ? 'bridge' : 'native'
}

/**
 * **仅供离线自检**：清掉「本机 fetch 不可用」的单向锁存。
 *
 * 真机上这个锁存是单向的、也不该复位（一台设备要么有 fetch 要么没有）。
 * 但 scripts/verify.mjs 要在同一个 Node 进程里先后扮演「有 fetch 的机型」和
 * 「没有 fetch 的机型」，第二次切换必须能回到干净状态 —— 只给测试用这一个口子，
 * 源码里没有任何调用点。
 */
export function __resetNativeProbe() {
  nativeBroken = false
}

/** 网桥不支持（也不需要支持）的 responseType：落盘与原始二进制 */
const BRIDGE_UNSUPPORTED_TYPES = {
  file: '落盘（responseType:file）',
  arraybuffer: '原始二进制（responseType:arraybuffer）',
}

function assertBridgeSupports(responseType) {
  const label = BRIDGE_UNSUPPORTED_TYPES[responseType]
  if (!label) return
  throw makeBridgeError(
    BRIDGE_ERRORS.UNSUPPORTED,
    '本机型没有 @system.fetch，而网桥暂不支持' + label + '（音频落盘兜底在本机型不可用）'
  )
}

/**
 * 原生通道：同时挂回调并尝试 Promise，谁先来用谁
 */
function nativeFetchOnce(options) {
  return new Promise((resolve, reject) => {
    const fn = nativeFetchFn()
    if (!fn) {
      nativeBroken = true
      reject(makeBridgeError(BRIDGE_ERRORS.UNAVAILABLE, '本机没有 @system.fetch'))
      return
    }

    let settled = false
    const ok = (val) => {
      if (settled) return
      settled = true
      resolve(val)
    }
    const bad = (data, code) => {
      if (settled) return
      settled = true
      reject({ data, code })
    }

    let maybePromise
    try {
      maybePromise = fn({
        ...options,
        success: ok,
        fail: bad,
      })
    } catch (e) {
      // 同步抛错基本等于"这个接口在本机没接上"（不是网络失败）：标记后由上层改走网桥
      nativeBroken = true
      bad(e)
      return
    }

    if (maybePromise && typeof maybePromise.then === 'function') {
      maybePromise.then(ok, bad)
    }
  })
}

/** 网桥通道：拿到的同样是 `{ code, data, headers }`，与原生形态对齐 */
function bridgeFetchOnce(options) {
  return bridge.request({
    url: options.url,
    method: options.method,
    headers: options.header,
    body: options.data,
  })
}

/**
 * 网桥响应归一化
 *
 * 原生 fetch 的 `responseType:'json'` 是**平台**帮我们 JSON.parse 的，网桥回来的永远是
 * 文本，所以这一步必须自己补上 —— 否则 biliApi 里 `res.body.code` 全是 undefined，
 * 报错会以"接口返回异常"的形式出现在离现场很远的地方。
 */
function normalizeBridgeResult(raw, responseType, url) {
  const res = normalizeFetchResult(raw)
  if (responseType === 'json' && typeof res.body === 'string') {
    const text = res.body
    if (!text) {
      res.body = null
      return res
    }
    try {
      res.body = JSON.parse(text)
    } catch (e) {
      throw makeBridgeError(
        BRIDGE_ERRORS.PROTOCOL,
        '网桥响应不是合法 JSON（' + url + '）：' + text.slice(0, 80)
      )
    }
  }
  return res
}

/**
 * 丢掉值为 undefined/null 的请求头。
 *
 * 原生层对参数的容忍度很低：header 里任何一个 undefined 值都会在
 * `convertValueToNative` 里变成空指针。
 * 
 */
function cleanHeaders(headers) {
  const out = {}
  const src = headers || {}
  Object.keys(src).forEach((k) => {
    const v = src[k]
    if (v === undefined || v === null) return
    out[k] = v
  })
  return out
}

/**
 * 统一网络请求
 * @param {object} options
 * @param {string} options.url
 * @param {string} [options.method]
 * @param {any} [options.data]
 * @param {object} [options.headers]
 * @param {string} [options.responseType] text|json|file|arraybuffer
 * @param {boolean} [options.withCookie] 是否带上登录 Cookie（先等 session 就绪再取，避免页面 VM 裸奔）
 * @returns {Promise<{httpCode:number, body:any, headers:object}>}
 */
export async function request(options) {
  const {
    url,
    method = 'GET',
    data,
    headers = {},
    responseType = 'json',
    withCookie = false,
  } = options

  const finalHeaders = cleanHeaders({
    'User-Agent': CONFIG.USER_AGENT,
    Accept: '*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    ...headers,
  })

  let cookieAttached = false
  if (withCookie) {
    // Vela 每个 page 一个独立 JS VM，模块级状态不跨页共享：登录态要各 VM 自己从
    // storage 读回来。页面若忘了 `session.ready()`，这里的 Cookie 就是空的 —— 请求
    // 裸奔，私密收藏夹会被后端判成「不是主人」→ `code=-403 访问权限不足`。
    // ready() 幂等（首次调用才真读 storage，之后直接 resolve），所以放在请求层兜底。
    await sessionReady()
    const cookie = getCookieHeader()
    if (cookie) {
      finalHeaders.Cookie = cookie
      cookieAttached = true
    }
  }

  const provider = resolveProvider()
  if (provider === 'bridge') assertBridgeSupports(responseType)

  // 联调时「403 到底是缺签名还是没带登录态」要一眼可辨，所以把 Cookie 的有无打进日志；
  // provider 也打进去 —— 网桥机型上排"为什么请求失败"第一眼看的就是它
  console.log(
    `[API] ${method} ${url} provider=${provider}${withCookie ? ` cookie=${cookieAttached ? 'on' : 'off'}` : ''}`
  )

  const nativeOptions = {
    url,
    method,
    header: finalHeaders,
    responseType,
  }
  // body 只在真的有的时候才交出去。`data: undefined` 会被原生层按字符串转换，
  // 日志里就是 `string arg is null or undefined!` —— 原生侧拿到的是空指针。
  // GET 本来也没有 body，把键去掉语义完全一样。
  if (data !== undefined && data !== null) nativeOptions.data = data

  let raw
  if (provider === 'bridge') {
    raw = await bridgeFetchOnce(nativeOptions)
    const res = normalizeBridgeResult(raw, responseType, url)
    console.log(`[API] ${method} ${url} -> http ${res.httpCode}（网桥）`)
    return res
  }

  try {
    raw = await nativeFetchOnce(nativeOptions)
  } catch (e) {
    // 原生这一跳同步失败（接口在本机没接上）且网桥可用：自动补一次网桥。
    // 只补这一次，且只在 nativeBroken 时补 —— 网络类失败不在这里重试，免得把
    // 一次普通超时变成两条链路各打一枪。
    if (!nativeBroken || !bridge.isAvailable()) throw e
    assertBridgeSupports(responseType)
    console.warn('[API] 原生 fetch 不可用，本次改走网桥：', e && e.message ? e.message : e)
    raw = await bridgeFetchOnce(nativeOptions)
    const res = normalizeBridgeResult(raw, responseType, url)
    console.log(`[API] ${method} ${url} -> http ${res.httpCode}（网桥兜底）`)
    return res
  }

  const res = normalizeFetchResult(raw)
  console.log(`[API] ${method} ${url} -> http ${res.httpCode}`)
  return res
}

/**
 * GET JSON
 */
export function get(url, params = {}, headers = {}) {
  const query = buildQuery(params)
  const fullUrl = query ? `${url}${url.indexOf('?') >= 0 ? '&' : '?'}${query}` : url
  return request({ url: fullUrl, method: 'GET', headers, responseType: 'json' })
}

/**
 * POST 表单
 */
export function post(url, data = {}, headers = {}) {
  return request({
    url,
    method: 'POST',
    data: buildQuery(data),
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      ...headers,
    },
    responseType: 'json',
  })
}

/**
 * 排查用：当前网络通道 + 网桥会话状态（日志里打这个，比逐条猜快）
 */
export function describeNetwork() {
  return {
    provider: resolveProvider(),
    mode: CONFIG.FETCH_BRIDGE,
    nativeBroken,
    bridge: bridge.isAvailable() ? bridge.describeState() : null,
  }
}

/**
 * 本次播放能不能试「直链」（`audio.src` 直接指向 CDN）。
 *
 * 只有有独立网络的机型（provider=native）才试得起：网桥机型（Redmi Watch 4 / H1 E）
 * 没有 @system.fetch 也没有独立网络，直链根本到不了设备，它们唯一的出声方式
 * 就是「落盘 → 播本地文件」。
 *
 * 与 resolveProvider() 同一判据，集中在这里，免得 playerService 自己判机型。
 */
export function usesDirectLink() {
  return resolveProvider() === 'native'
}
