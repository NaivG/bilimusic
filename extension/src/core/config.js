/**
 * 全局配置与常量
 */

export const CONFIG = {
  // B 站主站 API
  BILI_API: 'https://api.bilibili.com',
  // 通行证（TV 端扫码登录）
  BILI_PASSPORT: 'https://passport.bilibili.com',

  // 防盗链请求头。B 站 CDN（upos/edge）校验 Referer：带 Referer+UA 返回 206，
  // 什么都不带返回 403。扩展侧由 rules.json 的 declarativeNetRequest 在网络层注入。
  BILI_REFERER: 'https://www.bilibili.com/',
  BILI_ORIGIN: 'https://www.bilibili.com',

  // 部分接口对 UA 有要求；DNR 同时会把它写到 CDN 请求上
  USER_AGENT:
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',

  // 二维码轮询间隔与有效期（官方 180 秒，留一点余量）
  QR_POLL_INTERVAL: 2000,
  QR_TIMEOUT: 175000,

  LOGIN: {
    /**
     * 扫码登录走 TV 端（passport-tv-login）：登录票据 Cookie 直接在响应体
     * cookie_info.cookies[] 里返回，不依赖 Set-Cookie，也不依赖跨域地址。
     */
    TV_APPKEY: '4409e2ce8ffd12b8',
    TV_APPSEC: '59b43e04ad6965f34319062b478f83dd',
    TV_LOCAL_ID: 0,
  },

  // WBI 口令缓存时长（官方为每日更替，这里缓存 6 小时）
  WBI_CACHE_TTL: 6 * 60 * 60 * 1000,

  // 取流地址有效期余量（秒）。B 站 CDN 地址带 deadline，实测有效期 120 分钟；
  // 剩余少于这个余量就当成过期、重新取流，免得播到一半才 403。
  URL_TTL_MARGIN: 300,

  // 收藏夹分页大小
  FAV_PAGE_SIZE: 20,

  // 本地收藏上限，超出丢最旧
  LOCAL_FAV_MAX: 500,

  // 播放进度写盘节流（毫秒）。只有 position 走这个节流，否则每秒一次 storage
  // 会让所有 UI 的 onChanged 订阅都在空转。
  PROGRESS_SAVE_INTERVAL: 5000,
}

/**
 * B 站音质档：30216=64K / 30232=132K / 30280=192K /
 * 30250=杜比全景声 / 30251=Hi-Res 无损（后两者需大会员账号）。
 *
 * 挑流顺序固定从高到低，请求的档在当前稿件不可用时自动回退。
 */
export const AUDIO_QUALITY = {
  HIGH: '30280',
  MID: '30232',
  LOW: '30216',
}

/** 回退顺序：先精确匹配请求档，再从高到低兜底 */
export const QUALITY_FALLBACK = ['30280', '30232', '30216']

/**
 * 传输层重试判定。
 *
 * 412 与 304 不算可重试：412 是 B 站用状态码表达的风控拦截，交给补签链路；
 * 304 该做的是带 `Cache-Control: no-cache` 重取。
 *
 * @param {number|null} statusCode null 表示连接层直接失败（DNS/TLS/拒绝）
 * @param {boolean} [isTimeout]
 * @returns {boolean}
 */
export function isRetryableStatus(statusCode, isTimeout) {
  if (isTimeout) return true
  if (statusCode == null) return true
  return statusCode === 408 || statusCode === 429 || statusCode >= 500
}

/** 传输层最大尝试次数（含首次）。业务错误不在此列。 */
export const MAX_ATTEMPTS = 2

/** 退避基数（毫秒），实际等待 = base * 2^(n-1) ± 30% 抖动 */
export const RETRY_BASE_DELAY = 300

/**
 * 风控错误码。注意 -799 也在内，漏掉它会让一类风控响应直接抛给 UI。
 */
export const RISK_CODES = new Set([-352, -412, -799])

/** 未登录（列表/详情类接口未登录时也可能返回它，不一定是错误） */
export const CODE_NOT_LOGIN = -101

export default {
  CONFIG,
  AUDIO_QUALITY,
  QUALITY_FALLBACK,
  isRetryableStatus,
  MAX_ATTEMPTS,
  RETRY_BASE_DELAY,
  RISK_CODES,
  CODE_NOT_LOGIN,
}
