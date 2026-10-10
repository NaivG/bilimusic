/**
 * 底层 HTTP：fetch 封装 + 传输层重试
 *
 * 这一层不懂 B 站业务信封（code/data），也不做 WBI 签名——那两件事在
 * request.js。它只负责：拼请求头、超时、按需退避重试、把 fetch 的失败
 * 归类成 BiliNetworkException。
 *
 * 无环依赖：http → errors / session / config，不 import wbi 或 request。
 */

import { CONFIG, isRetryableStatus, MAX_ATTEMPTS, RETRY_BASE_DELAY } from '../core/config.js'
import { BiliNetworkException, BiliParseException } from './errors.js'
import { getCookieHeader } from '../auth/session.js'

/** 默认请求超时（毫秒） */
const DEFAULT_TIMEOUT = 15_000

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

/**
 * 退避：base * 2^(n-1) ± 30% 抖动，上限 30 秒。
 * 抖动是为了别让一批请求在同一拍重来。
 *
 * @param {number} attempt 从 1 开始
 */
async function backoff(attempt) {
  const base = RETRY_BASE_DELAY * 2 ** (attempt - 1)
  const jitter = base * 0.3 * (Math.random() * 2 - 1)
  await sleep(Math.max(0, Math.min(base + jitter, 30_000)))
}

/**
 * 装配出站请求头。
 *
 * `User-Agent` / `Referer` / `Origin` / `Cookie` 都是 forbidden header，
 * fetch 会静默丢弃：Referer 由 rules.json 的 declarativeNetRequest 在网络层注入，
 * 登录态走 credentials:'include' 让浏览器自己附带（浏览器 jar 是唯一事实来源）。
 *
 * @param {object} opts
 * @returns {Record<string,string>}
 */
function buildHeaders(opts) {
  const headers = {
    Accept: 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    ...opts.headers,
  }
  if (opts.referer) headers.Referer = opts.referer
  if (opts.contentType) headers['Content-Type'] = opts.contentType
  return headers
}

/**
 * 带超时与退避重试的 fetch。
 *
 * 重试只认超时 / 连接失败 / 408 / 429 / 5xx。重试请求会带
 * `Cache-Control: no-cache`：B 站部分接口会回 304，而这里没有本地缓存。
 *
 * @param {object} opts
 * @param {string} opts.url
 * @param {string} [opts.method]
 * @param {object} [opts.headers]
 * @param {string} [opts.body]
 * @param {boolean} [opts.retry]
 * @param {number} [opts.timeout]
 * @param {boolean} [opts.withCookie]
 * @returns {Promise<Response>}
 */
export async function rawFetch(opts) {
  const retry = opts.retry !== false
  const timeout = opts.timeout || DEFAULT_TIMEOUT
  const withCookie = opts.withCookie !== false
  let attempt = 1

  while (true) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeout)
    let failure = null
    let response = null

    try {
      const headers = buildHeaders(opts)
      if (attempt > 1) headers['Cache-Control'] = 'no-cache'
      response = await fetch(opts.url, {
        method: opts.method || 'GET',
        headers,
        body: opts.body,
        credentials: withCookie ? 'include' : 'omit',
        signal: controller.signal,
        redirect: 'follow',
      })
    } catch (e) {
      failure =
        e && e.name === 'AbortError'
          ? new BiliNetworkException(null, `请求超时（${Math.round(timeout / 1000)}s）`, {
              isTimeout: true,
            })
          : new BiliNetworkException(null, `网络错误：${(e && e.message) || e}`)
    } finally {
      clearTimeout(timer)
    }

    if (!failure) {
      if (response.status === 200) return response
      failure = new BiliNetworkException(response.status, `HTTP ${response.status}`)
    }

    if (retry && attempt < MAX_ATTEMPTS && isRetryableStatus(failure.statusCode, failure.isTimeout)) {
      await backoff(attempt)
      attempt++
      continue
    }
    throw failure
  }
}

/**
 * 发请求并按 `responseType` 解析。
 *
 * - `json`：解析失败抛 BiliParseException（带响应片段，便于定位）
 * - `text`：原样返回
 *
 * @param {object} opts 同 rawFetch，另加 responseType
 * @returns {Promise<{status:number, json?:any, text?:string, headers:Headers}>}
 */
export async function requestOnce(opts) {
  const response = await rawFetch(opts)
  const headers = response.headers

  if (opts.responseType === 'text') {
    const text = await response.text()
    return { status: response.status, text, headers }
  }

  const text = await response.text()
  try {
    const json = JSON.parse(text)
    return { status: response.status, json, headers }
  } catch (e) {
    const snippet = text.length > 200 ? text.slice(0, 200) + '...' : text
    throw new BiliParseException(`响应不是合法 JSON：${(e && e.message) || e}`, snippet)
  }
}

/**
 * 给主站请求装上 Referer / Origin（DNR 也会注入，这里作为显式意图留一份）。
 *
 * @returns {object}
 */
export function biliHeaders(extra) {
  return {
    Referer: CONFIG.BILI_REFERER,
    Origin: CONFIG.BILI_ORIGIN,
    ...(extra || {}),
  }
}

/** 读一次登录态 Cookie 头（带缓存） */
export { getCookieHeader }

export default { rawFetch, requestOnce, biliHeaders, DEFAULT_TIMEOUT }
