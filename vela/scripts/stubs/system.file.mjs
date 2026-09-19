/**
 * @system.file 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 按 Vela 官方文档（iot.mi.com/vela/quickapp/zh/features/data/file.html）的
 * 回调形态实现内存版文件系统，只覆盖本项目用到的接口：
 *   writeArrayBuffer（Uint8Array + append）/ readArrayBuffer / readText / list（fileList 带
 *   uri/length/lastModifiedTime）/ get / access / mkdir / rmdir / move / copy / delete。
 *
 * 语义要点（与真机对齐的部分）：
 *   - writeArrayBuffer 的 append:true 追加到文件末尾（position 无效）——
 *     B 档音频落盘靠它分块写，桩严格按这个语义实现；
 *   - list 返回的是**完整 uri**（官方：「该 uri 可以被其他组件或 Feature 访问」），
 *     audioCache 的 baseName() 只取末段，两种返回形态都兼容；
 *   - move/copy/delete/access 对不存在的文件回 fail（code 301/300）；
 *   - **tmp 分区**（`internal://tmp/…`）：官方「文件存储」章写明 Temp 是「只读，
 *     只能通过特定 API 获取」，而参数表里 `file.copy` **只禁止 dstUri 是 tmp**
 *     （`srcUri` 不限）—— 所以桩里 readArrayBuffer 读 tmp 默认回 **202 参数错误**
 *     （真机现场：`responseType:'file'` 给的 uri 直接读就是这个码），
 *     而 copy 允许以 tmp 为源。这正是 audioCache 里「拷出 tmp 再读」那条读法的由来，
 *     可用 __setTmpReadAllowed() / __setCopyFromTmpDenied() 切换成别的机型。
 *     其余接口的分区校验（write/move/delete/get 不许 tmp）暂不建模：本项目不那样用，
 *     建模了也只是自欺（桩的职责是照抄**真机给的形态**，不是照抄文档的所有限制）。
 */

const files = new Map() // uri -> { data: Uint8Array, mtime: number }

/** 调用记录（断言「读了几次 tmp」「拷了几次」「攒批后写了几次盘」用） */
const reads = [] // {uri, position, length, ok}
const copies = [] // {srcUri, dstUri}
const writes = [] // {uri, length, append, ok}

/** tmp 分区（internal://tmp/…）：真机上只有特定 API 能读，默认照真机「读不了」 */
let tmpReadAllowed = false
/** 是否禁止从 tmp 拷出（默认按文档：copy 的 srcUri 允许 tmp） */
let copyFromTmpDenied = false
/**
 * tmp 分区的 `readText` 行为。官方「文件存储」章把 Temp 写成「只读，**只能通过特定
 * API 获取（如 file.readText）**」—— 也就是真机上可能"读不了 readArrayBuffer / copy，
 * 却能 readText"。至于 readText 给回来的字符串与原始字节是什么关系，真机未验证，
 * 所以桩要能扮演全部三种可能：
 *   'denied'（默认）—— 连 readText 也拒绝 tmp（202）：tmp 对文件接口完全封闭
 *   'byte'          —— **一字节一字符**（嵌入式 JS 常见做法），字节可无损取回
 *   'base64'        —— 传 `encoding:'base64'` 时回 base64 文本（无损，需解码）
 *   'utf8'          —— 真按 UTF-8 解码：二进制会变成替换字符，**必须被我们拒掉**
 */
let tmpReadTextMode = 'denied'
const textReads = [] // {uri, encoding, mode, ok}

function isTmpUri(uri) {
  return String(uri || '').indexOf('internal://tmp/') === 0
}

/** 一字节一字符（charCode 即字节值） */
function bytesToBinaryString(data) {
  let out = ''
  for (let i = 0; i < data.length; i++) out += String.fromCharCode(data[i])
  return out
}

const later = (fn) => setTimeout(fn, 0)

function asBytes(buffer) {
  if (buffer instanceof Uint8Array) return buffer
  if (buffer instanceof ArrayBuffer) return new Uint8Array(buffer)
  if (buffer && buffer.buffer instanceof ArrayBuffer) {
    return new Uint8Array(buffer.buffer, buffer.byteOffset || 0, buffer.byteLength || buffer.buffer.byteLength)
  }
  return new Uint8Array(0)
}

function failCall(fail, code, data) {
  if (typeof fail === 'function') later(() => fail(data === undefined ? '' : data, code))
}

function okCall(success, data) {
  if (typeof success === 'function') later(() => success(data))
}

const file = {
  /** 写 Uint8Array：append 追加；否则按 position 覆盖写（文件不存在则创建） */
  writeArrayBuffer(options) {
    const { uri, buffer, append, position, success, fail } = options || {}
    if (!uri || typeof uri !== 'string') {
      writes.push({ uri, length: 0, append: !!append, ok: false })
      failCall(fail, 202, 'uri required')
      return
    }
    if (!(buffer instanceof Uint8Array) && !(buffer instanceof ArrayBuffer)) {
      writes.push({ uri, length: 0, append: !!append, ok: false })
      failCall(fail, 202, 'buffer must be Uint8Array')
      return
    }
    writes.push({ uri, length: asBytes(buffer).length, append: !!append, ok: true })
    later(() => {
      const data = asBytes(buffer)
      const prev = files.get(uri)
      let next
      if (append) {
        const base = prev ? prev.data : new Uint8Array(0)
        next = new Uint8Array(base.length + data.length)
        next.set(base, 0)
        next.set(data, base.length)
      } else {
        const pos = Math.max(0, Number(position) || 0)
        const prevLen = prev ? prev.data.length : 0
        const size = Math.max(pos + data.length, prevLen)
        next = new Uint8Array(size)
        if (prev) next.set(prev.data.subarray(0, Math.min(prevLen, size)), 0)
        next.set(data, pos)
      }
      files.set(uri, { data: next, mtime: Date.now() })
      okCall(success)
    })
  },

  /** 读 Buffer：position/length 缺省读整个文件；tmp 分区默认回 202；缺文件 fail 301 */
  readArrayBuffer(options) {
    const { uri, position, length, success, fail } = options || {}
    const hit = uri && files.get(uri)
    if (isTmpUri(uri) && !tmpReadAllowed) {
      // 真机现场：拿 responseType:'file' 给的 tmp uri 直接读 → code=202 invalid arguments
      reads.push({ uri, position, length, ok: false })
      failCall(fail, 202, 'invalid arguments')
      return
    }
    if (!hit) {
      reads.push({ uri, position, length, ok: false })
      failCall(fail, 301, 'file not found')
      return
    }
    reads.push({ uri, position, length, ok: true })
    const pos = Math.max(0, Number(position) || 0)
    const end = length === undefined || length === null ? hit.data.length : Math.min(hit.data.length, pos + Number(length))
    const out = hit.data.slice(pos, end)
    okCall(success, { buffer: out })
  },

  /**
   * 读文本。官方 success 形态是 `{text}`。
   * tmp 分区按 tmpReadTextMode 走（见上面的说明）——这是官方唯一点了名的 tmp 读法。
   */
  readText(options) {
    const { uri, encoding, success, fail } = options || {}
    const hit = uri && files.get(uri)
    if (isTmpUri(uri)) {
      if (tmpReadTextMode === 'denied') {
        textReads.push({ uri, encoding, mode: tmpReadTextMode, ok: false })
        failCall(fail, 202, 'invalid arguments')
        return
      }
      if (!hit) {
        textReads.push({ uri, encoding, mode: tmpReadTextMode, ok: false })
        failCall(fail, 301, 'file not found')
        return
      }
      textReads.push({ uri, encoding, mode: tmpReadTextMode, ok: true })
      const data = hit.data
      if (tmpReadTextMode === 'base64') {
        // 只有显式要 base64 才给 base64（其余按默认编码解码 —— 二进制必然被解坏）
        const text =
          encoding === 'base64'
            ? Buffer.from(data).toString('base64')
            : new TextDecoder('utf-8').decode(data)
        okCall(success, { text })
        return
      }
      okCall(success, { text: tmpReadTextMode === 'byte' ? bytesToBinaryString(data) : new TextDecoder('utf-8').decode(data) })
      return
    }
    if (!hit) {
      textReads.push({ uri, encoding, mode: 'normal', ok: false })
      failCall(fail, 301, 'file not found')
      return
    }
    textReads.push({ uri, encoding, mode: 'normal', ok: true })
    okCall(success, { text: new TextDecoder(encoding === 'base64' ? 'utf-8' : encoding || 'utf-8').decode(hit.data) })
  },

  /** 目录列表：fileList: [{uri, length, lastModifiedTime}]（uri 为完整 uri） */
  list(options) {
    const { uri, success, fail } = options || {}
    if (!uri || typeof uri !== 'string') {
      failCall(fail, 202, 'uri required')
      return
    }
    later(() => {
      const fileList = []
      files.forEach((value, key) => {
        if (key.indexOf(uri) === 0 && key !== uri) {
          fileList.push({ uri: key, length: value.data.length, lastModifiedTime: value.mtime })
        }
      })
      okCall(success, { fileList })
    })
  },

  /** 文件信息；缺文件 fail 301 */
  get(options) {
    const { uri, success, fail } = options || {}
    const hit = uri && files.get(uri)
    if (!hit) {
      failCall(fail, 301, 'file not found')
      return
    }
    okCall(success, { uri, length: hit.data.length, lastModifiedTime: hit.mtime, type: 'file' })
  },

  /** 判断存在：存在 success、不存在 fail（code 301） */
  access(options) {
    const { uri, success, fail } = options || {}
    if (uri && files.has(uri)) okCall(success)
    else failCall(fail, 301, 'not found')
  },

  /** 建目录：内存桩没有真实目录树，仅当 uri 合法即成功 */
  mkdir(options) {
    const { uri, success, fail } = options || {}
    if (!uri || typeof uri !== 'string') failCall(fail, 202, 'uri required')
    else okCall(success)
  },

  /** 删目录：连带删掉该前缀下所有文件 */
  rmdir(options) {
    const { uri, success, fail } = options || {}
    if (!uri || typeof uri !== 'string') {
      failCall(fail, 202, 'uri required')
      return
    }
    later(() => {
      const doomed = []
      files.forEach((_, key) => {
        if (key.indexOf(uri) === 0) doomed.push(key)
      })
      doomed.forEach((key) => files.delete(key))
      okCall(success)
    })
  },

  /** 移动（改名）：src 必须存在（fail 301）；dst 覆盖 */
  move(options) {
    const { srcUri, dstUri, success, fail } = options || {}
    const hit = srcUri && files.get(srcUri)
    if (!srcUri || !dstUri) {
      failCall(fail, 202, 'uri required')
      return
    }
    if (!hit) {
      failCall(fail, 301, 'src not found')
      return
    }
    later(() => {
      files.delete(srcUri)
      files.set(dstUri, { data: hit.data, mtime: Date.now() })
      okCall(success, dstUri)
    })
  },

  copy(options) {
    const { srcUri, dstUri, success, fail } = options || {}
    const hit = srcUri && files.get(srcUri)
    if (!srcUri || !dstUri) {
      failCall(fail, 202, 'uri required')
      return
    }
    if (isTmpUri(srcUri) && copyFromTmpDenied) {
      failCall(fail, 202, 'invalid arguments')
      return
    }
    if (!hit) {
      failCall(fail, 301, 'src not found')
      return
    }
    copies.push({ srcUri, dstUri })
    later(() => {
      files.set(dstUri, { data: hit.data.slice(), mtime: Date.now() })
      okCall(success, dstUri)
    })
  },

  delete(options) {
    const { uri, success, fail } = options || {}
    if (!uri || !files.has(uri)) {
      failCall(fail, 301, 'file not found')
      return
    }
    later(() => {
      files.delete(uri)
      okCall(success)
    })
  },
}

/* --------------------------- 测试专用入口 --------------------------- */

/** {uri: 字节数} 快照 */
export function __files() {
  const out = {}
  files.forEach((value, key) => {
    out[key] = value.data.length
  })
  return out
}

export function __exists(uri) {
  return files.has(uri)
}

/** 读取某个文件的完整字节（断言落盘内容用） */
export function __bytes(uri) {
  const hit = files.get(uri)
  return hit ? hit.data.slice() : null
}

/** 直接种一个文件（绕过下载链路，测清理逻辑用） */
export function __seed(uri, content) {
  const data = typeof content === 'string' ? new TextEncoder().encode(content) : asBytes(content)
  files.set(uri, { data: new Uint8Array(data), mtime: Date.now() })
}

/**
 * 这台机型的 tmp 分区能不能被 readArrayBuffer 直接读。
 * 默认 **false**（照真机：`responseType:'file'` 给的 uri 直接读回 202 参数错误）。
 */
export function __setTmpReadAllowed(on) {
  tmpReadAllowed = !!on
}

/** 模拟「连 file.copy 都不许以 tmp 为源」的机型（两条读法都会失败） */
export function __setCopyFromTmpDenied(on) {
  copyFromTmpDenied = !!on
}

/**
 * tmp 分区的 readText 行为：'denied'（默认，官方文档之外的最坏情况）| 'byte' | 'base64' | 'utf8'。
 * 见文件顶部 tmpReadTextMode 的说明 —— 三种映射对应三种完全不同的处置。
 */
export function __setTmpReadText(mode) {
  tmpReadTextMode = mode || 'denied'
}

/** readText 的调用记录：{uri, encoding, mode, ok}[] */
export function __textReads() {
  return textReads.slice()
}

/** readArrayBuffer 的调用记录：{uri, position, length, ok}[] */
export function __reads() {
  return reads.slice()
}

/** file.copy 的调用记录：{srcUri, dstUri}[] */
export function __copies() {
  return copies.slice()
}

/**
 * writeArrayBuffer 的调用记录：{uri, length, append, ok}[]（按调用顺序）。
 * B 档音频落盘的「攒批」就靠它断言：逐帧写 = 每帧一条，攒批后 = 每批一条。
 */
export function __writes() {
  return writes.slice()
}

export function __reset() {
  files.clear()
  reads.length = 0
  copies.length = 0
  writes.length = 0
  textReads.length = 0
  tmpReadAllowed = false
  copyFromTmpDenied = false
  tmpReadTextMode = 'denied'
}

export default file
