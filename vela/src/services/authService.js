import { CONFIG } from '../common/config'
import { request } from './api'
import {
  parseCookieHeader,
  parseTvCookieInfo,
  buildCookieDiagnostics,
} from '../common/parse'
import * as biliApi from './biliApi'
import * as session from './session'

/**
 * 扫码登录服务（TV 端单一路径）
 *
 *   POST /x/passport-tv-login/qrcode/auth_code  → { url, auth_code }（APP 签名）
 *   POST /x/passport-tv-login/qrcode/poll       → 根级 code 为状态
 *
 * 成功时 data.cookie_info.cookies[] 直接给出 SESSDATA/bili_jct/DedeUserID，
 * **不依赖响应头 Set-Cookie，也不依赖跨域地址** → 在 Vela 上最可靠。
 *
 */

const STATUS = {
  IDLE: 'idle',
  LOADING: 'loading',
  WAITING: 'waiting',
  SCANNED: 'scanned',
  SUCCESS: 'success',
  EXPIRED: 'expired',
  ERROR: 'error',
}

const listeners = []

const state = {
  status: STATUS.IDLE,
  qrcodeUrl: '',
  authCode: '',
  message: '',
  diagnostics: null,
}

let pollTimer = null
let pollDeadline = 0
let polling = false

/* ------------------------------ 事件 ------------------------------ */

export function subscribe(fn) {
  listeners.push(fn)
  return () => {
    const i = listeners.indexOf(fn)
    if (i >= 0) listeners.splice(i, 1)
  }
}

function emit(type, payload) {
  const snap = getSnapshot()
  listeners.forEach((fn) => {
    try {
      fn(type, snap, payload || {})
    } catch (e) {
      console.error('[Auth] listener error:', e)
    }
  })
}

export function getSnapshot() {
  return { ...state }
}

function setStatus(status, message) {
  state.status = status
  state.message = message || ''
  console.log(`[Auth] status = ${status}${message ? ' (' + message + ')' : ''}`)
  emit('status', { status, message })
}

/* ------------------------------ 登录流程 ------------------------------ */

/**
 * 申请二维码并开始轮询
 * @returns {Promise<{url:string}>}
 */
export async function startLogin() {
  stopLogin(false)

  state.qrcodeUrl = ''
  state.authCode = ''

  setStatus(STATUS.LOADING, '正在申请二维码…')

  try {
    const { url, authCode } = await biliApi.tvGenerateQrCode()
    state.qrcodeUrl = url
    state.authCode = authCode

    emit('qrcode', { url: state.qrcodeUrl })
    setStatus(STATUS.WAITING, '请用哔哩哔哩客户端扫码')
    beginPolling()
    return { url: state.qrcodeUrl }
  } catch (e) {
    console.error('[Auth] 申请二维码失败:', e)
    setStatus(STATUS.ERROR, describe(e))
    throw e
  }
}

function beginPolling() {
  polling = true
  pollDeadline = Date.now() + CONFIG.QR_TIMEOUT
  scheduleNext(CONFIG.QR_POLL_INTERVAL)
}

function scheduleNext(delay) {
  if (!polling) return
  pollTimer = setTimeout(() => {
    pollTimer = null
    pollOnce()
  }, delay)
}

async function pollOnce() {
  if (!polling) return

  if (Date.now() > pollDeadline) {
    console.log('[Auth] 二维码超时')
    setStatus(STATUS.EXPIRED, '二维码已超时，请重新获取')
    stopLogin(false)
    return
  }

  let res
  try {
    res = await biliApi.tvPollQrCode(state.authCode)
  } catch (e) {
    // 单次网络抖动不终止轮询
    console.warn('[Auth] 轮询失败，稍后重试:', describe(e))
    scheduleNext(CONFIG.QR_POLL_INTERVAL)
    return
  }

  const body = res.body || {}
  // TV 端的业务状态码在**根级 code**（不是 data.code）
  const code = body.code
  const apiMessage = body.message || ''

  if (code === 0) {
    stopLogin(false)
    try {
      await completeLogin(res)
    } catch (e) {
      console.error('[Auth] 登录收尾失败:', e)
      setStatus(STATUS.ERROR, describe(e))
    }
    return
  }

  if (code === 86038) {
    setStatus(STATUS.EXPIRED, '二维码已失效，请重新获取')
    stopLogin(false)
    return
  }

  if (code === 86090 || code === 86039) {
    setStatus(STATUS.SCANNED, '已扫码，请在手机上确认')
    scheduleNext(CONFIG.QR_POLL_INTERVAL)
    return
  }

  if (code === 86101) {
    if (state.status !== STATUS.WAITING) setStatus(STATUS.WAITING, '等待扫码…')
    scheduleNext(CONFIG.QR_POLL_INTERVAL)
    return
  }

  // 其余状态（含未扫码时的返回值）继续等待
  if (state.status !== STATUS.WAITING) {
    setStatus(STATUS.WAITING, apiMessage || '等待扫码…')
  }
  scheduleNext(CONFIG.QR_POLL_INTERVAL)
}

/**
 * 登录成功收尾：提取 Cookie -> 校验 -> 落库 -> 拉用户资料
 */
async function completeLogin(pollRes) {
  const { cookies, diagnostics, refreshToken } = extractTvAuth(pollRes)

  state.diagnostics = diagnostics
  emit('diagnostics', diagnostics)

  console.log('[Auth] 取到 Cookie:', diagnostics.obtained.join(', ') || '(空)')

  if (!cookies.SESSDATA) {
    setStatus(
      STATUS.ERROR,
      `登录成功但未取到 SESSDATA（缺 ${diagnostics.missingKeyCookies.join(',')}）`
    )
    return
  }

  await session.setAuth({
    cookies,
    refreshToken: refreshToken || '',
    timestamp: Date.now(),
  })

  // 拉用户资料补全 mid/uname（失败不影响登录态）
  try {
    const info = await biliApi.getUserInfo()
    await session.updateProfile(info)
    console.log('[Auth] 登录成功:', info.uname, `(mid=${info.mid})`)
    setStatus(STATUS.SUCCESS, `已登录：${info.uname}`)
  } catch (e) {
    console.warn('[Auth] 拉取用户资料失败:', describe(e))
    setStatus(STATUS.SUCCESS, '已登录')
  }
}

/**
 * 从 TV 端 poll 响应体里提取登录 Cookie 与诊断信息
 *
 * cookie_info 形如 { cookies: [{name, value, http_only, expires, secure}], domains: [] }；
 * 结构异常（老接口/风控返回）时按「一项都没取到」处理，由上层报错而不是静默成功。
 *
 * @param {object} pollRes 轮询响应信封
 */
function extractTvAuth(pollRes) {
  const data = ((pollRes && pollRes.body) || {}).data || {}
  const cookieInfo = data.cookie_info
  const cookies = parseTvCookieInfo(cookieInfo)
  const declaredNames = ((cookieInfo && cookieInfo.cookies) || [])
    .map((c) => c && c.name)
    .filter(Boolean)
  return {
    cookies,
    diagnostics: buildCookieDiagnostics(cookies, {
      cookieInfoCount: declaredNames.length,
      cookieInfoNames: declaredNames,
      hasRefreshToken: !!data.refresh_token,
      hasAccessToken: !!data.access_token,
    }),
    refreshToken: data.refresh_token,
  }
}

/**
 * 停止轮询
 * @param {boolean} reset 是否重置二维码状态
 */
export function stopLogin(reset = true) {
  polling = false
  if (pollTimer) {
    clearTimeout(pollTimer)
    pollTimer = null
  }
  if (reset && state.status !== STATUS.SUCCESS) {
    state.qrcodeUrl = ''
    state.authCode = ''
    setStatus(STATUS.IDLE, '')
  }
}

/* ------------------------------ 退出登录 ------------------------------ */

/**
 * 退出登录：先尽力让服务端失效，再清本地
 */
export async function logout() {
  stopLogin()
  const cookie = session.getCookieHeader()

  if (cookie) {
    try {
      const cookies = parseCookieHeader(cookie)
      const csrf = cookies.bili_jct
      if (csrf) {
        await request({
          url: `${CONFIG.BILI_PASSPORT}/login/exit/v2`,
          method: 'POST',
          data: `biliCSRF=${encodeURIComponent(csrf)}`,
          responseType: 'json',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            Cookie: cookie,
            Referer: CONFIG.BILI_REFERER,
          },
        })
        console.log('[Auth] 服务端退出完成')
      }
    } catch (e) {
      console.warn('[Auth] 服务端退出失败（忽略）:', describe(e))
    }
  }

  await session.clearAuth()
  state.diagnostics = null
  setStatus(STATUS.IDLE, '已退出登录')
  return true
}

function describe(e) {
  if (!e) return '未知错误'
  if (typeof e === 'string') return e
  if (e.message) return e.message
  if (e.code !== undefined) return `code=${e.code} ${e.data || ''}`.trim()
  return JSON.stringify(e)
}

export { STATUS }

export default {
  startLogin,
  stopLogin,
  logout,
  subscribe,
  getSnapshot,
  STATUS,
}
