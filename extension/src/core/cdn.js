/**
 * 取流地址（CDN）相关的纯逻辑
 *
 * deadline / 过期窗口：CDN 地址带 `deadline` 参数、实测有效期 120 分钟，
 * 剩余不足 `URL_TTL_MARGIN` 就重新取流，免得播到一半才 403。
 */

/**
 * 取地址里的 `deadline`（unix 秒）；解析不出返回 0。
 * @param {string} url
 * @returns {number}
 */
export function urlDeadline(url) {
  const m = String(url || '').match(/[?&]deadline=(\d{6,})/)
  if (!m) return 0
  const n = Number(m[1])
  return isFinite(n) && n > 0 ? Math.floor(n) : 0
}

/**
 * 地址是否还在有效期内。`marginSec` 是给「刚取回来就要下几十秒」留的余量。
 * 没有 deadline 参数的一律当有效。
 *
 * @param {string} url
 * @param {number} [now] 毫秒时间戳（测试注入）
 * @param {number} [marginSec]
 * @returns {boolean}
 */
export function isUrlFresh(url, now, marginSec) {
  const deadline = urlDeadline(url)
  if (!deadline) return true
  const t = typeof now === 'number' && now > 0 ? now : Date.now()
  const margin = typeof marginSec === 'number' && marginSec >= 0 ? marginSec : 300
  return deadline - t / 1000 > margin
}

/**
 * 滤掉已过期（或即将过期）的地址；全都过期就是空数组，
 * 调用方据此重新取流。
 *
 * @param {string[]} urls
 * @param {number} [now]
 * @param {number} [marginSec]
 * @returns {string[]}
 */
export function filterFreshUrls(urls, now, marginSec) {
  const list = Array.isArray(urls) ? urls : []
  return list.filter((u) => isUrlFresh(u, now, marginSec))
}

/** 去重但保持首次出现的顺序 */
export function uniq(list) {
  const seen = new Set()
  const out = []
  for (const u of list || []) {
    if (!u || seen.has(u)) continue
    seen.add(u)
    out.push(u)
  }
  return out
}

/**
 * 主地址 + backupUrl/backup_url，去重但保持顺序（主地址必须排第一）
 * @param {object} stream
 * @returns {string[]}
 */
export function collectCandidates(stream) {
  if (!stream) return []
  const primary = stream.baseUrl || stream.base_url || ''
  const backups = stream.backupUrl || stream.backup_url || []
  return uniq([primary].concat(backups).filter(Boolean))
}

/**
 * 把 DASH 流字段统一成数组（兼容单对象与数组两种形态）。
 *
 * @param {any} raw
 * @returns {object[]}
 */
export function asStreamList(raw) {
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) return [raw]
  if (Array.isArray(raw)) return raw.filter((x) => x && typeof x === 'object')
  return []
}

export default {
  urlDeadline,
  isUrlFresh,
  filterFreshUrls,
  uniq,
  collectCandidates,
  asStreamList,
}
