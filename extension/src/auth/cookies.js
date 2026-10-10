/**
 * Cookie 头拼装（纯函数，无 chrome.* 依赖）
 *
 * 出站请求的 Cookie 只有这一个装配入口，不要在别处手写 `Cookie: xxx` 拼串。
 * 被 auth/session.js（登录态读写）与 net/request.js（每次请求的头）共用。
 *
 * 两条登录路径产出的形状必须一致（固定顺序就是为了拼出同一个串），否则会出现
 * 「扫码登录能用、导入 Cookie 不能用」这类问题。
 *
 * ## 域
 *
 * `chrome.cookies.getAll({domain})` 的过滤是在点边界上比字符串，不是「拿这个域
 * 去问 jar 会发哪些」：过滤器带前导点 `.bilibili.com` 时，`bilibili.com`、
 * `www.bilibili.com`、`api.bilibili.com` 全都匹配不上。所以读 jar 一律用
 * `{ url }`，或者读全量、在 JS 里按下面的域判据自己筛。
 *
 * 写 jar 时：chrome.cookies.set 省掉 domain 就是 host-only，`api.bilibili.com`
 * 一个字节都收不到。必须显式给 `COOKIE_DOMAIN`。
 */

/**
 * 参与请求的关键 Cookie 项（顺序固定，便于联调时肉眼比对）。
 * `bili_jct` 是所有写接口的 csrf 来源，`SESSDATA` 是会话票据。
 */
export const COOKIE_ORDER = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5']

/** 主站地址：读 jar 与写 jar 都以它为准（host 的前缀匹配同时覆盖 api / passport 等子域） */
export const BILI_COOKIE_URL = 'https://www.bilibili.com/'

/** 写回 jar 时票据的域。带前导点是域 Cookie，api / passport 子域均生效 */
export const COOKIE_DOMAIN = '.bilibili.com'

/** Cookie 的域是不是 B 站（`.bilibili.com` / `bilibili.com` / `api.bilibili.com` 都算） */
export function isBiliDomain(domain) {
  const d = String(domain || '')
    .replace(/^\./, '')
    .toLowerCase()
  return d === 'bilibili.com' || d.endsWith('.bilibili.com')
}

/**
 * 由 cookie 对象拼出 Cookie 请求头的值。
 *
 * 关键项按固定顺序排前面，其余存在且非空的项（如 sid）追加在后——
 * 尽量贴近浏览器实际发出的形态。
 *
 * @param {object|null} cookies
 * @returns {string}
 */
export function buildCookieHeader(cookies) {
  if (!cookies) return ''
  const keys = COOKIE_ORDER.filter((k) => cookies[k])
  for (const k of Object.keys(cookies)) {
    if (!keys.includes(k) && cookies[k]) keys.push(k)
  }
  return keys.map((k) => `${k}=${cookies[k]}`).join('; ')
}

/**
 * 从 `chrome.cookies.getAll()` 的返回里挑出本端要用的那几项。
 *
 * 只留白名单里的名字、丢掉空值，并摊平去重：jar 里同一条票据可能有两份
 * （`www.bilibili.com` 上一份 host-only、`.bilibili.com` 上一份域 Cookie），
 * 键值对形状天然只留先到的那份。
 *
 * @param {Array<{name:string, value:string, domain?:string}>} rawCookies
 * @returns {object} 形如 { SESSDATA: '...', bili_jct: '...', ... }
 */
export function pickBiliCookies(rawCookies) {
  const out = {}
  for (const c of Array.isArray(rawCookies) ? rawCookies : []) {
    if (!c || !c.name) continue
    if (COOKIE_ORDER.includes(c.name) || c.name === 'sid' || c.name === 'buvid3') {
      if (c.value) out[c.name] = c.value
    }
  }
  return out
}

/** 从 cookie_info.cookies[]（TV 扫码响应体）提取键值对 */
export function fromCookieInfo(list) {
  const out = {}
  for (const c of Array.isArray(list) ? list : []) {
    if (c && c.name && c.value) out[c.name] = c.value
  }
  return out
}

/**
 * 全量 raw → 只留 B 站那批（按域筛，不按名字筛）。
 *
 * 给「要按域判断」的少数场景用（登出摘 Cookie、诊断落点）。
 *
 * @param {Array<object>} rawCookies
 * @returns {Array<object>}
 */
export function filterBiliJarCookies(rawCookies) {
  return (Array.isArray(rawCookies) ? rawCookies : []).filter((c) => c && isBiliDomain(c.domain))
}

/**
 * 从 jar 的原始列表里挑出「该补一份域 Cookie」的那几条。
 *
 * 判据是 host-only（域不带前导点），不是具体域名：B 站前端的 SESSDATA 落在
 * `www.bilibili.com` 上，而 host-only 的票据浏览器不会发给 api / passport
 * 子域——于是扩展这边看着已登录、服务端一律回未登录。补一份 `.bilibili.com`
 * 的域 Cookie 之后两边才对齐。只增不减：原有那条 host-only 不动。
 *
 * @param {Array<{name:string,value:string,domain?:string}>} rawCookies
 * @param {object} picked 本端要用的键值对（pickBiliCookies 的输出），只有进了这份的才值得补
 * @returns {Array<object>}
 */
export function hostOnlyToRehome(rawCookies, picked) {
  const names = new Set(Object.keys(picked || {}))
  const seen = new Set()
  const out = []
  for (const c of Array.isArray(rawCookies) ? rawCookies : []) {
    if (!c || !c.name || !c.value || !names.has(c.name)) continue
    if (String(c.domain || '').startsWith('.')) continue
    if (seen.has(c.name)) continue
    seen.add(c.name)
    out.push(c)
  }
  return out
}

export default {
  COOKIE_ORDER,
  BILI_COOKIE_URL,
  COOKIE_DOMAIN,
  isBiliDomain,
  buildCookieHeader,
  pickBiliCookies,
  fromCookieInfo,
  filterBiliJarCookies,
  hostOnlyToRehome,
}
