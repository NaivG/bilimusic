/**
 * QR 编码器（字节模式，纠错级别 M，自动选版本与掩码）
 *
 * 零依赖手写实现：本扩展要求零构建、零 node_modules，而 `qrcode` npm 包
 * 是 3000 行 + 3 个依赖。
 *
 * 参数表来自 src/core/qr_tables.js（由 Python 的 qrcode 库生成），摆放规则
 * 与掩码/罚分算法逐条对照 qrcode/main.py 与 util.py 实现。正确性由
 * scripts/gen_qr_fixtures.py 生成的对照矩阵在 verify.mjs 里逐位比对，
 * 改这里必须同步跑那套。
 *
 * 三个最容易写歪、写歪后「码看起来完全正常但扫不出来」的地方：
 *
 *  1. map_data 的列循环：Python 写的是 `for col in range(size-1, 0, -2)`，
 *     循环体里 `if col <= 6: col -= 1` 只改局部名，下一轮仍从 range 取值；
 *     JS 的 `for (let c = ...; c -= 2)` 递增器作用在被改过的变量上，
 *     会多跳一列、漏掉 (1,0) 这一对。这里用显式列表复刻 range 的语义。
 *  2. 掩码评估时格式信息写的是 False：qrcode 库的 best_mask_pattern 调
 *     `makeImpl(True, i)`，此时格式位与暗模块全为白，罚分是在这个中间态上
 *     算的。若按最终态算，选出来的掩码可能与参照实现不同。
 *  3. 格式信息的摆放方向（15 bit 分两处、LSB 在哪一头）见 setupTypeInfo。
 */

import { RS_BLOCKS, PATTERN_POSITION, FORMAT_MASK, FORMAT_GEN } from '../core/qr_tables.js'

/** 字节模式的模式指示符 */
const MODE_BYTE = 0b0100

/** 版本信息的 BCH(18,6) 生成多项式 */
const VERSION_GEN = 0x1f25

/* ------------------------------------------------------------------ GF(256) */

// QR 用的本原多项式 0x11D
const EXP = new Uint8Array(512)
const LOG = new Uint8Array(256)
;((() => {
  let x = 1
  for (let i = 0; i < 255; i++) {
    EXP[i] = x
    LOG[x] = i
    x <<= 1
    if (x & 0x100) x ^= 0x11d
  }
  for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]
})())

function mul(a, b) {
  if (a === 0 || b === 0) return 0
  return EXP[LOG[a] + LOG[b]]
}

/** (x + α^0)(x + α^1)...(x + α^(n-1))，系数**最高次在前** */
function generatorPoly(n) {
  let g = [1]
  for (let i = 0; i < n; i++) {
    const a = EXP[i]
    const next = new Array(g.length + 1).fill(0)
    for (let k = 0; k < g.length; k++) {
      next[k] ^= g[k] // * x
      next[k + 1] ^= mul(g[k], a) // * α^i
    }
    g = next
  }
  return g
}

/** Reed-Solomon 纠错码字（多项式取余的余数） */
function rsEncode(data, ecLen) {
  const g = generatorPoly(ecLen)
  const buf = new Array(data.length + ecLen).fill(0)
  for (let i = 0; i < data.length; i++) buf[i] = data[i]
  for (let i = 0; i < data.length; i++) {
    const factor = buf[i]
    if (factor === 0) continue
    for (let j = 0; j < g.length; j++) buf[i + j] ^= mul(g[j], factor)
  }
  return buf.slice(data.length)
}

/* ------------------------------------------------------------- 位缓冲与分块 */

class BitWriter {
  constructor() {
    this.bytes = []
    this.len = 0 // 已写入的**位**数
  }

  put(value, nbits) {
    for (let i = nbits - 1; i >= 0; i--) this.putBit((value >> i) & 1)
  }

  putBit(bit) {
    const idx = this.len >> 3
    if (idx >= this.bytes.length) this.bytes.push(0)
    if (bit) this.bytes[idx] |= 0x80 >> (this.len & 7)
    this.len++
  }
}

/** 把 RS_BLOCKS 的紧凑行展开成 [{total, data}, ...] */
function blocksOf(version) {
  const row = RS_BLOCKS[version]
  if (!row) throw new Error(`不支持的 QR 版本：${version}`)
  const out = []
  for (let i = 0; i + 2 < row.length; i += 3) {
    const [total, data, count] = [row[i], row[i + 1], row[i + 2]]
    for (let k = 0; k < count; k++) out.push({ total, data })
  }
  return out
}

/** 该版本可用的数据码字总数 */
function dataCodewordsOf(version) {
  return blocksOf(version).reduce((s, b) => s + b.data, 0)
}

/** 字节模式的长度字段位宽：v1-9 是 8 位，v10-40 是 16 位 */
function lengthBitsOf(version) {
  return version < 10 ? 8 : 16
}

/**
 * 选最小的能装下的版本。
 * @param {number} byteLen
 * @returns {number} 1..40
 */
function selectVersion(byteLen) {
  for (let v = 1; v <= 40; v++) {
    const capacity = dataCodewordsOf(v) * 8
    const needed = 4 + lengthBitsOf(v) + byteLen * 8
    if (capacity >= needed) return v
  }
  throw new Error(`内容过长，超出 QR 版本 40 的容量（${byteLen} 字节）`)
}

/**
 * 数据码字：模式 + 长度 + 数据 + 终止符 + 填充。
 *
 * 终止符最多 4 个 0；补到字节边界；再用 0xEC / 0x11 交替填满到容量上限。
 *
 * @param {Uint8Array} bytes
 * @param {number} version
 * @returns {{codewords:number[], blocks:object[]}}
 */
function buildData(bytes, version) {
  const blocks = blocksOf(version)
  const total = blocks.reduce((s, b) => s + b.data, 0)
  const bitLimit = total * 8

  const bw = new BitWriter()
  bw.put(MODE_BYTE, 4)
  bw.put(bytes.length, lengthBitsOf(version))
  for (const b of bytes) bw.put(b, 8)

  if (bw.len > bitLimit) throw new Error('内容超出所选版本容量')

  for (let i = 0, n = Math.min(4, bitLimit - bw.len); i < n; i++) bw.putBit(0)
  while (bw.len % 8 !== 0) bw.putBit(0)

  const PADS = [0xec, 0x11]
  let pi = 0
  while (bw.len < bitLimit) bw.put(PADS[pi++ % 2], 8)

  return { codewords: bw.bytes.slice(0, total), blocks }
}

/**
 * 分块纠错 + 交错。
 *
 * 交错是把各块的数据码字按列轮流取，再把纠错码字同样轮流取——
 * 这样单个块局部损坏时，错误会摊到整条码上而不是堆在一起。
 *
 * @param {number[]} codewords
 * @param {object[]} blocks
 * @returns {number[]}
 */
function interleave(codewords, blocks) {
  const dcBlocks = []
  const ecBlocks = []
  let offset = 0
  let maxDc = 0
  let maxEc = 0

  for (const b of blocks) {
    const dc = codewords.slice(offset, offset + b.data)
    offset += b.data
    const ecLen = b.total - b.data
    dcBlocks.push(dc)
    ecBlocks.push(rsEncode(dc, ecLen))
    if (dc.length > maxDc) maxDc = dc.length
    if (ecLen > maxEc) maxEc = ecLen
  }

  const out = []
  for (let i = 0; i < maxDc; i++) for (const dc of dcBlocks) if (i < dc.length) out.push(dc[i])
  for (let i = 0; i < maxEc; i++) for (const ec of ecBlocks) if (i < ec.length) out.push(ec[i])
  return out
}

/* ------------------------------------------------------------------ BCH */

function bchDigit(d) {
  let n = 0
  while (d !== 0) {
    n++
    d >>>= 1
  }
  return n
}

/** 格式信息 BCH(15,5)，末尾异或 G15_MASK。data = (纠错级别 << 3) | 掩码 */
function bchTypeInfo(data) {
  let d = data << 10
  while (bchDigit(d) - bchDigit(FORMAT_GEN) >= 0) {
    d ^= FORMAT_GEN << (bchDigit(d) - bchDigit(FORMAT_GEN))
  }
  return ((data << 10) | d) ^ FORMAT_MASK
}

/** 版本信息 BCH(18,6) */
function bchTypeNumber(data) {
  let d = data << 12
  while (bchDigit(d) - bchDigit(VERSION_GEN) >= 0) {
    d ^= VERSION_GEN << (bchDigit(d) - bchDigit(VERSION_GEN))
  }
  return (data << 12) | d
}

/* ------------------------------------------------------------ 矩阵构建 */

/** 定位图形 + 分隔符（-1..7 的方形区域） */
function setupPositionProbe(m, size, row, col) {
  for (let r = -1; r <= 7; r++) {
    const rr = row + r
    if (rr < 0 || rr >= size) continue
    for (let c = -1; c <= 7; c++) {
      const cc = col + c
      if (cc < 0 || cc >= size) continue
      m[rr][cc] =
        (r >= 0 && r <= 6 && (c === 0 || c === 6)) ||
        (c >= 0 && c <= 6 && (r === 0 || r === 6)) ||
        (r >= 2 && r <= 4 && c >= 2 && c <= 4)
    }
  }
}

function setupTiming(m, size) {
  for (let r = 8; r < size - 8; r++) {
    if (m[r][6] === null) m[r][6] = r % 2 === 0
  }
  for (let c = 8; c < size - 8; c++) {
    if (m[6][c] === null) m[6][c] = c % 2 === 0
  }
}

function setupPositionAdjust(m, version) {
  const pos = PATTERN_POSITION[version - 1] || []
  for (const row of pos) {
    for (const col of pos) {
      // 与定位图形重叠的位置上已经是确定值，跳过
      if (m[row][col] !== null) continue
      for (let r = -2; r <= 2; r++) {
        for (let c = -2; c <= 2; c++) {
          m[row + r][col + c] =
            r === -2 || r === 2 || c === -2 || c === 2 || (r === 0 && c === 0)
        }
      }
    }
  }
}

/**
 * 格式信息（15 bit 写两份）与暗模块。
 *
 * @param {boolean[][]} m
 * @param {number} size
 * @param {number} mask 0..7
 * @param {boolean} test 掩码评估阶段为 true：格式位与暗模块全写 False
 */
function setupTypeInfo(m, size, mask, test) {
  // 纠错级别 M 的指示位是 00
  const bits = bchTypeInfo((0 << 3) | mask)

  // 竖直那份
  for (let i = 0; i < 15; i++) {
    const mod = !test && ((bits >> i) & 1) === 1
    if (i < 6) m[i][8] = mod
    else if (i < 8) m[i + 1][8] = mod
    else m[size - 15 + i][8] = mod
  }

  // 水平那份
  for (let i = 0; i < 15; i++) {
    const mod = !test && ((bits >> i) & 1) === 1
    if (i < 8) m[8][size - i - 1] = mod
    else if (i < 9) m[8][15 - i - 1 + 1] = mod
    else m[8][15 - i - 1] = mod
  }

  // 暗模块（固定为黑）
  m[size - 8][8] = !test
}

function setupTypeNumber(m, size, version, test) {
  if (version < 7) return
  const bits = bchTypeNumber(version)
  for (let i = 0; i < 18; i++) {
    const mod = !test && ((bits >> i) & 1) === 1
    m[(i / 3) | 0][((i % 3) + size - 11) | 0] = mod
  }
  for (let i = 0; i < 18; i++) {
    const mod = !test && ((bits >> i) & 1) === 1
    m[((i % 3) + size - 11) | 0][(i / 3) | 0] = mod
  }
}

/** 掩码条件（i = 行，j = 列） */
function maskFunc(pattern, i, j) {
  switch (pattern) {
    case 0:
      return (i + j) % 2 === 0
    case 1:
      return i % 2 === 0
    case 2:
      return j % 3 === 0
    case 3:
      return (i + j) % 3 === 0
    case 4:
      return (((i / 2) | 0) + ((j / 3) | 0)) % 2 === 0
    case 5:
      return ((i * j) % 2) + ((i * j) % 3) === 0
    case 6:
      return (((i * j) % 2) + ((i * j) % 3)) % 2 === 0
    case 7:
      return (((i * j) % 3) + ((i + j) % 2)) % 2 === 0
    default:
      throw new Error('坏掩码：' + pattern)
  }
}

/**
 * 数据位按之字形铺进矩阵（跳过功能图形），并施加掩码。
 *
 * 列序列必须是「range(size-1, 0, -2) 但越过第 6 列时右移一位」——
 * 见文件头注释第 1 条，JS 的 for 递增器不能直接表达这个语义。
 */
function mapData(m, size, data, mask) {
  const cols = []
  for (let c = size - 1; c > 0; c -= 2) cols.push(c)

  let inc = -1
  let row = size - 1
  let bitIndex = 7
  let byteIndex = 0

  for (const rawCol of cols) {
    let col = rawCol
    if (col <= 6) col -= 1

    for (;;) {
      for (const c of [col, col - 1]) {
        if (m[row][c] !== null) continue
        let dark = false
        if (byteIndex < data.length) dark = ((data[byteIndex] >> bitIndex) & 1) === 1
        if (maskFunc(mask, row, c)) dark = !dark
        m[row][c] = dark
        bitIndex--
        if (bitIndex === -1) {
          byteIndex++
          bitIndex = 7
        }
      }
      row += inc
      if (row < 0 || row >= size) {
        row -= inc
        inc = -inc
        break
      }
    }
  }
}

function createBlank(version, size) {
  const m = Array.from({ length: size }, () => new Array(size).fill(null))
  setupPositionProbe(m, size, 0, 0)
  setupPositionProbe(m, size, size - 7, 0)
  setupPositionProbe(m, size, 0, size - 7)
  setupPositionAdjust(m, version)
  setupTiming(m, size)
  return m
}

/* ------------------------------------------------------------ 罚分（选掩码） */

/**
 * 掩码罚分，四条规则合计。越小越好，平局取下标更小的掩码。
 *
 * 与 qrcode/util.py 的 lost_point 逐条对应——包括 level2/level3 里那个
 * 「跳过下一个位置」的短路优化，它会改变遍历位置，抄漏了选出来的掩码就不同。
 */
function lostPoint(m) {
  const n = m.length
  let lost = 0

  // 1. 同色连续 ≥5
  const container = new Array(n + 1).fill(0)
  for (let row = 0; row < n; row++) {
    const r = m[row]
    let prev = r[0]
    let len = 0
    for (let col = 0; col < n; col++) {
      if (r[col] === prev) len++
      else {
        if (len >= 5) container[len]++
        len = 1
        prev = r[col]
      }
    }
    if (len >= 5) container[len]++
  }
  for (let col = 0; col < n; col++) {
    let prev = m[0][col]
    let len = 0
    for (let row = 0; row < n; row++) {
      if (m[row][col] === prev) len++
      else {
        if (len >= 5) container[len]++
        len = 1
        prev = m[row][col]
      }
    }
    if (len >= 5) container[len]++
  }
  for (let l = 5; l <= n; l++) lost += container[l] * (l - 2)

  // 2. 2×2 同色
  for (let row = 0; row < n - 1; row++) {
    const thisRow = m[row]
    const nextRow = m[row + 1]
    let col = 0
    while (col < n - 1) {
      const topRight = thisRow[col + 1]
      if (topRight !== nextRow[col + 1]) col += 2
      else if (topRight !== thisRow[col]) col++
      else if (topRight !== nextRow[col]) col++
      else {
        lost += 3
        col++
      }
    }
  }

  // 3. 1:1:3:1:1 定位图形样式
  const matchesRow = (arr, col) => {
    if (!(arr[col + 1] === false && arr[col + 4] === true && arr[col + 5] === false && arr[col + 6] === true && arr[col + 9] === false)) {
      return false
    }
    const a = arr[col + 0] === true && arr[col + 2] === true && arr[col + 3] === true && arr[col + 7] === false && arr[col + 8] === false && arr[col + 10] === false
    const b = arr[col + 0] === false && arr[col + 2] === false && arr[col + 3] === false && arr[col + 7] === true && arr[col + 8] === true && arr[col + 10] === true
    return a || b
  }
  for (let row = 0; row < n; row++) {
    const r = m[row]
    let col = 0
    while (col <= n - 11) {
      if (matchesRow(r, col)) lost += 40
      if (r[col + 10]) col += 2
      else col++
    }
  }
  for (let col = 0; col < n; col++) {
    const c = []
    for (let row = 0; row < n; row++) c.push(m[row][col])
    let row = 0
    while (row <= n - 11) {
      if (matchesRow(c, row)) lost += 40
      if (c[row + 10]) row += 2
      else row++
    }
  }

  // 4. 黑白比例偏离 50%
  let dark = 0
  for (let row = 0; row < n; row++) for (let col = 0; col < n; col++) if (m[row][col] === true) dark++
  const percent = dark / (n * n)
  const rating = Math.trunc(Math.abs(percent * 100 - 50) / 5)
  lost += rating * 10

  return lost
}

/* ------------------------------------------------------------------ 对外接口 */

/**
 * 编码为 QR 矩阵。
 *
 * @param {string} text
 * @param {object} [opts]
 * @param {number} [opts.mask] 强制掩码 0..7（默认自动挑罚分最小的）
 * @param {number} [opts.version] 强制版本（默认自动选）
 * @returns {{size:number, version:number, mask:number, modules:boolean[][]}}
 */
export function encode(text, opts = {}) {
  const bytes = new TextEncoder().encode(String(text))
  const version = opts.version || selectVersion(bytes.length)
  const size = version * 4 + 17

  const { codewords, blocks } = buildData(bytes, version)
  const data = interleave(codewords, blocks)

  let mask = opts.mask
  if (mask === undefined || mask === null) {
    // 评估阶段格式位全为白（qrcode 库的 test=true 语义）
    let best = 0
    let bestScore = Infinity
    for (let i = 0; i < 8; i++) {
      const m = createBlank(version, size)
      setupTypeInfo(m, size, i, true)
      setupTypeNumber(m, size, version, true)
      mapData(m, size, data, i)
      const score = lostPoint(m)
      if (i === 0 || score < bestScore) {
        bestScore = score
        best = i
      }
    }
    mask = best
  }

  const m = createBlank(version, size)
  setupTypeInfo(m, size, mask, false)
  setupTypeNumber(m, size, version, false)
  mapData(m, size, data, mask)

  return { size, version, mask, modules: m }
}

/**
 * 矩阵 → SVG 字符串（UI 直接内联，免去 canvas 缩放的模糊）。
 *
 * @param {{size:number, modules:boolean[][]}} qr
 * @param {object} [opts] {dark, light, scale, quiet}
 * @returns {string}
 */
export function toSvg(qr, opts = {}) {
  const scale = opts.scale || 8
  const quiet = opts.quiet === undefined ? 4 : opts.quiet
  const dark = opts.dark || '#000'
  const light = opts.light || '#fff'
  const n = qr.size
  const total = (n + quiet * 2) * scale

  const rects = []
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (!qr.modules[r][c]) continue
      rects.push(
        `<rect x="${(c + quiet) * scale}" y="${(r + quiet) * scale}" width="${scale}" height="${scale}"/>`
      )
    }
  }

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${total} ${total}" ` +
    `width="${total}" height="${total}" shape-rendering="crispEdges">` +
    `<rect width="${total}" height="${total}" fill="${light}"/>` +
    `<g fill="${dark}">${rects.join('')}</g></svg>`
  )
}

export default { encode, toSvg }
