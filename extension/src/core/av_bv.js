/**
 * AV 号转 BV 号。
 *
 * 算法常量与映射表来自 B 站前端常见的 av2bv 实现。
 * 只有 av2bv：搜索里 `AVxxx` 前缀要先转成 BV 再去查稿件详情。
 */

const XOR_CODE = 23442827791579n
const BASE = 58n
const DATA = 'FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf'

/**
 * @param {string[]} list
 * @param {number} i
 * @param {number} j
 */
function swap(list, i, j) {
  const temp = list[i]
  list[i] = list[j]
  list[j] = temp
}

/**
 * @param {number} aid
 * @returns {string} 12 位 BV 号
 */
export function av2bv(aid) {
  const bytes = ['B', 'V', '1', '0', '0', '0', '0', '0', '0', '0', '0', '0']
  let bvIndex = bytes.length - 1

  let tmp = (1n << 51n) | BigInt(aid)
  tmp = tmp ^ XOR_CODE

  while (tmp > 0n) {
    const remainder = tmp % BASE
    bytes[bvIndex] = DATA[Number(remainder)]
    tmp = tmp / BASE
    bvIndex--
  }

  swap(bytes, 3, 9)
  swap(bytes, 4, 7)

  return bytes.join('')
}

/**
 * 从任意输入里抠出 BV 号（搜索框输入可能带空格、URL 或全大写）。
 * 抠不到返回空串，调用方据此回落到关键词搜索。
 *
 * @param {string} raw
 * @returns {string}
 */
export function extractBvid(raw) {
  const m = String(raw || '').match(/BV1[a-zA-Z0-9]{9}/)
  if (!m) return ''
  // B 站 BV 号大小写敏感但首两字母恒为 BV，这里只纠正把 bv 当 BV 输入的情况
  const s = m[0]
  return 'BV' === s.slice(0, 2) ? s : 'BV' + s.slice(2)
}

/**
 * 抠出 AV 号的数字部分；不是 AV 号返回 0。
 *
 * @param {string} raw
 * @returns {number}
 */
export function extractAid(raw) {
  const m = String(raw || '').trim().match(/^av(\d+)/i)
  if (!m) return 0
  return Number(m[1]) || 0
}

export default { av2bv, extractBvid, extractAid }
