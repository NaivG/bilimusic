/**
 * FetchBridge（interconnect 网桥）协议纯逻辑
 *
 * 场景：Redmi Watch 4 / Xiaomi Watch H1 E 这类机型**有扬声器但没有 @system.fetch**
 * （官方支持明细里就没有这条），也没有独立网络。于是由手机/PC 端的 AstroBox
 * 「网桥 FetchBridge」插件代发 HTTP，两端用 @system.interconnect 交换 JSON。
 *
 * 本文件只放协议里最容易错、又完全不需要设备就能验证的那部分：
 * base64/hex/UTF-8 解码、caps 能力协商、分片乱序重组与累计 ACK
 * （不 import 任何 @system.*，Node 直接跑离线自检）。
 *
 * 协议：AstroBox-NG-Plugin-MiWear-InterconnectFetch/PROTOCOL.md（v4 插件，向下兼容 v1-v3）
 *
 * 本端只声明 `version: 4`（分片 + 累计 ACK + v4 开放长度流）：
 *   - v1 单消息有 MAX_UNCHUNKED_WIRE_LEN = 16384 字符的保护线，推荐流/收藏夹一页
 *     就可能压线，届时插件只能回一个错误响应（"response too large for unchunked
 *     interconnect frame"），表现出来像偶发故障；
 *   - v3 的分片 + 累计 ACK 正好解决它，且不需要压缩（本端只声明 compressions:['none']，
 *     绕开 JS 侧解压依赖）；
 *   - v4 的开放长度流给「音频落盘」（B 档）：普通 JSON 请求在请求帧里显式
 *     `stream:false`（见 buildFetchRequest），不受插件「Content-Length >= 64KiB
 *     自动流式」的影响；音频走 `stream:true + fixedChunks`，帧直接按 offset
 *     追加进 @system.file，整首歌不进 JS 堆。
 */

/** interconnect 通道上的消息 tag（一条 JSON = 一帧，tag 决定字段含义） */
export const BRIDGE_TAGS = {
  HANDSHAKE: '__hs__',
  FETCH: 'fetch',
  CHUNK: 'fetch-chunk',
  ACK: 'fetch-ack',
  // ---- v4 开放长度流（PROTOCOL.md §6）----
  STREAM: 'fetch-stream',
  STREAM_ACK: 'fetch-stream-ack',
  STREAM_CANCEL: 'fetch-stream-cancel',
  STREAM_ERROR: 'fetch-stream-error',
}

/* 协议默认值（PROTOCOL.md §3.4）：分片大小与 ACK 窗口都要夹到插件接受的范围里 */
export const DEFAULT_CHUNK_SIZE = 4096
export const MIN_CHUNK_SIZE = 256
export const MAX_CHUNK_SIZE = 65536
export const DEFAULT_ACK_WINDOW = 4
export const MIN_ACK_WINDOW = 1
export const MAX_ACK_WINDOW = 64

/** 网桥侧的错误码：调用方只认 code，人话在 message 里 */
export const BRIDGE_ERRORS = {
  UNAVAILABLE: 'E_BRIDGE_UNAVAILABLE',
  NO_HOST: 'E_BRIDGE_NO_HOST',
  CLOSED: 'E_BRIDGE_CLOSED',
  SEND: 'E_BRIDGE_SEND',
  TIMEOUT: 'E_BRIDGE_TIMEOUT',
  PROTOCOL: 'E_BRIDGE_PROTOCOL',
  NETWORK: 'E_BRIDGE_NETWORK',
  UNSUPPORTED: 'E_BRIDGE_UNSUPPORTED',
  CANCELLED: 'E_BRIDGE_CANCELLED',
}

/**
 * 造一个带 code 的错误。
 * playerService.describeError 认 `err.code`，所以到了 UI 上会显示成
 * `code=E_BRIDGE_NO_HOST 手机端网桥没有回应…`，排查时一眼能看出是哪一层。
 */
export function makeBridgeError(code, message) {
  const err = new Error(message)
  err.code = code
  return err
}

/* ------------------------------ 编解码 ------------------------------ */

const B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

const B64_LOOKUP = (() => {
  const table = {}
  for (let i = 0; i < B64_ALPHABET.length; i++) table[B64_ALPHABET.charAt(i)] = i
  // URL-safe 变体（RFC 4648 §5）：协议规定的是标准 base64，这里顺手容忍，不额外宣扬
  table['-'] = 62
  table['_'] = 63
  return table
})()

/**
 * base64 → 「二进制字符串」（每个字符一个字节）
 *
 * Vela 的 JS VM 不保证有 atob/TextDecoder，所以自己查表解。
 * 返回二进制字符串而不是数组，是为了跟 crypto.js 里 utf8Encode 的表示法一致：
 * 拼接、比对长度都便宜，最后整段过一次 utf8Decode。
 */
export function base64Decode(input) {
  const s = String(input === undefined || input === null ? '' : input)
  let out = ''
  let buffer = 0
  let bits = 0
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i)
    if (ch === '=') break // 填充之后不可能再有有效数据
    if (ch === '\n' || ch === '\r' || ch === ' ' || ch === '\t') continue
    const v = B64_LOOKUP[ch]
    if (v === undefined) {
      throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, 'base64 解码失败：非法字符 ' + JSON.stringify(ch))
    }
    buffer = (buffer << 6) | v
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out += String.fromCharCode((buffer >>> bits) & 0xff)
      // 只留还没用掉低位，避免 buffer 越移越大（32 位溢出后解出来全是错的）
      buffer = bits > 0 ? buffer & ((1 << bits) - 1) : 0
    }
  }
  return out
}

/** 小写十六进制 → 二进制字符串（协议里的 hex 编码，每字节两次查表） */
export function hexDecode(input) {
  const s = String(input === undefined || input === null ? '' : input)
  if (s.length % 2 !== 0) {
    throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, 'hex 解码失败：长度为奇数 ' + s.length)
  }
  let out = ''
  for (let i = 0; i < s.length; i += 2) {
    const byte = parseInt(s.substr(i, 2), 16)
    if (isNaN(byte)) {
      throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, 'hex 解码失败：' + s.substr(i, 2))
    }
    out += String.fromCharCode(byte)
  }
  return out
}

/**
 * UTF-8 字节（二进制字符串）→ JS 字符串
 *
 * 非法/截断序列替换成 U+FFFD 而不是抛错：协议层已经用 totalBytes 校验过长度，
 * 这里再因为一个坏字符把整笔请求打死不划算（弱网下更该降级成"某个字乱码"）。
 */
export function utf8Decode(binary) {
  const s = String(binary === undefined || binary === null ? '' : binary)
  let out = ''
  let i = 0
  while (i < s.length) {
    const b0 = s.charCodeAt(i++)
    if (b0 < 0x80) {
      out += String.fromCharCode(b0)
      continue
    }
    let extra = 0
    let cp = 0
    if ((b0 & 0xe0) === 0xc0) {
      extra = 1
      cp = b0 & 0x1f
    } else if ((b0 & 0xf0) === 0xe0) {
      extra = 2
      cp = b0 & 0x0f
    } else if ((b0 & 0xf8) === 0xf0) {
      extra = 3
      cp = b0 & 0x07
    } else {
      out += '\uFFFD'
      continue
    }
    if (i + extra > s.length) {
      out += '\uFFFD'
      break
    }
    let valid = true
    for (let k = 0; k < extra; k++) {
      const b = s.charCodeAt(i + k)
      if ((b & 0xc0) !== 0x80) {
        valid = false
        break
      }
      cp = (cp << 6) | (b & 0x3f)
    }
    if (!valid) {
      // 不推进 i：作为续字节的那个字符交给下一轮自己判（保证每轮都有进展）
      out += '\uFFFD'
      continue
    }
    i += extra
    if (cp > 0xffff) {
      cp -= 0x10000
      out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff))
    } else {
      out += String.fromCharCode(cp)
    }
  }
  return out
}

/**
 * IEEE CRC-32（zlib 同款：poly 0xEDB88320，初值/终值异或 0xFFFFFFFF）。
 *
 * 输入是本项目通用的「二进制字符串」（每字符一字节），返回小写 8 位十六进制。
 * v4 流逐帧校验（PROTOCOL.md §6.2）：校验失败的帧不推进 ACK、不落盘，
 * 而是整笔取消 —— 落盘文件差一个字节就是坏音频，宁可重来。
 */
const CRC_TABLE = (() => {
  const table = new Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    }
    table[n] = c >>> 0
  }
  return table
})()

export function crc32(binary) {
  const s = String(binary === undefined || binary === null ? '' : binary)
  let crc = -1
  for (let i = 0; i < s.length; i++) {
    crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ s.charCodeAt(i)) & 0xff]
  }
  return ((crc ^ -1) >>> 0).toString(16).padStart(8, '0')
}

/**
 * 二进制字符串 → Uint8Array：给 @system.file.writeArrayBuffer 用（官方要 Uint8Array）。
 * 只在流式落盘的路径上调用，每帧一次、每次 chunkSize 字节，堆占用可控。
 */
export function binaryToUint8(binary) {
  const s = String(binary === undefined || binary === null ? '' : binary)
  const out = new Uint8Array(s.length)
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff
  return out
}

/** 按声明的编码把一段 wire 字符串解成二进制字符串；'text' 表示已经是文本，不该走到这 */
function decodeBinary(encoded, encoding) {
  if (encoding === 'base64') return base64Decode(encoded)
  if (encoding === 'hex') return hexDecode(encoded)
  throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '未知的 bodyEncoding: ' + encoding)
}

/**
 * 压缩算法门禁：本端只声明 compressions:['none']，插件必须按交集选。
 * 真收到别的算法说明协商被无视了 —— 明确报错，绝不"当没压缩"接着解（解出来是乱码，
 * 而且会以 JSON.parse 失败的形式出现在很远的地方）。
 */
function assertNoCompression(compression) {
  if (compression && compression !== 'none') {
    throw makeBridgeError(
      BRIDGE_ERRORS.PROTOCOL,
      '对端用了未协商的压缩算法 ' + compression + '（本端只声明 none）'
    )
  }
}

/**
 * 单消息响应体的解码（PROTOCOL.md §5.1）
 *
 * bodyEncoding 缺省按 v1 规则推断：raw=false ⇒ text，raw=true ⇒ base64。
 * 本端一律请求 raw:false（只要文本），真拿到二进制就明确报不支持。
 */
export function decodeSingleBody(resp) {
  const r = resp || {}
  assertNoCompression(r.compression)
  const raw = !!r.raw
  const encoding = r.bodyEncoding || (raw ? 'base64' : 'text')
  const body = r.body === undefined || r.body === null ? '' : String(r.body)
  if (encoding === 'text') return body
  const binary = decodeBinary(body, encoding)
  if (raw) {
    throw makeBridgeError(BRIDGE_ERRORS.UNSUPPORTED, '网桥只支持文本响应（本端一律 raw:false）')
  }
  return utf8Decode(binary)
}

/* ------------------------------ 能力协商 ------------------------------ */

/**
 * 本端 caps（PROTOCOL.md §3.3）。字段名与协议一致，不能改名。
 * ackWindow 是"在途分片数"：手表内存紧张，默认 4 片 × 4 KB ≈ 16 KB 在途。
 * stream 只在 PROTOCOL_VERSION >= 4 且未显式关闭时声明 —— 它是 v4 流的唯一开关，
 * 声明后普通请求也要靠请求帧里的 stream:false 才能避开「大响应自动流式」。
 */
export function buildLocalCaps(bridgeConfig) {
  const cfg = bridgeConfig || {}
  const version = toInt(cfg.PROTOCOL_VERSION, 4)
  return {
    version,
    chunk: true,
    maxChunkSize: toInt(cfg.CHUNK_SIZE, DEFAULT_CHUNK_SIZE),
    encodings: (cfg.ENCODINGS || ['text', 'base64']).slice(),
    compressions: (cfg.COMPRESSIONS || ['none']).slice(),
    ack: true,
    ackWindow: toInt(cfg.ACK_WINDOW, DEFAULT_ACK_WINDOW),
    stream: version >= 4 && cfg.STREAM !== false,
  }
}

/**
 * 协商结果（PROTOCOL.md §3.4，逐条对着实现）
 *
 * `peer === null`（对端没带 caps：老宿主，或示范应用 interconn-fetch 那种 v1 客户端）
 * ⇒ 整个会话退回 v1：单消息、text/base64、不压缩、不分片、不 ACK。
 * 这条兼容路径必须留着 —— 它是"首响应到达前协商还没完成"时的兜底。
 */
export function negotiateCaps(peerCaps, localCaps) {
  const local = localCaps || buildLocalCaps()
  const peer = peerCaps && typeof peerCaps === 'object' ? peerCaps : null

  if (!peer) {
    return {
      version: 1,
      legacy: true,
      chunked: false,
      chunkSize: 0,
      encodings: [],
      compressions: [],
      ack: false,
      ackWindow: 0,
      stream: false,
    }
  }

  const version = Math.max(1, Math.min(toInt(peer.version, 1), toInt(local.version, 1)))
  const chunked = !!local.chunk && !!peer.chunk && version >= 2
  const chunkSize = chunked
    ? clampInt(toInt(peer.maxChunkSize, DEFAULT_CHUNK_SIZE), MIN_CHUNK_SIZE, MAX_CHUNK_SIZE)
    : 0
  const ackWindow =
    version >= 3 && chunked && !!local.ack && !!peer.ack
      ? clampInt(toInt(peer.ackWindow, DEFAULT_ACK_WINDOW), MIN_ACK_WINDOW, MAX_ACK_WINDOW)
      : 0
  // v4 流的硬门控（PROTOCOL.md §6.5）：version>=4 + 双端声明 stream + 分片 + ACK 全齐。
  // 缺任何一条都不能出现 fetch-stream 帧 —— 插件按同样规则协商，两端一致才开流。
  const stream = version >= 4 && !!local.stream && !!peer.stream && chunked && ackWindow > 0

  return {
    version,
    legacy: false,
    chunked,
    chunkSize,
    // 交集**保留对端顺序**：对端最想要的编码排在最前，发送方按这个顺序挑
    encodings: intersectOrdered(peer.encodings, local.encodings),
    compressions: intersectOrdered(peer.compressions, local.compressions),
    ack: ackWindow > 0,
    ackWindow,
    stream,
  }
}

function intersectOrdered(peerList, localList) {
  if (!isArray(peerList)) return []
  const local = isArray(localList) ? localList : []
  const out = []
  const seen = {}
  for (let i = 0; i < peerList.length; i++) {
    const item = peerList[i]
    if (typeof item !== 'string') continue
    if (local.indexOf(item) < 0 || seen[item]) continue
    seen[item] = true
    out.push(item)
  }
  return out
}

/* ------------------------------ 分片重组 ------------------------------ */

/**
 * 分片响应重组器（PROTOCOL.md §5.2 / §5.2.1）
 *
 * 两个要点：
 *   1. **乱序缓存**：按 seq 落位，重复分片忽略（也不重复计 ACK）；
 *   2. **累计 ACK** = "从 0 起最长的无空洞区间长度"（已收 {0,1,3,4} ⇒ ack=2）。
 *      手表必须**增量**回 ACK（每片一次），否则 chunkCount > 窗口 时发送方会在
 *      第 W 片后停住等 ACK，而快应用在等收齐 —— 双向死等（v2 的分片死锁）。
 *
 * 另外：**多字节 UTF-8 字符可能跨分片**，所以每片只解到二进制字符串，
 * 必须等 assemble() 拼完整段再 utf8Decode（per-chunk 解码会把中文切成两半）。
 */
export class ChunkAssembler {
  constructor(meta) {
    const m = meta || {}
    this.id = m.id
    this.chunkCount = toInt(m.chunkCount, 0)
    this.totalBytes = toInt(m.totalBytes, 0)
    this.encoding = m.bodyEncoding || 'base64'
    this.raw = !!m.raw
    /** 本笔响应是否启用 ACK 流控（头部 resp.ack 为 true 才回 fetch-ack） */
    this.needsAck = !!m.ack
    assertNoCompression(m.compression)
    this._parts = []
    this._bytes = 0
    this._received = 0
    this._frontier = 0
  }

  /** @returns {{accepted:boolean, reason?:string, ack:number}} */
  push(seq, data) {
    const idx = toInt(seq, -1)
    if (idx < 0) {
      throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '分片序号非法: ' + seq)
    }
    if (this.chunkCount > 0 && idx >= this.chunkCount) {
      throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '分片序号越界: ' + idx + '/' + this.chunkCount)
    }
    if (this._parts[idx] !== undefined) {
      return { accepted: false, reason: 'duplicate', ack: this._frontier }
    }
    const binary = decodeBinary(data === undefined || data === null ? '' : String(data), this.encoding)
    this._parts[idx] = binary
    this._bytes += binary.length
    this._received++
    while (this._parts[this._frontier] !== undefined) this._frontier++
    return { accepted: true, ack: this._frontier }
  }

  /** 下一个仍缺失的连续分片序号 = 累计 ACK 值（收齐时等于 chunkCount） */
  get ackValue() {
    return this._frontier
  }

  get receivedCount() {
    return this._received
  }

  get isComplete() {
    return this.chunkCount > 0 && this._frontier >= this.chunkCount
  }

  /** 拼出最终文本；长度与 totalBytes 对不上时明确报错（别把半截 JSON 交给调用方） */
  assemble() {
    if (!this.isComplete) {
      throw makeBridgeError(
        BRIDGE_ERRORS.PROTOCOL,
        '分片未收齐：' + this._frontier + '/' + this.chunkCount
      )
    }
    if (this.totalBytes > 0 && this._bytes !== this.totalBytes) {
      throw makeBridgeError(
        BRIDGE_ERRORS.PROTOCOL,
        '分片总长不符：期望 ' + this.totalBytes + '，实际 ' + this._bytes
      )
    }
    if (this.raw) {
      throw makeBridgeError(BRIDGE_ERRORS.UNSUPPORTED, '网桥只支持文本响应（本端一律 raw:false）')
    }
    return utf8Decode(this._parts.slice(0, this.chunkCount).join(''))
  }
}

/* ------------------------------ v4 流式重组 ------------------------------ */

/**
 * v4 开放长度流的接收状态机（PROTOCOL.md §6）
 *
 * 与 ChunkAssembler（v3 有限分片）的三点不同：
 *   1. **开放长度**：帧数未知，以 `final:true` 的结束帧收尾（它也占一个 seq、也受
 *      ACK/重传保护）；Content-Length 仅仅是提示，可能整个缺席（直播/chunked HTTP）。
 *   2. **逐帧校验 + 立即消费**：CRC 过了且序号连续就立刻把字节交给调用方
 *      （onChunk → @system.file 按偏移追加），**绝不整首歌攒在 JS 堆里** ——
 *      手表内存按 KB 计，一首 3 MB 的歌攒进来就是 OOM。
 *   3. **offset 是绝对字节偏移**：fixedChunks 模式下非尾帧满足 offset === seq*chunkSize，
 *      但这里不依赖该等式 —— 连续消费时的运行偏移与帧声明的 offset 对不上就报协议错，
 *      两道保险互相兜底。
 *
 * push() 每次返回累计 ACK（下一个仍缺失的连续帧序号）与本次连续消费出的帧，
 * 调用方（interconnBridge）负责真正发 ACK、调 onChunk。
 */
export class StreamAssembler {
  constructor(meta) {
    const m = meta || {}
    this.id = m.id
    this.encoding = m.bodyEncoding || 'base64'
    this.chunkSize = toInt(m.chunkSize, 0)
    this.fixedChunks = !!m.fixedChunks
    this.contentLength = m.contentLength === undefined ? null : toInt(m.contentLength, 0)
    // v4 不允许无 ACK 流式发送（PROTOCOL.md §6.3）：头部 resp.ack 不是 true 就是协议错
    if (m.ack !== true) {
      throw makeBridgeError(
        BRIDGE_ERRORS.PROTOCOL,
        'v4 流响应头部缺少 ack:true（协议要求流必须带 ACK 流控）'
      )
    }
    this.needsAck = true
    /** 头部声明 checksum:'crc32' 时逐帧强制校验；帧里自带 crc32 的也校验 */
    this.checksum = m.checksum || ''
    assertNoCompression(m.compression)
    this._pending = {} // seq -> {bytes, offset, final, totalBytes}（窗口内的乱序帧）
    this._nextSeq = 0 // 下一个待消费的连续序号 = 累计 ACK 值
    this._consumed = 0 // 已连续消费的字节数（也是下一帧的期望 offset）
    this._received = 0
    this._ended = false
    this._totalBytes = null // 结束帧声明的全量字节数
  }

  /**
   * 收一帧（数据帧或结束帧）
   * @param {object} frame {seq, offset, data, crc32, final, totalBytes}
   * @returns {{accepted:boolean, ack:number, delivered:Array<{bytes:string, offset:number}>, ended:boolean, totalBytes:number|null}}
   */
  push(frame) {
    const f = frame || {}
    const seq = toInt(f.seq, -1)
    if (seq < 0) {
      throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '流帧序号非法: ' + f.seq)
    }
    if (this._ended && seq >= this._nextSeq) {
      // 结束帧之后还来数据帧：除了重传（<= 已消费前沿）都算协议错
      throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '结束帧之后又收到新帧 seq=' + seq)
    }
    if (seq < this._nextSeq || this._pending[seq] !== undefined) {
      // 重复帧（go-back-N 重传，可能已消费也可能还在乱序缓存里）：忽略，
      // 但仍回当前 ACK 让发送方知道我们的连续前沿，别让它停在原地重传
      return { accepted: false, ack: this._nextSeq, delivered: [], ended: this._ended, totalBytes: this._totalBytes }
    }

    const bytes = decodeBinary(f.data === undefined || f.data === null ? '' : String(f.data), this.encoding)
    const expectCrc = this.checksum === 'crc32' || f.crc32 !== undefined
    if (expectCrc && crc32(bytes) !== String(f.crc32 || '').toLowerCase()) {
      throw makeBridgeError(
        BRIDGE_ERRORS.PROTOCOL,
        '流帧 CRC 校验失败 seq=' + seq + '（声明 ' + f.crc32 + '，实际 ' + crc32(bytes) + '）'
      )
    }

    if (f.final === true) {
      // 结束帧：占一个 seq，data 为空。totalBytes 是全部非结束帧的字节数
      this._pending[seq] = { bytes: '', offset: null, final: true, totalBytes: toInt(f.totalBytes, 0) }
      this._received++
    } else {
      // 内存护栏：乱序只允许发生在窗口内。堆积超过 64 帧说明对端没按窗口发，直接判协议错
      if (Object.keys(this._pending).length >= 64) {
        throw makeBridgeError(BRIDGE_ERRORS.PROTOCOL, '流帧堆积超出窗口上限（疑似对端未按 ACK 窗口发送）')
      }
      this._pending[seq] = {
        bytes,
        offset: typeof f.offset === 'number' && isFinite(f.offset) ? f.offset : null,
        final: false,
        totalBytes: null,
      }
      this._received++
    }

    const delivered = []
    // 连续消费：从 _nextSeq 起，能走多远走多远
    while (this._pending[this._nextSeq] !== undefined) {
      const unit = this._pending[this._nextSeq]
      delete this._pending[this._nextSeq]
      this._nextSeq++
      if (unit.final) {
        this._ended = true
        this._totalBytes = unit.totalBytes
        break
      }
      // offset 双保险：帧声明的偏移必须等于运行偏移（漏帧/错序在这里现形）
      if (unit.offset !== null && unit.offset !== this._consumed) {
        throw makeBridgeError(
          BRIDGE_ERRORS.PROTOCOL,
          '流帧偏移不连续：期望 ' + this._consumed + '，帧声明 ' + unit.offset + '（seq=' + (this._nextSeq - 1) + '）'
        )
      }
      delivered.push({ bytes: unit.bytes, offset: this._consumed })
      this._consumed += unit.bytes.length
    }

    if (this._ended) {
      if (this._totalBytes > 0 && this._consumed !== this._totalBytes) {
        throw makeBridgeError(
          BRIDGE_ERRORS.PROTOCOL,
          '流总长不符：期望 ' + this._totalBytes + '，实际 ' + this._consumed
        )
      }
      if (this.contentLength > 0 && this._totalBytes > 0 && this._totalBytes !== this.contentLength) {
        throw makeBridgeError(
          BRIDGE_ERRORS.PROTOCOL,
          '与 Content-Length 不符：声明 ' + this.contentLength + '，实际 ' + this._totalBytes
        )
      }
    }

    return { accepted: true, ack: this._nextSeq, delivered, ended: this._ended, totalBytes: this._totalBytes }
  }

  /** 累计 ACK 值 = 下一个仍缺失的连续帧序号 */
  get ackValue() {
    return this._nextSeq
  }

  get receivedCount() {
    return this._received
  }

  get consumedBytes() {
    return this._consumed
  }

  get isEnded() {
    return this._ended
  }

  get totalBytes() {
    return this._totalBytes
  }
}

/* ------------------------------ 收发辅助 ------------------------------ */

/**
 * 组装 fetch 请求帧（PROTOCOL.md §4）
 * options.headers 的值必须是字符串（非字符串插件会 toString 化，别指望它懂对象）。
 */
export function buildFetchRequest(options) {
  const o = options || {}
  const frame = {
    tag: BRIDGE_TAGS.FETCH,
    id: o.id,
    url: o.url,
    options: {
      method: String(o.method || 'GET').toUpperCase(),
      headers: o.headers || {},
    },
  }
  if (o.body !== undefined && o.body !== null) {
    frame.options.body = typeof o.body === 'string' ? o.body : JSON.stringify(o.body)
  }
  // 原生 fetch 会自己跟随 3xx；网桥默认不跟随（options.followRedirects 缺省 false），
  // 不显式打开的话 passport 之类的 302 会被原样当响应体丢回来（看着像 JSON 解析失败）。
  if (o.followRedirects !== false) frame.options.followRedirects = true
  // v4 语义（PROTOCOL.md §4）：已协商 v4 的会话里，插件对 audio/*、video/* 或
  // Content-Length >= 64KiB 的响应会「自动流式」。普通 JSON 请求必须**显式**
  // stream:false 才能锁回有限响应路径，否则一个大 JSON 会以 fetch-stream 帧到达，
  // 而调用方还在按单消息/分片等 —— 永远等不齐。只有显式要流（音频落盘）才置 true。
  frame.options.stream = o.stream === true
  if (o.stream === true && o.fixedChunks) frame.options.fixedChunks = true
  return frame
}

/** 收到的一帧 → 对象；非 JSON/空串按"不认识"处理（协议要求未知 tag 忽略而非报错） */
export function parseBridgeMessage(raw) {
  if (typeof raw !== 'string' || !raw) return null
  try {
    const msg = JSON.parse(raw)
    return msg && typeof msg === 'object' ? msg : null
  } catch (e) {
    return null
  }
}

/**
 * 响应帧 → `{ code, data, headers }`
 *
 * 刻意对齐 @system.fetch 的返回形态：这样 api.js 两条链路共用
 * common/parse.js 的 normalizeFetchResult，上层（biliApi/页面）感知不到走的哪条。
 */
export function toBridgeEnvelope(resp, text) {
  const r = resp || {}
  return {
    code: toInt(r.status, 0),
    data: text,
    headers: r.headers || {},
  }
}

/* ------------------------------ 小工具 ------------------------------ */

function toInt(value, fallback) {
  const n = Number(value)
  return isFinite(n) ? Math.floor(n) : fallback
}

function clampInt(value, min, max) {
  if (value < min) return min
  if (value > max) return max
  return value
}

function isArray(v) {
  return Object.prototype.toString.call(v) === '[object Array]'
}
