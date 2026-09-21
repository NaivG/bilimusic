import { CONFIG } from '../common/config'
import { Storage } from './storage'

/**
 * 登录态会话（内存态 + 持久化）
 * 供 biliApi（读 Cookie）与 authService（写登录态）共用，
 * 单独成模块以避免两者互相 import 造成循环依赖。
 *
 * 存储结构：
 * {
 *   cookieHeader: 'SESSDATA=..; bili_jct=..; DedeUserID=..; DedeUserID__ckMd5=..',
 *   cookies: { SESSDATA, bili_jct, DedeUserID, DedeUserID__ckMd5 },
 *   refreshToken: string,
 *   timestamp: number,       // 登录时间（毫秒）
 *   mid: number,
 *   uname: string,
 *   face: string
 * }
 */

// 参与请求的关键 Cookie 项（顺序固定，便于联调时肉眼比对）
const COOKIE_ORDER = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']

const state = {
  cookieHeader: '',
  cookies: null,
  refreshToken: '',
  timestamp: 0,
  mid: 0,
  uname: '',
  face: '',
  loaded: false,
}

// 幂等的 restore Promise：保证 restore 只跑一次，且后续调用拿到同一份结果。
// 各 page 在 onInit 读登录态前 await `ready()`，避免 app.ux bootstrap 中的
// `await session.restore()` 还没从 @system.storage 读完时就被抢先读到空值，
// 造成「登录成功后进入其他页面立刻显示未登录」的竞态。
let restorePromise = null

const listeners = []

function notify() {
  listeners.forEach((fn) => {
    try {
      fn(snapshot())
    } catch (e) {
      console.error('[Session] listener error:', e)
    }
  })
}

export function snapshot() {
  return {
    loggedIn: !!state.cookieHeader,
    mid: state.mid,
    uname: state.uname,
    face: state.face,
    timestamp: state.timestamp,
  }
}

/**
 * 订阅登录态变化，返回取消订阅函数
 */
export function subscribe(fn) {
  listeners.push(fn)
  return () => {
    const i = listeners.indexOf(fn)
    if (i >= 0) listeners.splice(i, 1)
  }
}

/**
 * 应用启动时调用；从 storage 载入上次登录态。
 * 幂等：多次调用复用同一份 Promise，避免 page 与 app.ux bootstrap 互相抢跑。
 */
export function restore() {
  if (restorePromise) return restorePromise
  restorePromise = (async () => {
    try {
      const saved = await Storage.getJson(CONFIG.STORAGE_KEYS.AUTH, null)
      if (saved && saved.cookieHeader) {
        state.cookieHeader = saved.cookieHeader
        state.cookies = saved.cookies || null
        state.refreshToken = saved.refreshToken || ''
        state.timestamp = saved.timestamp || 0
        state.mid = saved.mid || 0
        state.uname = saved.uname || ''
        state.face = saved.face || ''
        console.log('[Session] restored, mid =', state.mid, 'uname =', state.uname)
      } else {
        console.log('[Session] no saved auth')
      }
    } catch (e) {
      // storage 抛错不能让 page 永久挂起；按「无登录态」继续走，UI 该跳登录就跳
      console.error('[Session] restore failed:', e)
    }
    state.loaded = true
    notify()
    return snapshot()
  })()
  return restorePromise
}

/**
 * 等待首次 restore 完成。
 *  - restore() 未启动过：立即发起，resolve 当前快照
 *  - restore() 进行中：复用同一份 Promise
 *  - restore() 已完成：立即 resolve 当前快照
 *
 * 各 page onInit 在读登录态前先 await 此信号，避免与 app.ux bootstrap 抢跑
 * 读到空 state 导致「登录成功后进入其他页面立刻显示未登录」。
 */
export function ready() {
  if (state.loaded) return Promise.resolve(snapshot())
  return restore().then(() => snapshot())
}

/**
 * 写入登录态并持久化
 * @param {object} auth { cookies, refreshToken, timestamp, mid, uname, face }
 */
export async function setAuth(auth) {
  const cookies = auth.cookies || {}
  state.cookies = cookies
  state.cookieHeader = buildCookieHeader(cookies)
  state.refreshToken = auth.refreshToken || ''
  state.timestamp = auth.timestamp || Date.now()
  state.mid = auth.mid || state.mid || 0
  state.uname = auth.uname || state.uname || ''
  state.face = auth.face || state.face || ''

  console.log('[Session] setAuth cookieHeader length =', state.cookieHeader.length)
  await Storage.setJson(CONFIG.STORAGE_KEYS.AUTH, {
    cookieHeader: state.cookieHeader,
    cookies: state.cookies,
    refreshToken: state.refreshToken,
    timestamp: state.timestamp,
    mid: state.mid,
    uname: state.uname,
    face: state.face,
  })
  notify()
  return snapshot()
}

/**
 * 仅更新用户资料（登录后拉取 nav 补全）
 */
export async function updateProfile(profile) {
  if (!profile) return snapshot()
  state.mid = profile.mid || state.mid
  state.uname = profile.uname || state.uname
  state.face = profile.face || state.face
  await Storage.setJson(CONFIG.STORAGE_KEYS.AUTH, {
    cookieHeader: state.cookieHeader,
    cookies: state.cookies,
    refreshToken: state.refreshToken,
    timestamp: state.timestamp,
    mid: state.mid,
    uname: state.uname,
    face: state.face,
  })
  notify()
  return snapshot()
}

/**
 * 退出登录，清空登录态
 */
export async function clearAuth() {
  state.cookieHeader = ''
  state.cookies = null
  state.refreshToken = ''
  state.timestamp = 0
  state.mid = 0
  state.uname = ''
  state.face = ''
  await Storage.remove(CONFIG.STORAGE_KEYS.AUTH)
  console.log('[Session] cleared')
  notify()
  return snapshot()
}

export function getCookieHeader() {
  return state.cookieHeader
}

export function getMid() {
  return state.mid
}

export function isLoggedIn() {
  return !!state.cookieHeader
}

/**
 * 由 cookie 对象拼出 Cookie 请求头
 * @param {object} cookies
 */
export function buildCookieHeader(cookies) {
  if (!cookies) return ''
  const keys = COOKIE_ORDER.filter((k) => cookies[k])
  // 追加非关键但存在的 cookie 项（如 sid），保证行为更接近浏览器
  Object.keys(cookies).forEach((k) => {
    if (keys.indexOf(k) < 0 && cookies[k]) keys.push(k)
  })
  return keys.map((k) => `${k}=${cookies[k]}`).join('; ')
}

export default {
  restore,
  ready,
  setAuth,
  updateProfile,
  clearAuth,
  getCookieHeader,
  getMid,
  isLoggedIn,
  subscribe,
  snapshot,
  buildCookieHeader,
}
