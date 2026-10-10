/**
 * TV 端扫码登录状态机
 *
 *   POST /x/passport-tv-login/qrcode/auth_code  → { url, auth_code }（APP 签名）
 *   POST /x/passport-tv-login/qrcode/poll       → 根级 code 为状态
 *
 * 状态码在根级 code（不是 data.code）：
 *   0 成功 | 86038 已失效 | 86039 / 86090 已扫码未确认 | 86013 等待扫码
 *
 * 登录票据直接躺在响应体 cookie_info.cookies[] 里，不依赖 Set-Cookie。
 *
 * 跑在 service worker 里（不是 UI）：轮询是网络状态机，放 UI 里 popup 一关就断了。
 * UI 只通过 subscribe 拿状态快照。
 */

import { CONFIG } from '../core/config.js'
import { tvGenerateQrCode, tvPollQrCode, getUserInfo } from '../net/bili_api.js'
import { fromCookieInfo, pickBiliCookies, BILI_COOKIE_URL } from './cookies.js'
import { setAuth, updateProfile, writeCookiesToJar, getMid } from './session.js'

export const STATUS = {
  IDLE: 'idle',
  LOADING: 'loading',
  WAITING: 'waiting', // 等待扫码
  SCANNED: 'scanned', // 已扫码，等手机确认
  SUCCESS: 'success',
  EXPIRED: 'expired',
  ERROR: 'error',
}

const state = {
  status: STATUS.IDLE,
  message: '',
  qrUrl: '',
  /** 申请二维码时拿到的 auth_code，轮询要用 */
  authCode: '',
  deadline: 0,
  /** 登录成功后拉到的资料，便于 UI 展示 */
  profile: null,
}

let polling = false
let timer = null
let pollDeadline = 0
const listeners = []

function notify() {
  for (const fn of listeners) {
    try {
      fn(snapshot())
    } catch (e) {
      console.error('[QRLogin] listener error:', e)
    }
  }
}

export function snapshot() {
  return {
    status: state.status,
    message: state.message,
    qrUrl: state.qrUrl,
    authCode: state.authCode,
    // 剩余秒数（0 表示没有在等），UI 直接拿去倒计时
    remaining: Math.max(0, Math.ceil((state.deadline - Date.now()) / 1000)),
    profile: state.profile,
  }
}

/**
 * 订阅状态变化，返回取消订阅函数
 * @param {(s:object)=>void} fn
 */
export function subscribe(fn) {
  listeners.push(fn)
  return () => {
    const i = listeners.indexOf(fn)
    if (i >= 0) listeners.splice(i, 1)
  }
}

function setStatus(status, message) {
  state.status = status
  state.message = message || ''
  notify()
}

function scheduleNext(delay) {
  if (!polling) return
  timer = setTimeout(() => {
    timer = null
    pollOnce()
  }, delay)
}

function describe(e) {
  if (!e) return '未知错误'
  if (typeof e === 'string') return e
  if (e.message) return e.message
  if (e.code !== undefined) return `code=${e.code} ${e.data || ''}`.trim()
  return JSON.stringify(e)
}

/** 停止轮询。reset=true 时把二维码状态一并清掉 */
export function stopLogin(reset = true) {
  polling = false
  if (timer) {
    clearTimeout(timer)
    timer = null
  }
  if (reset && state.status !== STATUS.SUCCESS) {
    state.qrUrl = ''
    state.authCode = ''
    state.deadline = 0
    setStatus(STATUS.IDLE, '')
  }
}

/**
 * 申请二维码并开始轮询。
 *
 * @returns {Promise<string>} 二维码内容（登录 URL）
 */
export async function startLogin() {
  stopLogin(true)
  setStatus(STATUS.LOADING, '正在获取二维码…')
  try {
    const { url, authCode } = await tvGenerateQrCode()
    state.qrUrl = url
    state.authCode = authCode
    state.deadline = Date.now() + CONFIG.QR_TIMEOUT
    setStatus(STATUS.WAITING, '请用哔哩哔哩 App 扫码')
    polling = true
    pollDeadline = state.deadline
    scheduleNext(CONFIG.QR_POLL_INTERVAL)
    return url
  } catch (e) {
    console.error('[QRLogin] 申请二维码失败:', e)
    setStatus(STATUS.ERROR, describe(e))
    throw e
  }
}

async function pollOnce() {
  if (!polling) return

  if (Date.now() > pollDeadline) {
    setStatus(STATUS.EXPIRED, '二维码已超时，请重新获取')
    stopLogin(false)
    state.deadline = 0
    notify()
    return
  }

  let body
  try {
    body = await tvPollQrCode(state.authCode)
  } catch (e) {
    // 单次网络抖动不终止轮询
    console.warn('[QRLogin] 轮询失败，稍后重试:', describe(e))
    scheduleNext(CONFIG.QR_POLL_INTERVAL)
    return
  }

  const code = body && body.code
  const apiMessage = (body && body.message) || ''

  if (code === 0) {
    stopLogin(false)
    try {
      await completeLogin(body)
    } catch (e) {
      console.error('[QRLogin] 登录收尾失败:', e)
      setStatus(STATUS.ERROR, describe(e))
    }
    return
  }

  if (code === 86038) {
    setStatus(STATUS.EXPIRED, '二维码已失效，请重新获取')
    stopLogin(false)
    state.deadline = 0
    notify()
    return
  }

  if (code === 86090 || code === 86039) {
    setStatus(STATUS.SCANNED, '已扫码，请在手机上确认')
    scheduleNext(CONFIG.QR_POLL_INTERVAL)
    return
  }

  // 86013（等待扫码）及其余状态：保持等待
  if (state.status !== STATUS.WAITING) {
    setStatus(STATUS.WAITING, apiMessage || '请用哔哩哔哩 App 扫码')
  }
  scheduleNext(CONFIG.QR_POLL_INTERVAL)
}

/**
 * 登录成功收尾：写 Cookie 进浏览器 jar → 校验 → 补全资料
 *
 * 先写 jar 再拉资料：getUserInfo 走的是 jar 里的 Cookie，
 * 顺序反了会拿到未登录的 nav。
 *
 * @param {object} body 轮询响应信封
 */
async function completeLogin(body) {
  const data = (body && body.data) || {}
  const cookieInfo = data.cookie_info
  const list = (cookieInfo && cookieInfo.cookies) || []
  const cookies = fromCookieInfo(list)

  if (!cookies.SESSDATA) {
    const missing = ['SESSDATA', 'bili_jct', 'DedeUserID'].filter((k) => !cookies[k])
    setStatus(STATUS.ERROR, `登录成功但未取到 SESSDATA（缺 ${missing.join(',')}）`)
    return
  }

  // 写回浏览器 Cookie jar —— 之后与「从 Chrome 导入」汇成同一条路
  await writeCookiesToJar(list)
  await setAuth({
    mode: 'qr',
    cookies,
    timestamp: Date.now(),
    mid: Number(data.mid) || 0,
  })

  try {
    const info = await getUserInfo()
    if (info.isLogin) {
      await updateProfile(info)
      state.profile = info
      setStatus(STATUS.SUCCESS, `已登录：${info.uname}`)
    } else {
      // 票据写进去了但服务端不认：多半是 Cookie 落点不对（域 / SameSite），
      // 别报「已登录」——那会让人以为只是昵称没拉到
      setStatus(STATUS.SUCCESS, '票据已写入，但服务端未确认登录态（看下方诊断行）')
    }
  } catch (e) {
    // 拉资料失败不影响登录态本身
    console.warn('[QRLogin] 拉取用户资料失败:', describe(e))
    setStatus(STATUS.SUCCESS, '票据已写入，但服务端未确认登录态（看下方诊断行）')
  }
}

/**
 * 诊断用：当前 jar 里关键 Cookie 的齐备情况与落点（登录页展示）。
 *
 * 必须按「实际会发出去」的那批来数（`{url}` 过滤）：`{domain:'.bilibili.com'}`
 * 会漏掉 `www.bilibili.com` 上的 host-only 票据，于是诊断说「已取得 SESSDATA」
 * 而服务端说未登录。顺带把每项的域一起交出去，一眼能看出落点问题。
 *
 * @returns {Promise<{obtained:string[], missing:string[], domains:object, mid:number}>}
 */
export async function cookieDiagnostics() {
  const raw = await chrome.cookies.getAll({ url: BILI_COOKIE_URL })
  const cookies = pickBiliCookies(raw)
  const key = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']
  const domains = {}
  for (const c of raw) {
    // 同名取第一条（jar 按 path 长度排序，最长路径最先）
    if (c && cookies[c.name] && domains[c.name] === undefined) domains[c.name] = c.domain
  }
  return {
    obtained: Object.keys(cookies),
    missing: key.filter((k) => !cookies[k]),
    domains,
    mid: getMid(),
  }
}

export default { STATUS, startLogin, stopLogin, snapshot, subscribe, cookieDiagnostics }
