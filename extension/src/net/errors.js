/**
 * 异常体系（纯类定义，无任何依赖）
 *
 *   BiliApiException    — HTTP 200 但 code != 0
 *   BiliNetworkException — 传输层：超时、连接失败、非 200 状态码
 *   BiliParseException  — 响应不是预期 JSON
 *
 * 单独成模块是为了让 http.js（抛）与 request.js / bili_api.js（捕）共用。
 */

/** HTTP 200 但业务 code != 0 */
export class BiliApiException extends Error {
  /**
   * @param {number} code
   * @param {string} message
   * @param {{vVoucher?:string|null, traceId?:string|null}} [extra]
   */
  constructor(code, message, extra = {}) {
    super(message)
    this.name = 'BiliApiException'
    this.code = code
    this.vVoucher = extra.vVoucher ?? null
    this.traceId = extra.traceId ?? null
  }

  /** 未登录。列表/详情类接口在未登录时也可能返回它，不一定是错误。 */
  get isNotLogin() {
    return this.code === -101
  }

  /** 命中风控，需要降频或补签重试 */
  get isRiskControl() {
    return this.code === -352 || this.code === -412 || this.code === -799
  }

  /** 资源不存在（视频被删、分区为空等） */
  get isNotFound() {
    return this.code === -404 || this.code === 62002 || this.code === 62004
  }

  toString() {
    const extra = []
    if (this.vVoucher) extra.push(`vVoucher: ${this.vVoucher}`)
    if (this.traceId) extra.push(`traceId: ${this.traceId}`)
    return `BiliApiException(code: ${this.code}, message: ${this.message}${
      extra.length ? ', ' + extra.join(', ') : ''
    })`
  }
}

/** 传输层：超时、DNS/连接失败、非 200 状态码 */
export class BiliNetworkException extends Error {
  /**
   * @param {number|null} statusCode 非 200 状态码；连接层失败为 null
   * @param {string} message
   * @param {{isTimeout?:boolean}} [extra]
   */
  constructor(statusCode, message, extra = {}) {
    super(message)
    this.name = 'BiliNetworkException'
    this.statusCode = statusCode
    this.isTimeout = !!extra.isTimeout
  }

  /** HTTP 412：B 站用状态码表达风控拦截 */
  get isRiskControl() {
    return this.statusCode === 412
  }

  /**
   * 是否值得退避重试。
   *
   * 不含 412 —— 那是风控，交给补签链路；也不含 304 —— 304 不是「服务端出错」，
   * 该做的是带 `Cache-Control: no-cache` 重取。
   */
  get isRetryable() {
    const s = this.statusCode
    if (this.isTimeout) return true
    if (s == null) return true
    return s === 408 || s === 429 || s >= 500
  }

  toString() {
    return `BiliNetworkException(statusCode: ${this.statusCode}, message: ${this.message}, isTimeout: ${this.isTimeout})`
  }
}

/** 响应体不是预期结构 */
export class BiliParseException extends Error {
  constructor(message, snippet) {
    super(message)
    this.name = 'BiliParseException'
    this.snippet = snippet ?? null
  }

  toString() {
    return `BiliParseException(message: ${this.message}${this.snippet ? `, snippet: ${this.snippet}` : ''})`
  }
}

export default { BiliApiException, BiliNetworkException, BiliParseException }
