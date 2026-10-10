/**
 * Service Worker：消息路由、持久化、通知、offscreen 生命周期
 *
 * 三条边界：UI 只读 storage，SW 只写 storage，offscreen 只播。
 * 消息信封 { target, ns, type, payload }，每个上下文先看 target 再决定是否处理。
 */

import { CONFIG, AUDIO_QUALITY } from '../core/config.js'
import { toggleInFavList, capFavList } from '../core/fav_local.js'
import {
  search as searchApi,
  dealFav,
  getCreatedFavFolders,
  getFavResources,
  resolveStream,
} from '../net/bili_api.js'
import { isNotLogin, isRiskControl } from '../net/request.js'
import * as session from '../auth/session.js'
import * as qrLogin from '../auth/qr_login.js'

/* --------------------------------------------------------------- 存储 */

const KEYS = ['auth', 'playback', 'localFav', 'settings', 'ui']

const DEFAULTS = {
  auth: null,
  playback: {
    queue: [],
    index: 0,
    position: 0,
    /** position 的采样时刻（epoch ms），由 patchPlayback 在入口盖章 */
    positionAt: 0,
    duration: 0,
    state: 'idle',
    volume: 1,
    qualityId: AUDIO_QUALITY.HIGH,
    error: '',
  },
  localFav: { tracks: [] },
  settings: { notify: true, quality: AUDIO_QUALITY.HIGH, repeat: 'off' },
  ui: { lastTab: 'search' },
}

async function load(key) {
  const got = await chrome.storage.local.get(key)
  const v = got[key]
  if (v === undefined || v === null) return DEFAULTS[key]
  if (typeof DEFAULTS[key] === 'object' && DEFAULTS[key] !== null && !Array.isArray(DEFAULTS[key])) {
    return { ...DEFAULTS[key], ...v }
  }
  return v
}

/**
 * 局部更新 playback（队列/index/state 立即写，position 走节流）。
 *
 * position 的写盘被节流（CONFIG.PROGRESS_SAVE_INTERVAL），storage 里的进度最多
 * 落后真实播放一个周期——UI 不能直接渲染 position，要拿 positionAt（采样时刻）
 * 外推。所以带 position 的 patch 一进这里就盖时间戳：被节流停在 pendingProgress
 * 里的那一次也带着自己的时间戳，无论哪次被写出去，「进度值 ↔ 采样时刻」都成对成立。
 */
async function patchPlayback(patch, { throttlePosition = false } = {}) {
  if (patch.position !== undefined) patch.positionAt = Date.now()
  const cur = await load('playback')
  // 上次被节流掉的进度先补上，否则切歌/暂停那次写盘会把它丢掉
  const next = { ...cur, ...(pendingProgress || {}), ...patch }
  pendingProgress = null

  // 只有 position 是热字段；切歌 / 暂停 / 队列变化一律立即落盘
  const hotOnly = throttlePosition && Object.keys(patch).every((k) => k === 'position')
  if (hotOnly && Date.now() - lastProgressSave < CONFIG.PROGRESS_SAVE_INTERVAL) {
    pendingProgress = patch
    return next
  }
  lastProgressSave = Date.now()
  await chrome.storage.local.set({ playback: next })
  return next
}

let lastProgressSave = 0
let pendingProgress = null

/* ------------------------------------------------------- 广播给所有 UI */

/**
 * 向所有扩展页面广播不在 storage 里的状态。
 *
 * 播放状态、设置、收藏的真相都在 storage，UI 走 watchStorage 订阅即可。
 * 只有扫码进度这种「转瞬即变、不值得落盘」的才走这里。
 * 无人监听是常态（popup 关着），不算错误。
 */
function broadcast(ns, type, payload) {
  chrome.runtime.sendMessage({ target: 'ui', ns, type, payload }).catch(() => {})
}

/* ------------------------------------------------------- offscreen 生命周期 */

let creatingOffscreen = null

/** offscreen 文档是否活着（Chrome 116+ 的 getContexts） */
async function offscreenAlive() {
  if (!chrome.runtime.getContexts) return false
  const ctxs = await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] })
  return ctxs.length > 0
}

/**
 * 确保 offscreen 播放宿主存在。
 *
 * `AUDIO_PLAYBACK` 理由的 offscreen 在静音 30 秒后会被 Chrome 自动关闭，
 * 所以每次播放前都判一次活。并发调用共享同一个 Promise，避免连开两个。
 *
 * @returns {Promise<boolean>} true = 这次是新建的（调用方要补一次状态恢复）
 */
async function ensureOffscreen() {
  if (await offscreenAlive()) return false
  if (creatingOffscreen) {
    await creatingOffscreen
    return false // 由先到的那次负责发 restore
  }

  let created = true
  creatingOffscreen = (async () => {
    try {
      await chrome.offscreen.createDocument({
        url: 'src/offscreen/offscreen.html',
        reasons: ['AUDIO_PLAYBACK'],
        justification: '后台连续播放音频（BiliMusic 播放宿主）',
      })
    } catch (e) {
      created = false
      console.error('[SW] 创建 offscreen 失败', e)
    } finally {
      creatingOffscreen = null
    }
  })()
  await creatingOffscreen
  return created
}

/**
 * 把持久化的播放状态喂给 offscreen。
 * 必须在发命令之前：新建/被回收后的宿主内存里是空的，直接发 `play` 会因为
 * 队列为空而什么都不做。
 *
 * @param {object} [payload] 已经读好的状态，避免重复读盘
 */
async function sendRestore(payload) {
  const data = payload || { playback: await load('playback'), settings: await load('settings') }
  await sendToOffscreen('restore', data)
}

/**
 * 给 offscreen 发消息并等回话。
 *
 * createDocument 返回时文档的脚本未必已经把监听器挂上，第一条消息会以
 * "Receiving end does not exist" 失败——这是新建宿主后的必现竞态，所以要重试。
 *
 * @param {string} type
 * @param {object} payload
 * @param {number} [attempt]
 * @returns {Promise<object>}
 */
async function sendToOffscreen(type, payload, attempt = 0) {
  try {
    return await chrome.runtime.sendMessage({ target: 'offscreen', ns: 'player', type, payload })
  } catch (e) {
    const msg = String((e && e.message) || e)
    const notReady = /Receiving end does not exist|Could not establish connection|message port closed/i.test(msg)
    if (notReady && attempt < 6) {
      await new Promise((r) => setTimeout(r, 80))
      return sendToOffscreen(type, payload, attempt + 1)
    }
    return { ok: false, error: msg }
  }
}

/* ------------------------------------------------------------ 通知 */

async function notify(title, message, { silent = false } = {}) {
  const settings = await load('settings')
  if (!settings.notify && silent !== 'force') return
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon.png',
    title,
    message,
    priority: silent ? 0 : 1,
  }).catch(() => {})
}

/* ------------------------------------------------------------ 业务处理 */

function describeError(e) {
  if (!e) return '未知错误'
  if (typeof e === 'string') return e
  if (isNotLogin(e)) return '需要登录'
  if (isRiskControl(e)) return '被风控拦截，请稍后再试'
  if (e.code !== undefined && e.code !== null && e.message) return `${e.message}（code=${e.code}）`
  return e.message || String(e)
}

const handlers = {
  /* ---- 搜索 ----
   * handler 的键必须是 `${ns}_${type}`（见 handleMessage），漏一个下划线
   * 不报错、只静默返回「未知消息」——verify.mjs 的接线自检会抓这个。 */
  async search_search(p) {
    try {
      return { ok: true, data: await searchApi(p.query, { page: p.page }) }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },

  /* ---- 登录 ---- */
  async auth_status() {
    await session.ready()
    return session.snapshot()
  },
  async auth_import() {
    try {
      const snap = await session.importFromBrowser()
      return { ok: true, data: snap }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },
  async auth_start() {
    try {
      const url = await qrLogin.startLogin()
      return { ok: true, data: { qrUrl: url } }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },
  async auth_stop() {
    qrLogin.stopLogin(true)
    return { ok: true, data: qrLogin.snapshot() }
  },
  async auth_state() {
    return qrLogin.snapshot()
  },
  async auth_logout() {
    try {
      await session.clearAuth()
      return { ok: true, data: session.snapshot() }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },
  async auth_diagnostics() {
    return { ok: true, data: await qrLogin.cookieDiagnostics() }
  },

  /* ---- 收藏夹 ---- */
  async fav_folders() {
    try {
      return { ok: true, data: await getCreatedFavFolders() }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },
  async fav_resources(p) {
    try {
      return { ok: true, data: await getFavResources(p.mediaId, p.pn, p.ps) }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },
  async fav_deal(p) {
    try {
      await dealFav(p.bvid, !!p.add)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },
  /** 本地收藏：整表读 → 改 → 整表写（低频、点击触发，单写入面够用） */
  async fav_localToggle(p) {
    const cur = await load('localFav')
    const { list, added, changed } = toggleInFavList(cur.tracks, p.track, Date.now())
    if (changed) {
      await chrome.storage.local.set({ localFav: { tracks: capFavList(list) } })
    }
    return { ok: true, data: { added, changed, tracks: capFavList(list) } }
  },

  /* ---- 取流（offscreen 代跑） ---- */
  async player_resolveStream(p) {
    try {
      const stream = await resolveStream(p.track, p.opts || {})
      return { ok: true, data: stream }
    } catch (e) {
      return { ok: false, error: describeError(e) }
    }
  },

  /* ---- 播放指令：转发给 offscreen ---- */
  async player_command(p) {
    const created = await ensureOffscreen()
    // 新建的宿主内存里是空的，必须先把队列/进度喂回去，否则 play 无从下手
    if (created) await sendRestore()
    return sendToOffscreen('command', p)
  },

  /* ---- offscreen 上报的状态：落盘 ----
   * 不广播——UI 订阅的是 chrome.storage.onChanged。 */
  async player_state(p) {
    const patch = { ...p }
    const throttle = !!p.__throttle
    delete patch.__throttle
    await patchPlayback(patch, { throttlePosition: throttle })
    if (patch.state === 'error' && patch.error) {
      notify('播放失败', patch.error, { silent: true })
    }
    return { ok: true }
  },

  /* ---- 设置 ---- */
  async settings_set(p) {
    const cur = await load('settings')
    const next = { ...cur, ...p }
    await chrome.storage.local.set({ settings: next })
    // 音质/循环模式要让播放宿主立刻知道；宿主不在时不用发，
    // 它下次被重建时会走 sendRestore 拿到最新设置
    if (await offscreenAlive()) await sendToOffscreen('settings', next)
    return { ok: true, data: next }
  },
  async ui_set(p) {
    const cur = await load('ui')
    const next = { ...cur, ...p }
    await chrome.storage.local.set({ ui: next })
    return { ok: true, data: next }
  },
  async ui_openPlayer(p) {
    await openPlayerPage(p && p.query)
    return { ok: true }
  },
}

/**
 * 路由到 handler。键是 `${ns}_${type}`。
 */
async function handleMessage(msg) {
  const key = `${msg.ns}_${msg.type}`
  const fn = handlers[key]
  if (!fn) return { ok: false, error: `未知消息：${msg.ns}.${msg.type}` }
  const result = await fn(msg.payload || {})
  // handler 已经返回 {ok,...} 形状的就原样透传，否则包一层
  return result && typeof result === 'object' && 'ok' in result ? result : { ok: true, data: result }
}

/* -------------------------------------------------------------- 装配 */

// 登录态：SW 一启动就恢复，后续每个请求都要等它
session.restore().catch((e) => console.error('[SW] session restore 失败', e))
session.watchJar()

// 扫码状态变化 → 广播给 UI（不在 storage 里）
qrLogin.subscribe((snap) => broadcast('auth', 'state', snap))

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.target !== 'sw') return undefined
  handleMessage(msg)
    .then(sendResponse)
    .catch((e) => sendResponse({ ok: false, error: describeError(e) }))
  return true // 保持消息通道开着，等异步回话
})

chrome.notifications.onClicked.addListener(() => {
  openPlayerPage()
})

/** 打开全页播放器（已开就聚焦），并把搜索词带过去 */
async function openPlayerPage(query) {
  const base = chrome.runtime.getURL('src/ui/player.html')
  const url = query ? `${base}?q=${encodeURIComponent(query)}` : base

  // 带 url 条件的 query 对扩展自己的页面不需要 tabs 权限
  const existing = await chrome.tabs.query({ url: `${base}*` })
  if (existing.length) {
    const tab = existing[0]
    await chrome.tabs.update(tab.id, { active: true })
    await chrome.windows.update(tab.windowId, { focused: true })
    if (query) {
      // 已经开着的页面不能靠 URL 传参（改 URL 会整页重载），改用消息
      chrome.tabs
        .sendMessage(tab.id, { target: 'page', ns: 'nav', type: 'search', payload: { query } })
        .catch(() => {})
    }
    return
  }
  await chrome.tabs.create({ url })
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.get(KEYS).then((got) => {
    const patch = {}
    for (const k of KEYS) if (got[k] === undefined) patch[k] = DEFAULTS[k]
    if (Object.keys(patch).length) chrome.storage.local.set(patch)
  })
})

console.log('[SW] BiliMusic service worker 就绪')
