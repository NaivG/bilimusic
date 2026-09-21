/**
 * @system.interconnect 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 它扮演两个角色：
 *   1. **原生接口**：`instance()` 返回一条连接对象（connect），语义与真机一致 ——
 *      "在 app 中以单例形式存在"，所以这里也是模块级单例，跨 VM 共用一条连接、
 *      共用一个 onmessage 槽位（多 VM 抢槽的观测点见 __bindCount()）。
 *   2. **手机端的「网桥 FetchBridge」插件**：按 PROTOCOL.md 实现握手（caps 协商）、
 *      单消息响应、v3 分片 + 累计 ACK 滑动窗口、错误帧。
 *
 * 也就是说：verify.mjs 用这个桩跑的是**真实的协议往返**，不是对着假数据断言。
 * 协议实现有出入时（比如客户端不回 ACK），这里会像真插件一样卡住 → 用例超时失败。
 *
 * 与其它桩的区别：@system.audio / storage 那些是"全局原生服务"，而本桩的
 * onmessage 槽位是**按 app 单例**的 —— 这正是真机上「多 page VM 谁收得到响应」的
 * 不确定点，测试里可以据此写出跨 VM 的行为断言。
 */

/* ------------------------------ 编码（宿主侧要发 base64 分片） ------------------------------ */

import { crc32 } from '../../src/common/fetchbridge.js'

const B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

/** JS 字符串 → UTF-8 二进制字符串（每个字符一字节，与 src/common/crypto.js 同一表示法） */
function utf8Encode(string) {
  let out = ''
  for (let n = 0; n < string.length; n++) {
    let c = string.charCodeAt(n)
    if (c < 128) {
      out += String.fromCharCode(c)
    } else if (c < 2048) {
      out += String.fromCharCode((c >> 6) | 192, (c & 63) | 128)
    } else {
      if (c >= 55296 && c <= 56319) {
        const c2 = string.charCodeAt(n + 1)
        c = 65536 + ((c & 1023) << 10) + (c2 & 1023)
        n++
      }
      out += String.fromCharCode((c >> 12) | 224, ((c >> 6) & 63) | 128, (c & 63) | 128)
    }
  }
  return out
}

/** 二进制字符串 → base64（不补内部的换行） */
function base64Encode(binary) {
  let out = ''
  for (let i = 0; i < binary.length; i += 3) {
    const b0 = binary.charCodeAt(i)
    const b1 = i + 1 < binary.length ? binary.charCodeAt(i + 1) : NaN
    const b2 = i + 2 < binary.length ? binary.charCodeAt(i + 2) : NaN
    out += B64_ALPHABET.charAt(b0 >> 2)
    out += B64_ALPHABET.charAt(((b0 & 3) << 4) | (isNaN(b1) ? 0 : b1 >> 4))
    out += isNaN(b1) ? '=' : B64_ALPHABET.charAt(((b1 & 15) << 2) | (isNaN(b2) ? 0 : b2 >> 6))
    out += isNaN(b2) ? '=' : B64_ALPHABET.charAt(b2 & 63)
  }
  return out
}

/* ------------------------------ 宿主状态 ------------------------------ */

/** 宿主插件的默认 caps（对齐 PROTOCOL.md §3.4 的"插件当前默认值"） */
const DEFAULT_HOST_CAPS = {
  version: 4,
  chunk: true,
  maxChunkSize: 4096,
  encodings: ['base64', 'hex', 'text'],
  compressions: ['none', 'deflate', 'lz4'],
  ack: true,
  ackWindow: 4,
  stream: true,
}

let routes = {}
let sentFrames = []
let ackLog = {}
let transfers = {}
let streamCancels = []
let clientCaps = null
let hostCaps = DEFAULT_HOST_CAPS
let handshakeEnabled = true
let handshakeCount = 0
let bindCount = 0
let messageHandler = null
let responseSeq = 0

const later = (fn) => setTimeout(fn, 0)

function emit(frame) {
  if (typeof messageHandler === 'function') {
    messageHandler({ data: JSON.stringify(frame) })
  }
}

/** 客户端声明的 caps → 协商结果（照抄 PROTOCOL.md §3.4，宿主视角） */
function negotiated() {
  const peer = clientCaps
  if (!peer) {
    return { version: 1, chunked: false, chunkSize: 0, ack: false, ackWindow: 0, stream: false }
  }
  const version = Math.max(1, Math.min(Number(peer.version) || 1, Number(hostCaps.version) || 1))
  const chunked = !!hostCaps.chunk && !!peer.chunk && version >= 2
  const ackWindow =
    version >= 3 && chunked && !!hostCaps.ack && !!peer.ack
      ? Math.max(1, Math.min(Number(peer.ackWindow) || 4, 64))
      : 0
  // v4 流的硬门控与插件一致：version>=4 + 双端 stream + 分片 + ACK 全齐才开流
  const stream =
    version >= 4 && !!hostCaps.stream && !!peer.stream && chunked && ackWindow > 0
  return {
    version,
    chunked,
    chunkSize: chunked ? Math.max(256, Math.min(Number(peer.maxChunkSize) || 4096, 65536)) : 0,
    ack: ackWindow > 0,
    ackWindow,
    stream,
  }
}

/* ------------------------------ 连接对象（app 单例） ------------------------------ */

function handleSend(payload, success, fail) {
  if (!payload || typeof payload !== 'object') {
    if (typeof fail === 'function') later(() => fail({ data: 'payload must be object' }, 1000))
    return
  }
  sentFrames.push(payload)
  if (typeof success === 'function') later(success)

  if (payload.tag === '__hs__') {
    if (!handshakeEnabled) return // 没回音：模拟 AstroBox 里没给这个应用打开「监听」
    handshakeCount++
    if (payload.caps) clientCaps = payload.caps
    const count = Number(payload.count) || 0
    if (count < 2) {
      later(() => emit({ tag: '__hs__', count: count + 1, caps: hostCaps }))
    }
    return
  }

  if (payload.tag === 'fetch') {
    later(() => handleFetch(payload))
    return
  }

  if (payload.tag === 'fetch-ack') {
    const id = payload.id
    if (!ackLog[id]) ackLog[id] = []
    ackLog[id].push(Number(payload.ack))
    const t = transfers[id]
    if (t) {
      t.base = Math.max(t.base, Math.min(Number(payload.ack) || 0, t.parts.length))
      if (t.base >= t.parts.length) delete transfers[id]
      else pump(id)
    }
    return
  }

  // ---- v4 流（PROTOCOL.md §6.3/§6.4）：累计 ACK 推进窗口，取消则关掉数据源 ----
  if (payload.tag === 'fetch-stream-ack') {
    const id = payload.id
    if (!ackLog[id]) ackLog[id] = []
    ackLog[id].push(Number(payload.ack))
    const t = transfers[id]
    if (!t || t.kind !== 'stream') return
    const total = t.parts.length + 1 // 结束帧也占一个序号
    const want = Math.max(0, Math.min(Number(payload.ack) || 0, total))
    if (want > t.base) {
      t.base = want
      if (t.base >= total) delete transfers[id]
      else pumpStream(id)
      return
    }
    // ACK 停在原地（有在途未确认）：按插件同款 go-back-N 重传整窗（每个停滞点只重传一次）
    if (t.next > t.base && !t.retried[t.base]) {
      t.retried[t.base] = true
      t.dropped = {} // 重传这一轮把「首传丢帧」放回来
      t.next = t.base
      pumpStream(id)
    }
    return
  }

  if (payload.tag === 'fetch-stream-cancel') {
    streamCancels.push({ id: payload.id, reason: payload.reason || '' })
    delete transfers[payload.id]
    return
  }
  // 未知 tag：真插件也是只记日志
}

function handleFetch(payload) {
  const route = routes[payload.url]
  const n = negotiated()

  // 配了 silent 的路由：什么都不回（用来验证客户端的请求超时兜底）
  if (!route || route.silent) {
    if (!route) {
      emit({
        tag: 'fetch',
        id: payload.id,
        resp: { ok: false, status: 0, statusText: '桩：没有为 ' + payload.url + ' 配置路由', headers: {}, body: '', raw: false },
      })
    }
    return
  }
  if (route.error) {
    emit({
      tag: 'fetch',
      id: payload.id,
      resp: { ok: false, status: 0, statusText: route.error, headers: {}, body: '', raw: false },
    })
    return
  }

  const body = route.body === undefined || route.body === null ? '' : String(route.body)
  const status = route.status || 200
  const headers = route.headers || { 'content-type': 'application/json' }

  if (route.stream) {
    if (n.stream) {
      // v4 已协商：走开放长度流（头部 + fetch-stream 帧 + 结束帧）
      startStream(payload.id, { body: body, status: status, headers: headers, route: route, negotiated: n })
      return
    }
    // 未协商 v4：按协议「忽略 stream，安全回退有限响应」（对齐真插件行为）
  }

  if (route.chunked) {
    startChunked(payload.id, { body: body, status: status, headers: headers, route: route, negotiated: n })
    return
  }

  const encoding = route.singleEncoding || 'text'
  emit({
    tag: 'fetch',
    id: payload.id,
    resp: {
      ok: true,
      status: status,
      statusText: 'OK',
      headers: headers,
      body: encoding === 'text' ? body : base64Encode(utf8Encode(body)),
      raw: false,
      bodyEncoding: encoding,
      compression: 'none',
    },
  })
}

function startChunked(id, ctx) {
  const bytes = utf8Encode(ctx.body)
  const chunkSize = ctx.route.chunkSize || ctx.negotiated.chunkSize || 4096
  const parts = []
  for (let i = 0; i < bytes.length; i += chunkSize) parts.push(bytes.slice(i, i + chunkSize))
  if (parts.length === 0) parts.push('')
  // 路由可以强行关掉 ACK（用来复现 v2 那种无流控分片），默认跟协商走
  const useAck = ctx.route.ack === false ? false : !!ctx.negotiated.ack
  transfers[id] = {
    parts: parts,
    next: 0,
    base: 0,
    window: useAck ? ctx.negotiated.ackWindow || 4 : 0,
    useAck: useAck,
    id: id,
  }

  emit({
    tag: 'fetch',
    id: id,
    resp: {
      ok: true,
      status: ctx.status,
      statusText: 'OK',
      headers: ctx.headers,
      body: '',
      raw: false,
      chunked: true,
      totalBytes: bytes.length,
      chunkSize: chunkSize,
      chunkCount: parts.length,
      bodyEncoding: 'base64',
      compression: 'none',
      ack: useAck,
    },
  })
  pump(id)
}

/** 发送窗口内的分片（ACK 模式下每收到一个 ACK 才继续发 —— 与插件同一套滑动窗口） */
function pump(id) {
  const t = transfers[id]
  if (!t) return
  const limit = t.useAck ? t.base + t.window : t.parts.length
  while (t.next < t.parts.length && t.next < limit) {
    const seq = t.next
    t.next++
    emit({
      tag: 'fetch-chunk',
      id: id,
      seq: seq,
      total: t.parts.length,
      data: base64Encode(t.parts[seq]),
    })
  }
  // 无 ACK 模式：一次发完即结束（插件 v2 路径）
  if (!t.useAck && t.next >= t.parts.length) delete transfers[id]
}

/* --------------------- v4 开放长度流（桩扮演 v4 插件） --------------------- */

/**
 * 流式响应：头部（tag:'fetch' + resp.stream）→ 数据帧（fetch-stream）→ 结束帧
 * （data 为空、final:true、totalBytes 为全量）。帧内 CRC32 用的是与手表端同一份
 * 实现（直接 import src/common/fetchbridge.js）—— 两端算出不同值就是 bug 本身。
 *
 * 路由可注入的故障（真机不好造，桩里专门给）：
 *   corruptSeq   该序号的数据帧故意多塞一个字节 → CRC 必不过，客户端应取消整笔
 *   dropSeq      [seq] 首传跳过该帧 → 客户端 ACK 停滞 → 桩 go-back-N 重传补齐
 *   streamError  发出这么多个数据帧后改发 fetch-stream-error（模拟读流中断）
 */
function startStream(id, ctx) {
  // 客户端可能在桩处理 fetch 之前就取消（fetch 是延迟处理的，cancel 是同步的）：
  // 迟到的 fetch 不许再起流，否则传输没人认领、永远留在窗口里（真插件按消息
  // 顺序处理不会这样，桩必须补上同一语义）
  if (streamCancels.some((c) => c.id === id)) return
  const bytes = utf8Encode(ctx.body)
  const chunkSize = ctx.route.chunkSize || ctx.negotiated.chunkSize || 4096
  const parts = []
  for (let i = 0; i < bytes.length; i += chunkSize) parts.push(bytes.slice(i, i + chunkSize))
  const totalBytes = bytes.length

  const dropSeq = Array.isArray(ctx.route.dropSeq) ? ctx.route.dropSeq : []
  transfers[id] = {
    kind: 'stream',
    parts,
    totalBytes,
    chunkSize,
    next: 0,
    base: 0,
    window: ctx.negotiated.ackWindow || 4,
    stalled: !!ctx.route.streamStall, // 发完头部就装死（测客户端的流空闲超时）
    dropped: dropSeq.reduce((acc, seq) => {
      acc[seq] = true
      return acc
    }, {}),
    retried: {},
    corruptSeq: ctx.route.corruptSeq,
    corrupted: false,
    errorAfter: ctx.route.streamError,
    sentCount: 0,
    id: id,
  }

  emit({
    tag: 'fetch',
    id: id,
    resp: {
      ok: true,
      status: ctx.status,
      statusText: 'OK',
      headers: ctx.headers,
      body: '',
      raw: true,
      stream: true,
      chunkSize: chunkSize,
      fixedChunks: true,
      bodyEncoding: 'base64',
      compression: 'none',
      ack: true,
      checksum: 'crc32',
      contentLength: totalBytes,
    },
  })
  pumpStream(id)
}

function pumpStream(id) {
  const t = transfers[id]
  if (!t || t.kind !== 'stream') return
  if (t.stalled) return // 头部之后一个帧都不发：模拟读流卡死
  const total = t.parts.length + 1 // 数据帧 + 结束帧
  const limit = t.base + t.window
  while (t.next < total && t.next < limit) {
    const seq = t.next
    if (t.dropped[seq]) {
      // 首传丢帧：不发但要推进 next（留出空洞），靠 go-back-N 补发
      t.next++
      continue
    }
    if (t.errorAfter !== undefined && t.errorAfter !== null && t.sentCount >= t.errorAfter) {
      emit({ tag: 'fetch-stream-error', id: id, message: 'stub: 读流中断（注入故障）' })
      delete transfers[id]
      return
    }
    t.next++
    t.sentCount++
    const isFinal = seq === t.parts.length
    if (isFinal) {
      emit({
        tag: 'fetch-stream',
        id: id,
        seq: seq,
        offset: t.totalBytes,
        data: '',
        crc32: '00000000',
        final: true,
        totalBytes: t.totalBytes,
      })
      continue
    }
    let payload = t.parts[seq]
    if (t.corruptSeq === seq && !t.corrupted) {
      t.corrupted = true
      payload = payload + 'x' // 字节损坏，但 CRC 仍按**原始**数据算（真损坏 = 校验对不上）
    }
    emit({
      tag: 'fetch-stream',
      id: id,
      seq: seq,
      offset: seq * t.chunkSize, // fixedChunks 语义：非尾帧 offset === seq*chunkSize
      data: base64Encode(payload),
      crc32: crc32(t.parts[seq]),
    })
  }
}

/** app 单例连接：每次 instance() 拿到的是同一个对象（官方文档：在 app 中以单例形式存在） */
const connect = {
  getReadyState(obj) {
    const o = obj || {}
    later(() => {
      if (typeof o.success === 'function') o.success({ status: 1 })
    })
  },
  diagnosis(obj) {
    const o = obj || {}
    later(() => {
      if (typeof o.success === 'function') o.success({ status: handshakeEnabled ? 0 : 204 })
    })
  },
  send(obj) {
    const o = obj || {}
    handleSend(o.data, o.success, o.fail)
  },
}

// onmessage 是"属性槽"（真机语义）：用 setter 记下被赋值多少次 ——
// 多 page VM 同时用一条连接时，"谁持有槽位"就是靠这个观测的
Object.defineProperty(connect, 'onmessage', {
  get() {
    return messageHandler
  },
  set(fn) {
    bindCount++
    messageHandler = fn
  },
  enumerable: true,
  configurable: true,
})

connect.onopen = null
connect.onclose = null
connect.onerror = null

export function instance() {
  responseSeq++
  return connect
}

/** 原生模块的默认导出形态（与其它桩保持一致） */
export default { instance }

/* ------------------------------ 测试用钩子 ------------------------------ */

/** 清空路由、日志与会话状态（不动 connect 本身） */
export function __reset() {
  routes = {}
  sentFrames = []
  ackLog = {}
  transfers = {}
  streamCancels = []
  hostCaps = DEFAULT_HOST_CAPS
  handshakeEnabled = true
  handshakeCount = 0
  bindCount = 0
  messageHandler = null
  // clientCaps 刻意**不清**：真插件按「设备地址 + 快应用包名」记协商会话（600s 空闲），
  // 不会因为测试重置路由就忘了对端 caps。清了它，缓存过 peerCaps 的客户端实例再发
  // 请求会被当 v1 处理（流式请求被降级成普通响应），那是真实链路上不该有的状态。
  // 新 VM 的握手会刷新它；要模拟「宿主重启」用 __setHandshake(false) + 新 VM 表达。
  connect.onopen = null
  connect.onclose = null
  connect.onerror = null
}

/**
 * 配一条路由
 * @param {string} url
 * @param {object} route
 *   body           响应体（字符串）
 *   status         HTTP 状态码，默认 200
 *   headers        响应头
 *   singleEncoding 'text'（默认）| 'base64'
 *   chunked        true 走 v2/v3 分片路径
 *   chunkSize      分片大小（编码前字节数），覆盖协商值
 *   ack            false 时强制关掉 ACK 流控（复现 v2 无流控分片）
 *   error          直接回 ok:false 的错误帧（网络类失败）
 *   stream         true 走 v4 开放长度流（未协商 v4 时按协议回退有限响应）
 *   corruptSeq     v4 流：该序号数据帧故意损坏（CRC 校验失败的回归）
 *   dropSeq        v4 流：[seq] 首传跳过，靠 go-back-N 重传补齐
 *   streamError    v4 流：发出这么多个数据帧后改发 fetch-stream-error
 */
export function __setRoute(url, route) {
  routes[url] = route || {}
}

/** 覆盖宿主 caps（例如把 ack 关掉，看客户端会不会退回 v1/v2 行为） */
export function __setHostCaps(caps) {
  hostCaps = caps || DEFAULT_HOST_CAPS
}

/** false = 握手不回任何包（模拟"设备没连/没在 AstroBox 里给本应用开监听"） */
export function __setHandshake(enabled) {
  handshakeEnabled = !!enabled
}

/** 客户端发过来的所有帧（已 parse） */
export function __sent() {
  return sentFrames.slice()
}

export function __lastSent(tag) {
  for (let i = sentFrames.length - 1; i >= 0; i--) {
    if (!tag || sentFrames[i].tag === tag) return sentFrames[i]
  }
  return null
}

/** 某笔请求收到的 ACK 序列（累计 ACK 必须单调不减，且每片一次） */
export function __acks(id) {
  return (ackLog[id] || []).slice()
}

/** onmessage 被赋值次数：多 VM 抢槽时"发之前重绑"的观测点 */
export function __bindCount() {
  return bindCount
}

/** 还有多少笔分片传输没发完（>0 说明窗口卡住了） */
export function __inflightTransfers() {
  return Object.keys(transfers)
}

/** 收到的 v4 流取消帧（[{id, reason}]）：客户端 CRC 失败/主动取消都会走到这 */
export function __streamCancels() {
  return streamCancels.slice()
}

/** 模拟连接断开：触发客户端的 onclose（在途请求应立刻失败，而不是各自等到超时） */
export function __emitClose(code) {
  if (typeof connect.onclose === 'function') connect.onclose({ code: code || 1006, data: 'closed' })
}

/** 连接对象本身（断言 onmessage 归属用） */
export function __connect() {
  return connect
}

/**
 * 直接往当前的 onmessage 槽里塞一帧（不经过 send）。
 * 用来验证客户端对"不是自己 id 的帧 / 未知 tag"的处理 —— 真机上同一条 app 单例连接
 * 会把别的 page VM 的帧也送到持有槽位的那份代码里。
 */
export function __emitRaw(frame) {
  emit(frame)
}
