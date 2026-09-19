/**
 * @system.fetch 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 三种注入方式：
 *   1) **JSON 预设**（B 站接口调用）：没注入响应就直接抛错（离线测试不该联网）
 *        __setJson(body)              → success({code:200, data:body})，B 站信封原样给
 *        __setResponse({code,data})   → 同上但 HTTP 状态码自定（403/302 也会走 success，
 *                                       这正是「错误响应体被存成 tmp 文件」的现场）
 *        __setFail(code, data)        → fail(data, code)，按官方回调形态（code=28 超时等）
 *        __setDelay(ms)               → 回调延迟，模拟慢网/给兜底竞态留窗口
 *   2) **文件流**（audioCache 的音频落盘调用）：按 URL 种一份字节，桩自己实现
 *      **Range 语义**（206 + Content-Range），让「分块下载 + 断点续传」这条链路
 *      能在离线环境里被真跑一遍：
 *        __setFile(url, bytes)        → 注册可下载资源
 *        __setChunkBytes(n)           → 单次响应最多给多少字节（模拟慢链路一次拿不完）
 *        __setChunkFails(n)           → 下 n 次文件请求直接 fail（模拟蓝牙抖动/超时）
 *        __setArrayBufferBroken(on)   → **真机现场**：code/headers 齐全、data 是空的
 *        __setTmpFileMissing(on)      → responseType:file 给的临时文件根本不存在
 *   （tmp 分区默认读不了 —— 见 system.file.mjs 的 __setTmpReadAllowed，那是第二道真机现场）
 *   3) 在 1)、2) 都没有命中时抛错（离线测试不该发起真实网络请求）。
 *
 * **桩必须照抄真机形态**（吃过一次大亏）：文件流响应体严格按官方
 * 「responseType 与 success 中 data 关系」表构造 —— arraybuffer 给 ArrayBuffer、
 * file/缺省给**临时文件 uri**。这里曾经不管 responseType 一律回 Uint8Array，
 * 于是「真机 arraybuffer 拿不到字节」这类读法问题在离线 500+ 项里完全看不出来
 * （与 `status`/`code` 那次是同一类坑）。
 *
 * 桩把每次调用的 url/method/header/responseType 记下来（__last() / __requests() 断言）。
 * api.js 的 fetchOnce 同时认回调与 Promise 两种形态，这里只走回调，避免重复 settle。
 */

import { __seed } from './system.file.mjs'

let cannedRes = null // { code, data, headers }
let failPreset = null // { code, data }
let failAlways = null // { code, data }：持续失败，直到显式清掉
let delayMs = 0
/** 模拟「本机 responseType:'arraybuffer' 拿不到字节」：真机上 data 是空的 */
let arrayBufferBroken = false
/** arraybuffer 读法被运行时无视、直接给临时文件 uri（见 respondBody） */
let arrayBufferAsUri = false
/** 模拟「响应体太大就被运行时丢掉」（>0 时：arraybuffer 且超过这个字节数 → data 为空） */
let arrayBufferMaxBytes = 0
/** 模拟「responseType:'file' 给的临时文件读不回来」（不种文件 → readArrayBuffer 301） */
let tmpFileMissing = false
/** 临时文件 uri 序号（每次响应一个新 uri，与真机一致） */
let tmpSeq = 0
/** 还有几次文件请求要回「2xx 但没有响应体」 */
let emptyBodyTimes = 0
const requests = []

/** 可下载资源：url -> Uint8Array */
const files = new Map()
/** 单次响应最多给多少字节（0 = 不限制，一次给完） */
let chunkBytes = 0
/** 还需要失败几次（文件请求），模拟慢链路上的超时 */
let chunkFails = 0
/** true = 这个节点不支持 Range（无视 Range 直接回整份 200） */
let rangeIgnored = false

function asBytes(content) {
  if (content instanceof Uint8Array) return content
  if (content instanceof ArrayBuffer) return new Uint8Array(content)
  return new TextEncoder().encode(String(content))
}

/** 'bytes=262144-524287' → {from, to}；不带 Range → null */
function parseRangeHeader(header) {
  const raw = header && (header.Range || header.range)
  const m = String(raw || '').match(/bytes=(\d+)-(\d*)/i)
  if (!m) return null
  return { from: parseInt(m[1], 10), to: m[2] === '' ? null : parseInt(m[2], 10) }
}

/**
 * 文件流路径：实现了 Range 语义的那条响应
 *
 * **字段名必须是 `code`**：官方文档「success 返回值」表就是 code / data / headers 三个
 * （https://iot.mi.com/vela/quickapp/zh/features/network/fetch.html）。
 * 这里曾经图省事写成 `status`，于是桩和真机各说各话：离线 500+ 项全绿，
 * 真机上 `res.status` 恒为 undefined —— 一句话的字段名，把整条音频落盘链路废掉了。
 * 桩的职责就是**照抄真机形态**，不许自创。
 */
function resolveFileResponse(url, header, responseType) {
  const body = files.get(url)
  if (!body) return null
  const range = parseRangeHeader(header)
  if (!range || rangeIgnored) {
    // 不带 Range，或服务器压根不支持 Range（真机上有这种节点）→ 整份 200
    return respondBody(200, body, { 'Content-Length': String(body.length) }, responseType)
  }
  const from = Math.min(range.from, body.length)
  let to = range.to === null ? body.length - 1 : Math.min(range.to, body.length - 1)
  // 慢链路模拟：服务器一次只给 chunkBytes 字节就收尾（Range 语义允许提前结束）
  if (chunkBytes > 0 && to - from + 1 > chunkBytes) to = from + chunkBytes - 1
  const slice = body.slice(from, to + 1)
  return respondBody(
    206,
    slice,
    {
      'Content-Range': 'bytes ' + from + '-' + (from + slice.length - 1) + '/' + body.length,
      'Content-Length': String(slice.length),
    },
    responseType
  )
}

/**
 * 按官方「responseType 与 success 中 data 关系」表构造响应体：
 *   arraybuffer       → ArrayBuffer（真机坏掉时是 undefined，见 __setArrayBufferBroken）
 *   file / 未指定     → **存储的临时文件的 uri**（框架原生落盘，不是字节）
 *
 * 第二种形态尤其要照抄：`responseType:'file'` 给的是一段 uri 文本，
 * 谁把它当字节写进 .part，谁就在往音频文件里塞路径字符串。
 */
function respondBody(code, bytes, headers, responseType) {
  if (responseType === 'arraybuffer') {
    // 真机上 responseType 也可能被**无视**：非文本内容一律落到临时文件，给回一段 uri 文本
    // （官方 responseType 表里「不指定且内容不是文本」就是这个形态）。
    if (arrayBufferAsUri) {
      const uri = 'internal://tmp/fetch-' + ++tmpSeq
      if (!tmpFileMissing) __seed(uri, bytes)
      return { code, data: uri, headers }
    }
    // 两种「206 + 合法 Content-Range + 没有字节」的真机现场：
    //   ①这台机型的 arraybuffer 就是拿不到字节（__setArrayBufferBroken）
    //   ②响应体太大被运行时丢掉（__setArrayBufferMaxBytes）——快应用规范里 fetch
    //     明写「数据大小不能超过 100k」，256 KB 正好越线
    if (arrayBufferBroken || (arrayBufferMaxBytes > 0 && bytes.length > arrayBufferMaxBytes)) {
      return { code, data: undefined, headers }
    }
    return { code, data: bytes.buffer, headers }
  }
  const uri = 'internal://tmp/fetch-' + ++tmpSeq
  if (!tmpFileMissing) __seed(uri, bytes)
  return { code, data: uri, headers }
}

export function fetch(options) {
  const { url, method = 'GET', header = {}, data, responseType, success, fail } = options || {}
  requests.push({ url, method, header, data, responseType })

  // 持续失败（一直生效，直到传入 null/0 清掉）：验「下载彻底失败」的报错链路
  if (failAlways) {
    setTimeout(() => {
      if (typeof fail === 'function') fail(failAlways.data, failAlways.code)
    }, delayMs)
    return
  }

  // 文件流优先：音频落盘走这条路（api.js 的 JSON 请求不会命中 files 表）
  if (files.has(url)) {
    if (chunkFails > 0) {
      chunkFails--
      setTimeout(() => {
        if (typeof fail === 'function') fail('operation timed out', 28)
      }, delayMs)
      return
    }
    const res = resolveFileResponse(url, header, responseType)
    if (emptyBodyTimes > 0) {
      // 「2xx 但没有字节」：状态码与 Content-Range 都对，就是没有响应体。
      // 真机上两种成因都出现过 —— 传输被掐断（该重试），或本机读法拿不到字节（该换读法）。
      emptyBodyTimes--
      setTimeout(() => {
        if (typeof success === 'function') {
          success({ code: res.code, data: undefined, headers: res.headers })
        }
      }, delayMs)
      return
    }
    setTimeout(() => {
      if (typeof success === 'function') success(res)
    }, delayMs)
    return
  }

  if (!cannedRes && !failPreset) {
    throw new Error('桩：离线测试不应发起真实网络请求，请先 __setJson()/__setFile() 注入响应')
  }

  setTimeout(() => {
    if (failPreset) {
      if (typeof fail === 'function') fail(failPreset.data, failPreset.code)
      return
    }
    if (typeof success === 'function') success(cannedRes)
  }, delayMs)
}

/* --------------------------- JSON 预设 --------------------------- */

/** 注入下一次请求的完整响应（code = HTTP 状态码） */
export function __setResponse(res) {
  cannedRes = { code: 200, data: null, headers: {}, ...(res || {}) }
  failPreset = null
}

/** 注入下一次请求的失败（按官方 fail(data, code) 形态回调，只影响一次） */
export function __setFail(code, data) {
  failPreset = { code, data }
  cannedRes = null
}

/**
 * 持续失败：设置后**每一次**请求都 fail，直到 __setFailAlways(null) 清掉。
 * 用来验「落盘彻底失败」的报错链路（分块重试会连发多次请求，一次性的 __setFail
 * 会被第一次重试就吃掉）。
 */
export function __setFailAlways(code, data) {
  failAlways = code === null || code === undefined || code === 0 ? null : { code, data }
}

/** 下一次请求的回调延迟（毫秒），模拟慢网/超时窗口 */
export function __setDelay(ms) {
  delayMs = Math.max(0, Number(ms) || 0)
}

/** 注入下一次请求的响应体（B 站信封原样给，例如 {code:0,data:{...}}） */
export function __setJson(body) {
  __setResponse({ code: 200, data: body, headers: {} })
}

/* --------------------------- 文件流（音频落盘） --------------------------- */

/** 注册一个可下载资源；桩按 Range 语义切片返回 206 */
export function __setFile(url, content) {
  files.set(url, asBytes(content))
}

/** 取消注册 */
export function __clearFile(url) {
  files.delete(url)
}

/** 单次响应最多给多少字节（模拟慢链路：一次拿不完，要多次 Range） */
export function __setChunkBytes(n) {
  chunkBytes = Math.max(0, Number(n) || 0)
}

/** 接下来 n 次文件请求直接 fail(code=28)，用来验「分块重试 + 断点续传」 */
export function __setChunkFails(n) {
  chunkFails = Math.max(0, Number(n) || 0)
}

/** 模拟「这个 CDN 节点不支持 Range」：无视 Range 直接回整份 200 */
export function __setRangeIgnored(on) {
  rangeIgnored = !!on
}

/**
 * 模拟真机上 `responseType:'arraybuffer'` **拿不到字节**的机型：
 * 响应仍是 206 + 合法 Content-Range + 正确请求头，唯独 data 是空的。
 * 这是 audioCache 里「换 file 读法」兜底的唯一触发条件。
 */
export function __setArrayBufferBroken(on) {
  arrayBufferBroken = !!on
}

/**
 * 模拟「responseType:'arraybuffer' 被运行时无视，给回临时文件 uri」的机型
 * （官方 responseType 表：不指定 responseType 且内容不是文本时，给的就是临时文件 uri）。
 *
 * 这条要单独能装出来，是因为它的失败方式是**静默**的：那串 uri 是字符串，
 * 而 bytesOfBody 认字符串为二进制串 —— 不认出来就会把 uri 文本当音频写进 .part，
 * 文件长度不对却看着像下好了。
 */
export function __setArrayBufferAsUri(on) {
  arrayBufferAsUri = !!on
}

/**
 * 模拟「响应体超过这个字节数就被运行时丢掉」（arraybuffer 读法）。
 * 快应用规范里 fetch 写着「数据大小不能超过 100k」——audioCache 的 Range 档位阶梯
 * （256K → 64K → 32K → 16K）就是为这条现象准备的。
 */
export function __setArrayBufferMaxBytes(n) {
  arrayBufferMaxBytes = Math.max(0, Number(n) || 0)
}

/** 注册过的可下载资源字节（@system.request 桩要用同一份内容） */
export function __resource(url) {
  return files.get(url) || null
}

/** 模拟 `responseType:'file'` 给的临时文件根本不存在（不种文件：读回与拷出都会失败） */
export function __setTmpFileMissing(on) {
  tmpFileMissing = !!on
}

/**
 * 接下来 n 次文件请求回「2xx 但没有响应体」（不看读法）。
 * 用来验两件事：①瞬时空体应当重试（不是一次就判死）；②持续空体的报错要带现场。
 */
export function __setEmptyBodyTimes(n) {
  emptyBodyTimes = Math.max(0, Number(n) || 0)
}

export function __requests() {
  return requests.slice()
}

export function __last() {
  return requests.length ? requests[requests.length - 1] : null
}

export function __reset() {
  cannedRes = null
  failPreset = null
  failAlways = null
  delayMs = 0
  chunkBytes = 0
  chunkFails = 0
  rangeIgnored = false
  arrayBufferBroken = false
  arrayBufferAsUri = false
  arrayBufferMaxBytes = 0
  tmpFileMissing = false
  tmpSeq = 0
  emptyBodyTimes = 0
  files.clear()
  requests.length = 0
}

export default { fetch }
