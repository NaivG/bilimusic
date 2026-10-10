/**
 * 登录态会话（内存态 + chrome.storage 持久化）
 *
 * 唯一事实来源是浏览器的 Cookie jar，不是本扩展自己存的一份 Cookie 串。
 * 两条登录路径（从 Chrome 导入 / TV 扫码）最终都写进 jar，之后完全一致，
 * 因此 `getCookieHeader()` 只是「把 jar 摊成一个请求头」的视图。
 *
 * 本模块只碰 chrome.storage / chrome.cookies，不 import net/——net/request.js
 * 单向依赖它取 Cookie 头。唯一的例外是导入路径要过一遍 nav 补昵称 / mid，
 * 于是与 net/bili_api.js 形成一个模块级循环；两端都只在函数体里解引用，
 * ESM 的活绑定撑得住，但不要再往这个环里加模块级调用。
 */

import {
  BILI_COOKIE_URL,
  COOKIE_DOMAIN,
  buildCookieHeader,
  filterBiliJarCookies,
  hostOnlyToRehome,
  pickBiliCookies,
} from './cookies.js'
// 见文件头：导入路径要调 nav 补资料，这是刻意保留的模块级环。
import { getUserInfo } from '../net/bili_api.js'

const STORAGE_KEY = 'auth'

/**
 * 登出时摘掉的会话 Cookie。保留 buvid3 / buvid4 / b_nut / bili_ticket /
 * _uuid / b_lsid —— 清掉设备标识等于下次启动从零自举，白白多几次撞风控。
 */
const SESSION_COOKIES = [
  'SESSDATA',
  'bili_jct',
  'DedeUserID',
  'DedeUserID__ckMd5',
  'sid',
  'buvid_fp',
  'x-bili-gaia-vtoken',
]

/** 拼出来的 Cookie 头缓存时长（毫秒）。靠 chrome.cookies.onChanged 主动失效兜底。 */
const HEADER_TTL = 10_000

/**
 * 读 jar：取全量、按域判据自己筛。
 *
 * 不给 `getAll` 传 `domain`：那是在点边界上比字符串（Chromium
 * `MatchFilter::MatchesDomain`），`bilibili.com` / `www.bilibili.com` /
 * `api.bilibili.com` 上的 Cookie 全都匹配不上，而 SESSDATA 的 host-only
 * 落点恰恰就是 `www.bilibili.com`。用 `getAll({})` + `isBiliDomain` 的纯函数
 * 筛法则可单测（判据在 verify.mjs 里跑）。
 *
 * @returns {Promise<Array<object>>}
 */
export async function readJarCookies() {
  return filterBiliJarCookies(await chrome.cookies.getAll({}))
}

/**
 * chrome.cookies.remove 只认 url，不认 domain——按 cookie 的路径还原出候选地址。
 *
 * 两个候选都要给：`www.bilibili.com` 是 host-only 票据的地址，`bilibili.com`
 * 是域 Cookie 剥掉前导点后的那一层。摘一条不存在的 Cookie 是静默 no-op，不会报错。
 *
 * @param {{path?:string, secure?:boolean}} c
 * @returns {string[]}
 */
function removalUrls(c) {
  const path = c.path || '/'
  const scheme = c.secure === false ? 'http' : 'https'
  const withPath = (host) => `${scheme}://${host}${path.startsWith('/') ? path : '/' + path}`
  return [...new Set([withPath('www.bilibili.com'), withPath('bilibili.com')])]
}

/** 摘掉一个 cookie（两种域形态都试），返回是否至少成功一次 */
async function removeCookie(c) {
  let removed = false
  for (const url of removalUrls(c)) {
    try {
      const r = await chrome.cookies.remove({ url, name: c.name })
      if (r) removed = true
    } catch (e) {
      console.warn('[Session] 移除 Cookie 失败', c.name, url, e)
    }
  }
  return removed
}

const state = {
  mode: '',
  cookieHeader: '',
  cookies: null,
  mid: 0,
  uname: '',
  face: '',
  timestamp: 0,
  loaded: false,
}

/** 幂等的 restore Promise，避免并发调用重复读盘 */
let restorePromise = null
let headerCache = { value: '', ts: 0 }

export function snapshot() {
  return {
    loggedIn: !!state.cookieHeader,
    mode: state.mode,
    mid: state.mid,
    uname: state.uname,
    face: state.face,
    timestamp: state.timestamp,
  }
}

/**
 * 从 chrome.storage 载入上次登录态。幂等：多次调用复用同一份 Promise。
 * @returns {Promise<object>}
 */
export function restore() {
  if (restorePromise) return restorePromise
  restorePromise = (async () => {
    try {
      const saved = (await chrome.storage.local.get(STORAGE_KEY))[STORAGE_KEY]
      if (saved && saved.cookieHeader) {
        Object.assign(state, {
          mode: saved.mode || '',
          cookieHeader: saved.cookieHeader,
          cookies: saved.cookies || null,
          mid: saved.mid || 0,
          uname: saved.uname || '',
          face: saved.face || '',
          timestamp: saved.timestamp || 0,
        })
      }
    } catch (e) {
      // storage 抛错不能让上层永久挂起：按「无登录态」继续走
      console.error('[Session] restore failed:', e)
    }
    state.loaded = true
    return snapshot()
  })()
  return restorePromise
}

/** 等首次 restore 完成（net 层发请求前必须先等它，否则会把已登录读成未登录） */
export async function ready() {
  if (state.loaded) return snapshot()
  await restore()
  return snapshot()
}

async function persist() {
  await chrome.storage.local.set({
    [STORAGE_KEY]: {
      mode: state.mode,
      cookieHeader: state.cookieHeader,
      cookies: state.cookies,
      mid: state.mid,
      uname: state.uname,
      face: state.face,
      timestamp: state.timestamp,
    },
  })
}

/**
 * 写入登录态并持久化。
 *
 * @param {object} auth {mode, cookies, mid, uname, face, timestamp}
 */
export async function setAuth(auth) {
  const cookies = auth.cookies || {}
  Object.assign(state, {
    mode: auth.mode || state.mode || 'qr',
    cookies,
    cookieHeader: buildCookieHeader(cookies),
    mid: auth.mid || state.mid || 0,
    uname: auth.uname || state.uname || '',
    face: auth.face || state.face || '',
    timestamp: auth.timestamp || Date.now(),
  })
  invalidateHeader()
  await persist()
  return snapshot()
}

/** 仅更新用户资料（登录后拉取 nav 补全） */
export async function updateProfile(profile) {
  if (!profile) return snapshot()
  state.mid = profile.mid || state.mid
  state.uname = profile.uname || state.uname
  state.face = profile.face || state.face
  await persist()
  return snapshot()
}

/**
 * 从浏览器 Cookie jar 导入登录态。
 *
 * 读所有 B 站域下的 Cookie，只挑本端要的那几项存档，顺带把
 * `www.bilibili.com` 上的 host-only 票据补一份 `.bilibili.com` 的域 Cookie，
 * 否则浏览器对 api.bilibili.com 的请求根本带不上它（只增不减，原票据不动）。
 *
 * @returns {Promise<object>} snapshot（已尽力补上 nav 的昵称 / mid）
 */
export async function importFromBrowser() {
  await ready()
  const cookies = await adoptJarCookies()
  if (!cookies.SESSDATA) {
    throw new Error('Chrome 里没有 bilibili.com 的登录 Cookie，请先在 B 站网页登录')
  }
  const snap = await setAuth({ mode: 'cookies', cookies, timestamp: Date.now() })

  // 昵称 / mid 只有服务端知道，jar 里没有
  try {
    const info = await getUserInfo()
    if (info.isLogin) return await updateProfile(info)
  } catch (e) {
    // 认证没确认上不影响「已导入」这个事实，异常留给上层按原样提示
    console.warn('[Session] 导入后拉取用户资料失败:', e && e.message)
  }
  return snap
}

/**
 * 读出本端要用的那几项，并把 host-only 的票据补一份域 Cookie。
 *
 * @returns {Promise<object>} 形如 { SESSDATA: '...', bili_jct: '...' }
 */
async function adoptJarCookies() {
  const raw = await readJarCookies()
  const cookies = pickBiliCookies(raw)

  // 补一份域 Cookie，否则 api / passport 子域收不到
  const rehome = hostOnlyToRehome(raw, cookies)
  for (const c of rehome) {
    try {
      await chrome.cookies.set({
        url: c.secure === false ? 'http://www.bilibili.com/' : BILI_COOKIE_URL,
        name: c.name,
        value: c.value,
        path: c.path || '/',
        domain: COOKIE_DOMAIN,
        secure: c.secure !== false,
        sameSite: c.sameSite === 'no_restriction' ? 'no_restriction' : 'lax',
      })
    } catch (e) {
      console.warn('[Session] 补域 Cookie 失败', c.name, e)
    }
  }
  if (rehome.length) invalidateHeader()
  return cookies
}

/**
 * 把 TV 扫码拿到的票据写回浏览器 Cookie jar。
 *
 * 写进 jar 之后两条登录路径就汇成同一条：读 jar 走同一个判据，请求时由浏览器
 * 自己带上 jar 里的 Cookie。**domain 必须显式给**：省略即 host-only，而 host-only
 * 的 `www.bilibili.com` 票据收不到 `api.bilibili.com`。服务端没给 domain 时
 * 兜底 `COOKIE_DOMAIN`。
 *
 * @param {Array<{name:string,value:string,domain?:string,path?:string,expires?:number,httpOnly?:boolean,secure?:boolean}>} list
 *   cookie_info.cookies[] 原样
 */
export async function writeCookiesToJar(list) {
  const url = BILI_COOKIE_URL
  for (const c of Array.isArray(list) ? list : []) {
    if (!c || !c.name || !c.value) continue
    const detail = {
      url,
      name: c.name,
      value: c.value,
      // 服务端给了域就尊重它，没给就兜底成域 Cookie（host-only 是错的，见上）
      domain: c.domain || COOKIE_DOMAIN,
      path: c.path || '/',
    }
    if (typeof c.expires === 'number' && c.expires > 0) detail.expirationDate = c.expires
    if (c.httpOnly) detail.httpOnly = true
    if (c.secure) detail.secure = true
    // chrome.cookies 的取值是小写枚举；B 站下发的多为 'Lax' / 'None'
    if (c.sameSite) {
      const s = String(c.sameSite).toLowerCase()
      if (s === 'none') detail.sameSite = 'no_restriction'
      else if (s === 'lax') detail.sameSite = 'lax'
      else if (s === 'strict') detail.sameSite = 'strict'
    }
    try {
      await chrome.cookies.set(detail)
    } catch (e) {
      // 单个 Cookie 写失败不整批中止：票据类的 SESSDATA/bili_jct 才是关键
      console.warn('[Session] 写入 Cookie 失败', c.name, e)
    }
  }
  invalidateHeader()
}

/**
 * 退出登录：只摘会话 Cookie，保留设备标识（清掉设备标识等于下次启动从零自举）。
 */
export async function clearAuth() {
  await ready()
  // 按域筛而不是按 {domain:'.bilibili.com'} 过滤：后者漏掉 www 上的 host-only 票据
  const raw = await readJarCookies()
  for (const c of raw) {
    if (!SESSION_COOKIES.includes(c.name)) continue
    await removeCookie(c)
  }
  Object.assign(state, {
    mode: '',
    cookieHeader: '',
    cookies: null,
    mid: 0,
    uname: '',
    face: '',
    timestamp: 0,
  })
  invalidateHeader()
  await chrome.storage.local.remove(STORAGE_KEY)
  return snapshot()
}

/**
 * 出站请求用的 Cookie 头。
 *
 * 每次现读 jar 是对的（用户可能刚在网页上登出/换号），但 IPC 不便宜，
 * 所以缓存 HEADER_TTL，并由 chrome.cookies.onChanged 主动失效。
 *
 * @returns {Promise<string>}
 */
export async function getCookieHeader() {
  await ready()
  const now = Date.now()
  if (headerCache.value && now - headerCache.ts < HEADER_TTL) return headerCache.value

  const raw = await readJarCookies()
  const header = buildCookieHeader(pickBiliCookies(raw))
  headerCache = { value: header, ts: now }
  // jar 是唯一事实来源，state.cookies 只是登录时的快照
  if (header) state.cookieHeader = header
  return header
}

/** Cookie 头缓存失效（jar 变了） */
export function invalidateHeader() {
  headerCache = { value: '', ts: 0 }
}

/** 写接口的 csrf 参数值 = bili_jct */
export async function getCsrf() {
  const header = await getCookieHeader()
  const m = header.match(/(?:^|;\s*)bili_jct=([^;]+)/)
  return m ? m[1] : ''
}

export function getMid() {
  return state.mid
}

/**
 * 在 service worker 启动时调用：注册 jar 变化监听，让缓存跟着失效。
 * 必须只注册一次（SW 会被反复拉起）。
 */
export function watchJar() {
  if (watchJar.done) return
  watchJar.done = true
  chrome.cookies.onChanged.addListener(() => invalidateHeader())
}
watchJar.done = false

export default {
  restore,
  ready,
  setAuth,
  updateProfile,
  importFromBrowser,
  writeCookiesToJar,
  clearAuth,
  getCookieHeader,
  getCsrf,
  getMid,
  snapshot,
  invalidateHeader,
  watchJar,
}
