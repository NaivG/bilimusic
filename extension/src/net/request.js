/**
 * B 站 API 请求入口：URL 组装、WBI 签名、业务信封校验、风控补签重试
 *
 *   - 按需签名：只有显式 `signed: true` 才签；
 *   - 撞风控自动补签重试一次：未签名被 -352/-412/-799 或 HTTP 412 拦下时，
 *     刷新口令、改成带签名再打一次（不占传输层重试预算）；
 *   - gaia 伪成功形态：`code=0` 但 `data` 里只有一个 `v_voucher` 时不当成功返回，
 *     否则 UI 会把风控挑战当成「搜索到 0 条结果」。
 *
 * 依赖：http / wbi / errors / session，均为单向，无环。
 */

import { CONFIG, RISK_CODES, CODE_NOT_LOGIN } from '../core/config.js'
import { BiliApiException, BiliNetworkException, BiliParseException } from './errors.js'
import { requestOnce, biliHeaders } from './http.js'
import { signedParams, invalidate } from './wbi.js'
import { getCsrf, ready as sessionReady } from '../auth/session.js'

/**
 * 拼 query string。
 *
 * 不用 URLSearchParams：它把空格编成 `+`，而 WBI 签名是拿 `encodeURIComponent`
 * 编码后的串去算 w_rid 的，两边编码不一致服务端就重算不出同一个 w_rid。
 * 这里与 signWbi 用同一套编码，保证「发出去的」就是「签过的」。
 *
 * @param {object} params
 * @returns {string}
 */
export function buildQuery(params) {
  const parts = []
  for (const [k, v] of Object.entries(params || {})) {
    if (v === undefined || v === null) continue
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
  }
  return parts.join('&')
}

/**
 * 组装请求 URL。
 *
 * @param {string} path 以 `/` 开头的路径
 * @param {object} [params]
 * @param {{signed?:boolean, baseUrl?:string}} [opts]
 * @returns {Promise<string>}
 */
export async function buildUrl(path, params, opts = {}) {
  const base = opts.baseUrl || CONFIG.BILI_API
  const signed = opts.signed ? await signedParams(params || {}) : params || {}
  const qs = buildQuery(signed)
  if (!qs) return `${base}${path}`
  return `${base}${path}${path.includes('?') ? '&' : '?'}${qs}`
}

/**
 * 「code=0 但 data 里只有一个 v_voucher」= gaia 风控的伪成功形态。
 * 真实成功响应里 data 至少有一个业务字段（result / nav / info / pages…）。
 *
 * @param {object} json
 * @returns {boolean}
 */
function isVoucherOnly(json) {
  if (json.code !== 0) return false
  const data = json.data
  if (!data || typeof data !== 'object' || Array.isArray(data)) return false
  const voucher = data.v_voucher
  if (typeof voucher !== 'string' || !voucher) return false
  return Object.keys(data).length <= 1
}

/**
 * 把响应信封转成异常（v_voucher 形态换成 code=-352 的清晰错误，
 * 方便上层走风控链路而不是显示成「没有结果」）。
 *
 * @param {object} json
 * @param {Response} response
 * @returns {BiliApiException}
 */
function envelopeError(json, response) {
  if (isVoucherOnly(json)) {
    return new BiliApiException(-352, '风控校验失败（v_voucher）', {
      vVoucher: json.data.v_voucher,
      traceId: response.headers.get('bili-trace-id'),
    })
  }
  const code = typeof json.code === 'number' ? json.code : -1
  const data = json.data
  const voucher =
    data && typeof data === 'object' && typeof data.v_voucher === 'string'
      ? data.v_voucher
      : response.headers.get('x-bili-gaia-vvoucher')
  return new BiliApiException(code, json.message || '未知错误', {
    vVoucher: voucher,
    traceId: response.headers.get('bili-trace-id'),
  })
}

/**
 * 发请求并校验业务信封，返回**完整响应体**（含顶层 page / has_more 等字段）。
 *
 * @param {string} method
 * @param {string} path
 * @param {object} [opts]
 * @param {object} [opts.params] query 参数
 * @param {object|string} [opts.form] POST 表单
 * @param {boolean} [opts.signed] 是否 WBI 签名
 * @param {string} [opts.signedPath] 补签重试时改用的路径（老路径不签 / `/wbi/` 新路径必须签的成对接口）
 * @param {boolean} [opts.includeCsrf] POST 时自动带上 csrf=bili_jct（默认 true）
 * @param {boolean} [opts.retry] 传输层重试开关
 * @param {number} [opts.timeout]
 * @param {object} [opts.headers]
 * @returns {Promise<object>}
 */
export async function send(method, path, opts = {}) {
  // 等登录态就绪：SW 刚被拉起时 session 还没读完盘，抢跑会把已登录读成未登录
  await sessionReady()

  let useSignature = !!opts.signed
  let signatureRetried = false
  let attemptPath = path

  while (true) {
    const url = await buildUrl(attemptPath, opts.params, { signed: useSignature })

    let headers = biliHeaders(opts.headers)
    let body
    if (method === 'POST') {
      const form = { ...(opts.form || {}) }
      if (opts.includeCsrf !== false) {
        const csrf = await getCsrf()
        if (csrf) form.csrf = csrf
      }
      body = typeof form === 'string' ? form : buildQuery(form)
      headers['Content-Type'] = 'application/x-www-form-urlencoded'
    }

    let response
    try {
      response = await requestOnce({
        url,
        method,
        headers,
        body,
        retry: opts.retry,
        timeout: opts.timeout,
      })
    } catch (e) {
      // HTTP 412 是 B 站用状态码表达的风控拦截，与 JSON 路径同样处理：
      // 未签名 → 补签重试一次；已签名 → 刷新口令再试一次。都不占传输层预算。
      if (e instanceof BiliNetworkException && e.isRiskControl && !signatureRetried) {
        signatureRetried = true
        useSignature = true
        invalidate()
        attemptPath = opts.signedPath || path
        continue
      }
      throw e
    }

    const json = response.json
    if (!json || typeof json !== 'object' || Array.isArray(json)) {
      throw new BiliParseException('响应根节点不是 JSON 对象')
    }

    if (json.code === 0 && !isVoucherOnly(json)) return json

    const error = envelopeError(json, response)
    if (error.isRiskControl && !signatureRetried) {
      signatureRetried = true
      useSignature = true
      invalidate()
      attemptPath = opts.signedPath || path
      continue
    }
    throw error
  }
}

/**
 * GET 并返回完整响应体（已校验 code == 0）。
 * 需要读 `page` / `has_more` 等顶层字段时用它。
 *
 * @param {string} path
 * @param {object} [opts] 同 send，另加 params 简写
 * @returns {Promise<object>}
 */
export function getJson(path, opts = {}) {
  return send('GET', path, opts)
}

/**
 * GET 并返回 `data` 字段（只关心数据时用它）。
 *
 * @param {string} path
 * @param {object} [opts]
 * @returns {Promise<any>}
 */
export async function getData(path, opts = {}) {
  const json = await getJson(path, opts)
  return json.data
}

/**
 * POST 表单（application/x-www-form-urlencoded）。
 * 默认带 csrf（Cookie 里的 bili_jct），未登录时为空串——与 Web 端行为一致，
 * 接口自己会返回 -111 之类。
 *
 * @param {string} path
 * @param {object} opts
 * @returns {Promise<object>}
 */
export function postForm(path, opts = {}) {
  return send('POST', path, opts)
}

/** 判断异常是不是「未登录」——列表类接口未登录也返回 -101，不一定是错误 */
export function isNotLogin(e) {
  return e instanceof BiliApiException && e.code === CODE_NOT_LOGIN
}

/** 判断异常是不是风控 */
export function isRiskControl(e) {
  if (e instanceof BiliApiException) return RISK_CODES.has(e.code)
  if (e instanceof BiliNetworkException) return e.isRiskControl
  return false
}

export default { buildQuery, buildUrl, send, getJson, getData, postForm, isNotLogin, isRiskControl }
