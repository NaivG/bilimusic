/**
 * interconnect 网桥客户端（手表侧）
 *
 * 把「没有 @system.fetch 的机型」接回 B 站接口链路：
 *
 *   api.js ──► 本模块 ──@system.interconnect──► 手机 的 AstroBox「网桥 FetchBridge」插件
 *                                                 └─► 真正的 HTTP
 *
 * 协议细节与解码/重组逻辑都在 common/fetchbridge.js（纯函数，可离线单测）；
 * 这里只管**会话**：单例连接的取用、握手、请求多路复用、超时与错误归类，
 * 以及 v4 流式请求（B 档音频落盘）的帧接收、增量 ACK、取消与空闲超时。
 *
 * 三个会话语义要点：
 *
 *  1. **`instance()` 在 app 内是单例**（官方文档原话），跨 page VM 共用一条连接。
 *     而 onmessage 是"属性槽"，多 VM 同时用大概率是最后设置者生效（与 @system.audio
 *     事件同一模式）。所以每次发送前都重绑一次 onmessage —— 谁在发请求谁持有槽位，
 *     并把"不是自己 id 的帧"直接忽略，避免串台。
 *
 *  2. **id 前缀带本 VM 随机 token**：同一条连接上可能有别的 page VM 的请求在飞，
 *     只有 id 前缀能区分归属。
 *
 *  3. 连接断开（onclose/onerror）要把所有 in-flight 请求一次性失败掉，不能让页面
 *     各自等到超时 —— 那会叠出一堆"莫名卡 20 秒"。
 */

import { CONFIG } from '../common/config'
import {
  BRIDGE_TAGS,
  BRIDGE_ERRORS,
  makeBridgeError,
  buildLocalCaps,
  negotiateCaps,
  parseBridgeMessage,
  buildFetchRequest,
  toBridgeEnvelope,
  decodeSingleBody,
  ChunkAssembler,
  StreamAssembler,
} from '../common/fetchbridge'

/* ------------------------------ 模块加载 ------------------------------ */

let interconnectModule
let interconnectProbed = false

/**
 * 取 @system.interconnect。
 *
 * 用 require + try/catch 而不是静态 import（与 crypto.js 取 @system.crypto 同一写法）：
 * 这份代码要跑在"连 @system.fetch 都没有"的机型上，静态 import 一个不存在的系统模块
 * 会怎么失败没人保证得了（最坏是整包模块图加载失败 → 白屏）。require 失败只会让
 * isAvailable() 返回 false，退化成"网桥不可用"，别的地方照常跑。
 *
 * 离线自检里由 scripts/verify.mjs 注入同名 require 指到桩模块。
 */
function interconnectApi() {
  if (!interconnectProbed) {
    interconnectProbed = true
    try {
      interconnectModule = require('@system.interconnect')
    } catch (e) {
      interconnectModule = null
      console.warn('[Bridge] @system.interconnect 不可用：', e && e.message ? e.message : e)
    }
  }
  return interconnectModule
}

/** 本机运行时有 interconnect 才算"网桥可用"（有接口不代表手机端在听，那是握手的事） */
export function isAvailable() {
  const api = interconnectApi()
  return !!(api && typeof api.instance === 'function')
}

/* ------------------------------ 会话状态 ------------------------------ */

/** 本 VM 的请求 id 前缀：同一条连接上区分"谁的请求"（见文件头第 2 点） */
const VM_TOKEN = Math.floor(Math.random() * 0xffffff).toString(36)

let conn = null
let closed = false
let peerCaps = null
let handshakePromise = null
let handshakeResolve = null
let handshakeReject = null
let handshakeTimer = null
let pending = {}
let idSeq = 0

function bridgeConfig() {
  return CONFIG.BRIDGE || {}
}

function ensureConn() {
  if (conn) return conn
  const api = interconnectApi()
  if (!api) {
    throw makeBridgeError(BRIDGE_ERRORS.UNAVAILABLE, '本机没有 @system.interconnect，网桥不可用')
  }
  conn = api.instance()
  bindConn(conn)
  return conn
}

function bindConn(target) {
  target.onmessage = onMessage
  target.onopen = () => {
    closed = false
    console.log('[Bridge] 连接已建立')
  }
  target.onclose = (data) => {
    closed = true
    // 握手会话作废：重连后要重新协商（插件的协商状态是会话级的，别指望它还在）
    resetSession('连接已断开' + (data && data.code !== undefined ? ' code=' + data.code : ''))
  }
  target.onerror = (data) => {
    closed = true
    resetSession('连接出错' + (data && data.code !== undefined ? ' code=' + data.code : ''))
  }
}

/** 连接断了/要重来：失败掉所有在途请求与**正等着的握手**，并丢弃协商结果 */
export function resetSession(reason) {
  const message = reason || '网桥会话已重置'
  const err = makeBridgeError(BRIDGE_ERRORS.CLOSED, message)
  const entries = pending
  const ids = Object.keys(entries)
  pending = {}
  ids.forEach((id) => {
    const entry = entries[id]
    if (!entry) return
    if (entry.timer) clearTimeout(entry.timer)
    if (entry.reject) entry.reject(err)
  })
  peerCaps = null
  handshakePromise = null
  if (handshakeTimer) {
    clearTimeout(handshakeTimer)
    handshakeTimer = null
  }
  handshakeResolve = null
  // 握手途中断开也必须失败掉这个 Promise：request() 是先 await 握手再建请求超时定时器，
  // 握手挂住 = 请求永远不 settle（连超时都还没开始计），页面就那么卡着。
  const reject = handshakeReject
  handshakeReject = null
  if (reject) reject(err)
  console.warn('[Bridge]', message)
}

/* ------------------------------ 发送 ------------------------------ */

function sendRaw(payload) {
  let target
  try {
    target = ensureConn()
  } catch (e) {
    return Promise.reject(e)
  }
  // 单例连接只有一个 onmessage 槽：发之前重绑，保证"发起方持有槽位"（见文件头第 1 点）
  target.onmessage = onMessage

  return new Promise((resolve, reject) => {
    try {
      target.send({
        data: payload,
        success: () => resolve(),
        fail: (data, code) => {
          const detail = data && data.data ? data.data : ''
          reject(
            makeBridgeError(
              BRIDGE_ERRORS.SEND,
              '网桥发送失败 code=' + code + (detail ? ' ' + detail : '')
            )
          )
        },
      })
    } catch (e) {
      reject(makeBridgeError(BRIDGE_ERRORS.SEND, '网桥发送异常：' + (e && e.message ? e.message : e)))
    }
  })
}

/* ------------------------------ 握手 ------------------------------ */

/**
 * 握手 + caps 协商（PROTOCOL.md §3.1）
 *
 * 本端发 count=0（带 caps）；对端回 count=1（带它的 caps）；本端回 count=2 收尾。
 * 任一方向计数到 2 就是完成，不再回包。对端没带 caps ⇒ 会话退回 v1（单消息）。
 *
 * 超时是**最常见**的故障：手机没连、或 AstroBox 里没给本应用打开「监听」
 * （插件按「设备地址 + 快应用包名」注册接收器，包名对不上就永远收不到回音）。
 * 错误信息里直接写清楚该去点什么，别让人对着 code 猜。
 */
function ensureHandshake() {
  if (peerCaps) return Promise.resolve(peerCaps)
  if (handshakePromise) return handshakePromise

  const timeout = bridgeConfig().HANDSHAKE_TIMEOUT || 4000
  handshakePromise = new Promise((resolve, reject) => {
    handshakeResolve = resolve
    handshakeReject = reject
    handshakeTimer = setTimeout(() => {
      handshakeTimer = null
      handshakePromise = null
      handshakeResolve = null
      handshakeReject = null
      reject(
        makeBridgeError(
          BRIDGE_ERRORS.NO_HOST,
          '手机端网桥没有回应：确认设备已连接，并在 AstroBox 的「网桥 FetchBridge」里为本应用打开「监听」'
        )
      )
    }, timeout)

    sendRaw({
      tag: BRIDGE_TAGS.HANDSHAKE,
      count: 0,
      caps: buildLocalCaps(bridgeConfig()),
    }).catch((e) => {
      if (handshakeTimer) {
        clearTimeout(handshakeTimer)
        handshakeTimer = null
      }
      handshakePromise = null
      handshakeResolve = null
      handshakeReject = null
      reject(e)
    })
  })
  return handshakePromise
}

function onHandshake(msg) {
  if (msg.caps) {
    peerCaps = negotiateCaps(msg.caps, buildLocalCaps(bridgeConfig()))
    console.log(
      '[Bridge] 协商结果 version=' +
        peerCaps.version +
        ' chunked=' +
        peerCaps.chunked +
        ' chunkSize=' +
        peerCaps.chunkSize +
        ' ackWindow=' +
        peerCaps.ackWindow +
        ' encodings=' +
        peerCaps.encodings.join('/')
    )
  }

  const count = Number(msg.count)
  const safeCount = isFinite(count) ? count : 0

  if (safeCount >= 1) completeHandshake()

  if (safeCount < 2) {
    // 回 count+1 是本端的义务（对端 count<2 时必须应答）
    sendRaw({
      tag: BRIDGE_TAGS.HANDSHAKE,
      count: safeCount + 1,
      caps: buildLocalCaps(bridgeConfig()),
    }).catch((e) => console.warn('[Bridge] 握手应答失败：', e && e.message))
  }
}

function completeHandshake() {
  if (!peerCaps) {
    // 对端没声明 caps：按 v1 兼容路径继续（单消息、text/base64）
    peerCaps = negotiateCaps(null, buildLocalCaps(bridgeConfig()))
  }
  if (handshakeTimer) {
    clearTimeout(handshakeTimer)
    handshakeTimer = null
  }
  const resolve = handshakeResolve
  handshakeResolve = null
  handshakeReject = null
  if (resolve) resolve(peerCaps)
}

/* ------------------------------ 收帧 ------------------------------ */

function onMessage(evt) {
  const msg = parseBridgeMessage(evt && evt.data)
  if (!msg) return

  if (msg.tag === BRIDGE_TAGS.HANDSHAKE) {
    onHandshake(msg)
    return
  }
  if (msg.tag === BRIDGE_TAGS.FETCH) {
    onFetchFrame(msg)
    return
  }
  if (msg.tag === BRIDGE_TAGS.CHUNK) {
    onChunkFrame(msg)
    return
  }
  if (msg.tag === BRIDGE_TAGS.STREAM) {
    onStreamFrame(msg)
    return
  }
  if (msg.tag === BRIDGE_TAGS.STREAM_ERROR) {
    onStreamErrorFrame(msg)
    return
  }
  // 协议要求：未知 tag 只记日志、不得报错断开会话
  console.log('[Bridge] 忽略未处理的 tag：', msg.tag)
}

function onFetchFrame(msg) {
  const entry = pending[msg.id]
  if (!entry) return // 不是本 VM 的请求（同一条连接上还有别的 page VM）→ 忽略

  const resp = msg.resp || {}
  if (resp.ok === false) {
    finish(msg.id, makeBridgeError(BRIDGE_ERRORS.NETWORK, resp.statusText || '网桥请求失败'))
    return
  }

  if (resp.stream) {
    // v4 流响应头（PROTOCOL.md §6.1）：只发请求时带 stream:true 才会走到这。
    // 普通请求收到它说明「自动流式」被触发而客户端没声明流能力 —— 按协议错处理，
    // 绝不能把空 body 当正常响应交出去。
    if (!entry.isStream) {
      finish(
        msg.id,
        makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '收到未请求的 v4 流响应（检查请求帧的 stream 字段）')
      )
      return
    }
    try {
      entry.stream = new StreamAssembler({
        id: msg.id,
        bodyEncoding: resp.bodyEncoding || 'base64',
        chunkSize: resp.chunkSize,
        fixedChunks: resp.fixedChunks,
        ack: resp.ack,
        checksum: resp.checksum,
        contentLength: resp.contentLength,
        compression: resp.compression,
      })
      entry.status = resp.status
      entry.headers = resp.headers || {}
    } catch (e) {
      finish(msg.id, e)
      return
    }
    if (typeof entry.onHeader === 'function') {
      // 给上层送一次头部信息（Content-Length 可用于进度条；缺席时是 null）
      try {
        entry.onHeader({
          status: entry.status,
          headers: entry.headers,
          contentLength: resp.contentLength === undefined ? null : resp.contentLength,
          chunkSize: resp.chunkSize,
        })
      } catch (e) {
        console.warn('[Bridge] onHeader 回调出错：', e && e.message ? e.message : e)
      }
    }
    resetStreamTimer(msg.id)
    return
  }

  // 流式请求却收到了普通/分片响应：宿主丢过会话（重启、超时清理），协商已降级。
  // 绝不能把普通响应当「下载完成」交出去 —— 那会以 written=0 的空文件一路走到落盘。
  // 丢弃缓存的协商结果，下一次请求强制重新握手（真插件收到 fetch 也会补发握手）。
  if (entry.isStream) {
    peerCaps = null
    handshakePromise = null
    console.warn('[Bridge] 流式请求被降级为普通响应（宿主会话可能已重置），将重新协商')
    finish(
      msg.id,
      makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '网桥把流式请求降级成了普通响应（宿主会话可能已重置），请重试')
    )
    return
  }

  if (resp.chunked) {
    try {
      entry.assembler = new ChunkAssembler({
        id: msg.id,
        chunkCount: resp.chunkCount,
        totalBytes: resp.totalBytes,
        bodyEncoding: resp.bodyEncoding || 'base64',
        compression: resp.compression,
        raw: resp.raw,
        ack: resp.ack,
      })
      entry.status = resp.status
      entry.headers = resp.headers || {}
    } catch (e) {
      finish(msg.id, e)
    }
    return
  }

  let text
  try {
    text = decodeSingleBody(resp)
  } catch (e) {
    finish(msg.id, e)
    return
  }
  finish(msg.id, null, toBridgeEnvelope(resp, text))
}

function onChunkFrame(msg) {
  const entry = pending[msg.id]
  if (!entry || !entry.assembler) return

  let result
  try {
    result = entry.assembler.push(msg.seq, msg.data)
  } catch (e) {
    finish(msg.id, e)
    return
  }

  // 增量 ACK：**每收到一片就回一次**。攒着最后回一个会在 chunkCount > 窗口 时死锁
  // （发送方等 ACK 才继续发，快应用等收齐才回 ACK），见 PROTOCOL.md §5.2.1。
  if (entry.assembler.needsAck) {
    sendRaw({
      tag: BRIDGE_TAGS.ACK,
      id: msg.id,
      ack: entry.assembler.ackValue,
    }).catch((e) => console.warn('[Bridge] 回 ACK 失败：', e && e.message))
  }

  if (entry.assembler.isComplete) {
    let text
    try {
      text = entry.assembler.assemble()
    } catch (e) {
      finish(msg.id, e)
      return
    }
    finish(msg.id, null, {
      code: entry.status,
      data: text,
      headers: entry.headers || {},
    })
  }
}

function finish(id, err, result) {
  const entry = pending[id]
  if (!entry) return
  delete pending[id]
  if (entry.timer) clearTimeout(entry.timer)
  if (err) entry.reject(err)
  else entry.resolve(result)
}

/* ------------------------------ v4 流式请求 ------------------------------ */

/** 流帧空闲计时器：每收到一帧（或建连）就重置，超时判死并发取消帧 */
function resetStreamTimer(id) {
  const entry = pending[id]
  if (!entry || !entry.isStream) return
  if (entry.timer) clearTimeout(entry.timer)
  const idleTimeout = bridgeConfig().STREAM_IDLE_TIMEOUT || 20000
  entry.timer = setTimeout(() => {
    entry.timer = null
    sendStreamCancel(id, 'idle timeout')
    finish(id, makeBridgeError(BRIDGE_ERRORS.TIMEOUT, '流式传输空闲超时（' + idleTimeout + 'ms）：连续没有收到任何帧'))
  }, idleTimeout)
}

function sendStreamCancel(id, reason) {
  sendRaw({
    tag: BRIDGE_TAGS.STREAM_CANCEL,
    id,
    reason: String(reason || 'cancelled'),
  }).catch((e) => console.warn('[Bridge] 发送流取消帧失败：', e && e.message ? e.message : e))
}

function onStreamFrame(msg) {
  const entry = pending[msg.id]
  if (!entry || !entry.isStream || !entry.stream) return // 不是本 VM 的流 → 忽略

  let result
  try {
    result = entry.stream.push({
      seq: msg.seq,
      offset: msg.offset,
      data: msg.data,
      crc32: msg.crc32,
      final: msg.final,
      totalBytes: msg.totalBytes,
    })
  } catch (e) {
    // CRC 不过 / 协议错：按 §6.4 发取消帧让插件关掉 HTTP source，整笔失败
    sendStreamCancel(msg.id, e && e.message ? e.message : 'protocol error')
    finish(msg.id, e)
    return
  }

  // 连续消费出的帧交给调用方（写文件）；回调抛错同样整笔取消 ——
  // 磁盘写不进去了，继续收帧只会白耗蓝牙带宽
  if (result.delivered.length && typeof entry.onChunk === 'function') {
    try {
      for (let i = 0; i < result.delivered.length; i++) {
        entry.onChunk(result.delivered[i].bytes, result.delivered[i].offset)
      }
    } catch (e) {
      sendStreamCancel(msg.id, 'onChunk failed')
      finish(msg.id, e)
      return
    }
  }

  // 增量 ACK：每帧一报（含重复帧——回当前前沿，发送方才不会误判丢帧 go-back-N）
  sendRaw({
    tag: BRIDGE_TAGS.STREAM_ACK,
    id: msg.id,
    ack: result.ack,
  }).catch((e) => console.warn('[Bridge] 回流 ACK 失败：', e && e.message ? e.message : e))

  resetStreamTimer(msg.id)

  if (result.ended) {
    finish(msg.id, null, {
      status: entry.status,
      headers: entry.headers || {},
      totalBytes: result.totalBytes,
    })
  }
}

function onStreamErrorFrame(msg) {
  const entry = pending[msg.id]
  if (!entry) return
  finish(
    msg.id,
    makeBridgeError(BRIDGE_ERRORS.NETWORK, '网桥流式传输失败：' + (msg.message || 'unknown stream error'))
  )
}

/**
 * 发起一次 v4 流式下载（音频落盘专用，PROTOCOL.md §6）
 *
 * 与 request() 的区别：返回 { promise, cancel } 而不是裸 Promise ——
 * 流是长传输，调用方（audioCache）必须能在切歌/停止时**主动掐断**，
 * 插件收到取消帧会关掉 HTTP source，不再白耗蓝牙带宽。
 *
 * 字节不在这里落地：每帧经 onChunk 交给调用方，写盘失败时抛错即可整笔回滚
 * （本模块不依赖 @system.file，职责边界保持在「协议与会话」）。
 *
 * @param {object} options
 * @param {string} options.url
 * @param {object} [options.headers]
 * @param {boolean} [options.fixedChunks] 非尾帧固定 chunkSize（默认 true，便于按偏移写盘）
 * @param {(info:{status:number, headers:object, contentLength:number|null, chunkSize:number})=>void} [options.onHeader]
 * @param {(binary:string, offset:number)=>void} [options.onChunk] 二进制字符串（每字符一字节）+ 绝对字节偏移
 * @returns {{promise: Promise<{status:number, headers:object, totalBytes:number|null}>, cancel:(reason?:string)=>void}}
 */
export function requestStream(options) {
  const o = options || {}
  // 取消必须**先于注册也有效**：握手期间/请求帧还没发出去时就取消，
  // 不能等注册完再放行（否则会放出一笔没人认领的传输，白耗带宽还留残片）。
  const ctrl = {
    cancelled: false,
    reason: '',
    cancel(reason) {
      ctrl.cancelled = true
      ctrl.reason = String(reason || 'cancelled')
    },
  }

  const promise = (async () => {
    if (!isAvailable()) {
      throw makeBridgeError(BRIDGE_ERRORS.UNAVAILABLE, '本机没有 @system.interconnect，无法走网桥取流')
    }
    const caps = await ensureHandshake()
    if (ctrl.cancelled) {
      throw makeBridgeError(BRIDGE_ERRORS.CANCELLED, '流式传输已取消：' + ctrl.reason)
    }
    if (!caps || !caps.stream) {
      throw makeBridgeError(
        BRIDGE_ERRORS.UNSUPPORTED,
        '网桥未协商出 v4 流能力（需要 AstroBox「网桥 FetchBridge」v4 及以上插件）'
      )
    }
    if (closed) closed = false

    return new Promise((resolve, reject) => {
      const id = VM_TOKEN + '-' + ++idSeq
      const entry = {
        id,
        isStream: true,
        stream: null,
        onChunk: typeof o.onChunk === 'function' ? o.onChunk : null,
        onHeader: typeof o.onHeader === 'function' ? o.onHeader : null,
        resolve,
        reject,
        timer: null,
        status: 0,
        headers: {},
      }
      pending[id] = entry
      // 注册后取消 = 发取消帧 + 立即失败；取消帧对已结束的传输是迟到的，按协议静默忽略
      ctrl.cancel = (reason) => {
        ctrl.cancelled = true
        ctrl.reason = String(reason || 'cancelled')
        if (!pending[id]) return
        sendStreamCancel(id, ctrl.reason)
        finish(id, makeBridgeError(BRIDGE_ERRORS.CANCELLED, '流式传输已取消：' + ctrl.reason))
      }
      if (ctrl.cancelled) {
        // 取消发生在注册与发送之间的一瞬：直接失败，请求帧不再出门
        delete pending[id]
        reject(makeBridgeError(BRIDGE_ERRORS.CANCELLED, '流式传输已取消：' + ctrl.reason))
        return
      }
      resetStreamTimer(id)

      sendRaw(
        buildFetchRequest({
          id,
          url: o.url,
          method: o.method || 'GET',
          headers: o.headers,
          stream: true,
          fixedChunks: o.fixedChunks !== false,
        })
      ).catch((e) => finish(id, e))
    })
  })()

  return { promise, cancel: (reason) => ctrl.cancel(reason) }
}

/* ------------------------------ 对外的请求 ------------------------------ */

/**
 * 发起一次网桥请求
 *
 * @param {object} options
 * @param {string} options.url
 * @param {string} [options.method]
 * @param {object} [options.headers]
 * @param {string} [options.body]
 * @returns {Promise<{code:number, data:string, headers:object}>} 与 @system.fetch 同形态，
 *          交给 api.js 的 normalizeFetchResult 归一化
 */
export function request(options) {
  const o = options || {}
  if (!isAvailable()) {
    return Promise.reject(
      makeBridgeError(
        BRIDGE_ERRORS.UNAVAILABLE,
        '本机没有 @system.interconnect，无法走网桥联网'
      )
    )
  }
  if (closed) {
    // 连接断过：先让它重绑（重连由框架自动进行，onopen 会把 closed 清掉）
    closed = false
  }

  const timeout = o.timeout || bridgeConfig().REQUEST_TIMEOUT || 20000

  return ensureHandshake().then(
    () =>
      new Promise((resolve, reject) => {
        const id = VM_TOKEN + '-' + ++idSeq
        const entry = {
          id: id,
          resolve: resolve,
          reject: reject,
          timer: null,
          assembler: null,
          status: 0,
          headers: {},
        }
        entry.timer = setTimeout(() => {
          entry.timer = null
          finish(id, makeBridgeError(BRIDGE_ERRORS.TIMEOUT, '网桥请求超时（' + timeout + 'ms）：' + o.url))
        }, timeout)
        pending[id] = entry

        sendRaw(
          buildFetchRequest({
            id: id,
            url: o.url,
            method: o.method,
            headers: o.headers,
            body: o.body,
            followRedirects: o.followRedirects,
          })
        ).catch((e) => finish(id, e))
      })
  )
}

/** 运维/排查用：一眼看出网桥当前到哪一步了（日志里打这个，比逐条猜快） */
export function describeState() {
  return {
    available: isAvailable(),
    connected: !!conn,
    closed: closed,
    negotiated: peerCaps
      ? {
          version: peerCaps.version,
          chunked: peerCaps.chunked,
          chunkSize: peerCaps.chunkSize,
          ackWindow: peerCaps.ackWindow,
        }
      : null,
    inflight: Object.keys(pending).length,
    streams: Object.keys(pending).filter((id) => pending[id] && pending[id].isStream).length,
  }
}
