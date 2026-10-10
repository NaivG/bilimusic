/**
 * UI 侧的消息与状态门面
 *
 * UI 的读取面只有 chrome.storage（watch 订阅变化），不直接连 offscreen：
 * 指令一律发给 service worker，由它判活、转发、落盘。
 *
 * 进度显示不依赖落盘节奏：position 是节流落盘的采样点，页面拿
 * displayPosition 本地外推，别把它当实时值渲染。
 */

/**
 * 给 service worker 发指令。
 *
 * 返回的信封是 `{ok, data?, error?}`——业务失败（未登录、风控、网络）不抛异常，
 * 由调用方决定提示方式；只有「SW 根本没回话」才是真异常。
 *
 * @param {string} ns player|auth|fav|search|store|ui
 * @param {string} type
 * @param {object} [payload]
 * @returns {Promise<{ok:boolean, data?:any, error?:string}>}
 */
export async function send(ns, type, payload) {
  try {
    const res = await chrome.runtime.sendMessage({ target: 'sw', ns, type, payload })
    if (!res) return { ok: false, error: '扩展后台未响应' }
    return res
  } catch (e) {
    return { ok: false, error: String((e && e.message) || e) }
  }
}

/**
 * 订阅 SW 广播（登录态、播放状态、设置变化）。
 * @param {(msg:object)=>void} fn
 * @returns {()=>void} 取消订阅
 */
export function onBroadcast(fn) {
  const listener = (msg) => {
    if (!msg || msg.target !== 'ui') return
    fn(msg)
  }
  chrome.runtime.onMessage.addListener(listener)
  return () => chrome.runtime.onMessage.removeListener(listener)
}

/**
 * 订阅 storage 变化（UI 的主状态来源）。
 * @param {(changes:object, area:string)=>void} fn
 * @returns {()=>void}
 */
export function watchStorage(fn) {
  const listener = (changes, area) => {
    if (area !== 'local') return
    fn(changes, area)
  }
  chrome.storage.onChanged.addListener(listener)
  return () => chrome.storage.onChanged.removeListener(listener)
}

/** 一次性读全部持久化状态 */
export function readAll() {
  return chrome.storage.local.get(['playback', 'localFav', 'settings', 'ui', 'auth'])
}

/* ---------------------------------------------------------------- 进度 */

/**
 * 显示用进度（秒）：storage 里的 position 是 SW 节流落盘的采样点
 * （PROGRESS_SAVE_INTERVAL，默认 5s），直接渲染进度条就会「5 秒一跳」。
 * 播放中拿 positionAt（SW 在 patchPlayback 入口盖的采样时刻）之后的流逝
 * 时间外推，两次落盘之间显示也走得动。
 *
 * @param {object|null} p playback；无 positionAt 时退化为原值
 * @param {number} [now] 当前时刻（epoch ms），默认 Date.now()；测试注入用
 * @returns {number} 秒
 */
export function displayPosition(p, now = Date.now()) {
  if (!p) return 0
  const pos = Number(p.position) || 0
  if (p.state !== 'playing' || !p.positionAt) return pos
  const elapsed = Math.max(0, (now - p.positionAt) / 1000)
  const dur = Number(p.duration) || 0
  return dur > 0 ? Math.min(pos + elapsed, dur) : pos + elapsed
}

/**
 * 本地进度心跳：进度是纯本地推算（displayPosition），不靠落盘或广播驱动。
 * 500ms 一次足够顺滑；页面只需要传渲染回调。
 *
 * @param {()=>void} fn
 * @param {number} [ms] 心跳周期，默认 500
 * @returns {()=>void} 取消函数
 */
export function startProgressTicker(fn, ms = 500) {
  const id = setInterval(() => fn(), ms)
  return () => clearInterval(id)
}

/* ---------------------------------------------------------------- 主题 */

/** 支持的主题（对应 md3.tokens.css / md3.bridge.css 里的 [data-theme] 块） */
export const THEMES = ['bilimusic', 'bilimusic-light']

/**
 * 应用主题（写 html[data-theme]，daisyUI 全部组件跟随变量换色）。
 * 值持久化在 ui.theme，两个页面在 storage 变化时都要调它，
 * 这样在「我的」页换主题，开着的另一页会立即跟上。
 * @param {string} [theme] 未传/未知值回退到深色
 * @returns {string} 实际生效的主题名
 */
export function applyTheme(theme) {
  const t = THEMES.includes(theme) ? theme : 'bilimusic'
  document.documentElement.setAttribute('data-theme', t)
  return t
}

/** 秒 → mm:ss（超过一小时用 h:mm:ss） */
export function fmtTime(sec) {
  const s = Math.max(0, Math.floor(sec || 0))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const r = s % 60
  const pad = (n) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`
}

/** 转义 HTML（搜索结果与标题都来自远端，绝不能直接 innerHTML） */
export function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[c])
}

export default { send, onBroadcast, watchStorage, readAll, displayPosition, startProgressTicker, fmtTime, esc, applyTheme, THEMES }
