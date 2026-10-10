/**
 * 播放宿主（offscreen document）
 *
 * 只做四件事：
 *   1. 持有 <audio>，执行 play / pause / seek / next / prev；
 *   2. 向 service worker 索取取流结果（自己不发网络请求——offscreen 只有
 *      chrome.runtime 一个扩展 API，也没有登录态与存储）；
 *   3. 广播状态（SW 落盘，UI 通过 chrome.storage.onChanged 订阅）；
 *   4. 设置 Media Session 元数据与播控 handler（feature-detect，不可用时静默跳过）。
 *
 * 生命周期：AUDIO_PLAYBACK 理由在静音 30 秒后会关闭本文档，内存里的队列就没了。
 * SW 每次播放前 ensureOffscreen() 重建，并用 restore 把持久化的
 * queue/index/position 喂回来续播。
 */

import { findTrackIndex } from '../core/tracks.js'

const audio = document.getElementById('audio')

/* ------------------------------------------------------------- 内存状态 */

const state = {
  queue: [],
  index: 0,
  position: 0,
  duration: 0,
  state: 'idle', // idle | loading | playing | paused | error
  volume: 1,
  qualityId: '30280',
  error: '',
}

let settings = { notify: true, quality: '30280', repeat: 'off' }

/** 当前曲目的候选地址（主地址 + backupUrl），逐条换着试 */
let candidates = []
let candidateIdx = 0
/** 已连续失败的曲目数——连着几首都放不出来时该停手而不是无限往下跳 */
let failureStreak = 0
/** 进度上报节流 */
let lastTick = 0

/* -------------------------------------------------------- 与 SW 通信 */

function requestSW(type, payload) {
  return chrome.runtime.sendMessage({ target: 'sw', ns: 'player', type, payload })
}

/**
 * 上报状态。只发变化的字段——SW 那边靠「是不是只有 position」来判断
 * 要不要节流写盘，每次都发整份状态会让节流永远不生效。
 *
 * @param {object} patch
 * @param {boolean} [throttle] 允许节流（周期性进度）
 */
function report(patch, throttle) {
  chrome.runtime
    .sendMessage({ target: 'sw', ns: 'player', type: 'state', payload: { ...patch, __throttle: !!throttle } })
    .catch(() => {})
}

/* ------------------------------------------------------------- 取流与播放 */

/**
 * 播放下标指定的曲目。
 *
 * @param {number} i
 * @param {object} [opts] {resume: 从多少秒起播, force: 无视缓存重新取流}
 */
async function playIndex(i, opts = {}) {
  const track = state.queue[i]
  if (!track) return

  state.index = i
  state.error = ''
  state.state = 'loading'
  report({ queue: state.queue, index: i, state: 'loading', error: '', duration: state.duration })

  const resume = opts.resume || 0
  let stream
  try {
    const res = await requestSW('resolveStream', {
      track,
      opts: { force: !!opts.force, qualityId: settings.quality },
    })
    if (!res || !res.ok) throw new Error((res && res.error) || '取流失败')
    stream = res.data
  } catch (e) {
    handleTrackError(String((e && e.message) || e))
    return
  }

  candidates = stream.candidates || []
  candidateIdx = 0
  if (stream.qualityId && stream.qualityId !== state.qualityId) {
    state.qualityId = stream.qualityId
    report({ qualityId: state.qualityId })
  }
  if (!candidates.length) {
    handleTrackError('接口未返回可用地址')
    return
  }

  applySource(candidates[0], resume)
}

/** 换一条候选地址重试（主地址 403 时 backupUrl 还能救） */
function retryNextCandidate(resume) {
  candidateIdx++
  if (candidateIdx >= candidates.length) {
    handleTrackError('所有候选地址都播不了（多为防盗链或链接过期）')
    return
  }
  applySource(candidates[candidateIdx], resume)
}

function applySource(url, resume) {
  audio.src = url
  audio.load()
  // 起播位置要等 metadata（时长未知时设置 currentTime 会被丢弃）
  const applyResume = () => {
    if (resume > 0 && isFinite(audio.duration)) {
      audio.currentTime = Math.min(resume, Math.max(0, audio.duration - 1))
    }
  }
  if (audio.readyState >= 1) applyResume()
  else audio.addEventListener('loadedmetadata', applyResume, { once: true })

  audio.play().catch((e) => {
    // autoplay 被拦 / 编码不支持，都交给 error 分支处理
    console.warn('[Player] play() 失败', e && e.message)
    handleTrackError(String((e && e.message) || '播放启动失败'))
  })
}

/* --------------------------------------------------------- 播完 / 失败之后 */

/**
 * 播完或失败之后，下一步播什么。
 *
 * 这是本模块唯一的产品决策点——它决定连播的听感与故障恢复行为。
 * 下面是可用的默认实现，三处 TODO 是留给你的权衡点，改这里不需要动别处。
 *
 * @param {object} ctx
 * @param {number} ctx.index 当前下标
 * @param {number} ctx.queueLen 队列长度
 * @param {'ended'|'error'} ctx.event 结束原因
 * @param {string} ctx.repeat 'off' | 'all' | 'one'
 * @param {number} ctx.failureStreak 已连续失败的曲目数
 * @returns {number|null} 下一个要播的下标；null 表示停下
 */
export function nextAfterEvent(ctx) {
  const { index, queueLen, event, repeat, failureStreak } = ctx
  if (queueLen <= 0) return null

  // 单曲循环：只有「正常播完」才原地重来。
  // 失败也重来会变成死循环——同一首放不出来，重播一百次还是放不出来。
  if (repeat === 'one' && event === 'ended') return index

  if (event === 'error') {
    // 整个队列都试过一遍就停，避免断网时无限空转。
    const threshold = queueLen
    if (failureStreak >= threshold) return null
    return (index + 1) % queueLen
  }

  // 正常播完
  if (index + 1 < queueLen) return index + 1
  // 队列放完了回到开头继续
  if (repeat === 'all') return 0
  return null
}

function handleTrackError(message) {
  console.warn('[Player] 曲目失败:', message)
  failureStreak++
  const next = nextAfterEvent({
    index: state.index,
    queueLen: state.queue.length,
    event: 'error',
    repeat: settings.repeat,
    failureStreak,
  })

  if (next === null) {
    state.state = 'error'
    state.error = message
    // 失败就报一次，由 SW 的 player_state 落到 chrome.notifications。
    report({ state: 'error', error: message, position: 0 })
    return
  }
  state.error = message
  playIndex(next, { resume: 0, force: true }) // 死链重试多少次都还是死链，必须重新取流
}

/* ------------------------------------------------------------- 播控 */

function togglePlay() {
  if (audio.paused) {
    if (!audio.src) {
      // offscreen 刚被重建，没有 src——从持久化的位置续播
      playIndex(state.index, { resume: state.position })
      return
    }
    audio.play().catch(() => {})
  } else {
    audio.pause()
  }
}

function seekTo(seconds) {
  if (!isFinite(audio.duration)) return
  const t = Math.max(0, Math.min(seconds, audio.duration))
  audio.currentTime = t
  state.position = t
  report({ position: t }, false)
}

function step(delta) {
  if (!state.queue.length) return
  let i = state.index + delta
  if (i < 0) i = state.queue.length - 1
  if (i >= state.queue.length) i = settings.repeat === 'all' ? 0 : state.queue.length - 1
  if (i === state.index && audio.src) {
    seekTo(0)
    audio.play().catch(() => {})
    return
  }
  failureStreak = 0
  playIndex(i, { resume: 0 })
}

/**
 * 点播一首（与来源解耦）：
 *   - 已在队列里 → 跳过去播（不重复插入）；
 *   - 不在队列 → 插到当前曲目之后再播。
 * 来源页（搜索/收藏夹）绝不整份替换队列。
 */
function playTrackNow(track) {
  // bvid 优先、退化到 avid，且「一方取不到键」时宁可重复入队也不误判成同一首
  const idx = findTrackIndex(state.queue, track)
  if (idx >= 0) {
    failureStreak = 0
    playIndex(idx, { resume: 0 })
    return
  }
  const insertAt = Math.min(state.index + 1, state.queue.length)
  state.queue.splice(insertAt, 0, track)
  failureStreak = 0
  playIndex(insertAt, { resume: 0 })
}

/** 整份替换队列（「播放全部」） */
function setQueue(queue, index, autoplay) {
  state.queue = Array.isArray(queue) ? queue.slice() : []
  state.index = Math.max(0, Math.min(index || 0, state.queue.length - 1))
  failureStreak = 0
  report({ queue: state.queue, index: state.index, position: 0, state: 'idle', error: '' })
  if (autoplay !== false && state.queue.length) playIndex(state.index, { resume: 0 })
}

/* ------------------------------------------------------- Media Session */

/**
 * 系统媒体控制（锁屏 / 系统媒体栏 / 蓝牙耳机键）。
 * 全程 feature-detect，不可用时静默跳过，由 service worker 的
 * chrome.notifications 兜底。
 */
function setupMediaSession() {
  if (!('mediaSession' in navigator)) {
    console.warn('[Player] navigator.mediaSession 不可用，降级为仅系统通知')
    return
  }
  const ms = navigator.mediaSession
  const set = (action, fn) => {
    try {
      ms.setActionHandler(action, fn)
    } catch (e) {
      // 某些 action 在某些浏览器版本未实现，单个失败不该拖垮其余
      console.warn('[Player] setActionHandler 失败', action, e && e.message)
    }
  }
  set('play', () => audio.play().catch(() => {}))
  set('pause', () => audio.pause())
  set('previoustrack', () => step(-1))
  set('nexttrack', () => step(1))
  set('seekto', (d) => d && typeof d.seekTime === 'number' && seekTo(d.seekTime))
  set('seeked', (d) => d && typeof d.seekTime === 'number' && seekTo(d.seekTime))
  set('stop', () => audio.pause())
}

function updateMediaMetadata() {
  if (!('mediaSession' in navigator)) return
  const t = state.queue[state.index]
  if (!t) return
  try {
    navigator.mediaSession.metadata = new MediaMetadata({
      title: t.title || '未知',
      artist: t.artist || '',
      album: 'BiliMusic',
      artwork: t.cover ? [{ src: t.cover, sizes: '640x360', type: 'image/jpeg' }] : [],
    })
  } catch (e) {
    console.warn('[Player] MediaMetadata 失败', e && e.message)
  }
}

function updatePositionState() {
  if (!('mediaSession' in navigator) || !navigator.mediaSession.setPositionState) return
  try {
    if (isFinite(audio.duration) && audio.duration > 0) {
      navigator.mediaSession.setPositionState({
        duration: audio.duration,
        position: audio.currentTime,
        playbackRate: audio.playbackRate || 1,
      })
    }
  } catch (e) {
    // 某些浏览器对非法 duration/position 会抛，静默忽略
  }
}

/* --------------------------------------------------------- <audio> 事件 */

audio.addEventListener('play', () => {
  state.state = 'playing'
  state.error = ''
  // 真出声了就说明前一首的失败已经翻篇，连败计数清零
  failureStreak = 0
  // position 必须带上：暂停期间 storage 的 positionAt 停在旧采样点，
  // UI 的进度外推要靠这次上报重新对表
  report({ state: 'playing', error: '', position: audio.currentTime })
  updateMediaMetadata()
})

audio.addEventListener('pause', () => {
  if (audio.ended) return
  state.state = 'paused'
  state.position = audio.currentTime
  // 暂停是「用户意图变了」，进度必须立即落盘（节流会丢）
  report({ state: 'paused', position: state.position }, false)
})

audio.addEventListener('durationchange', () => {
  if (!isFinite(audio.duration)) return
  state.duration = audio.duration
  report({ duration: state.duration })
  updatePositionState()
})

audio.addEventListener('timeupdate', () => {
  state.position = audio.currentTime
  const now = Date.now()
  if (now - lastTick < 1000) return
  lastTick = now
  report({ position: state.position }, true)
  updatePositionState()
})

audio.addEventListener('ended', () => {
  state.position = 0
  const next = nextAfterEvent({
    index: state.index,
    queueLen: state.queue.length,
    event: 'ended',
    repeat: settings.repeat,
    failureStreak,
  })
  if (next === null) {
    state.state = 'paused'
    report({ state: 'paused', position: 0 })
    return
  }
  failureStreak = 0
  if (next === state.index) {
    // 单曲循环：原地重播
    seekTo(0)
    audio.play().catch(() => {})
    return
  }
  playIndex(next, { resume: 0 })
})

audio.addEventListener('error', () => {
  if (!audio.src) return // 空 src 不算失败
  console.warn('[Player] audio error', audio.error && audio.error.code)
  retryNextCandidate(state.position)
})

/* ----------------------------------------------------- 消息：SW → 本文档 */

async function handleCommand(action, p) {
  switch (action) {
    case 'play':
      if (!audio.src && state.queue.length) await playIndex(state.index, { resume: state.position })
      else audio.play().catch(() => {})
      return { ok: true }
    case 'pause':
      audio.pause()
      return { ok: true }
    case 'toggle':
      togglePlay()
      return { ok: true }
    case 'next':
      step(1)
      return { ok: true }
    case 'prev':
      step(-1)
      return { ok: true }
    case 'seek':
      seekTo(p.time || 0)
      return { ok: true }
    case 'playTrack':
      playTrackNow(p.track)
      return { ok: true }
    case 'setQueue':
      setQueue(p.queue, p.index, p.autoplay)
      return { ok: true }
    case 'removeAt': {
      const i = p.index
      if (i < 0 || i >= state.queue.length) return { ok: false, error: '下标越界' }
      const removingCurrent = i === state.index
      state.queue.splice(i, 1)
      if (i < state.index) state.index--
      report({ queue: state.queue, index: state.index })
      if (removingCurrent) {
        if (state.queue.length) playIndex(Math.min(state.index, state.queue.length - 1), { resume: 0 })
        else {
          audio.pause()
          audio.removeAttribute('src')
          state.state = 'idle'
          report({ state: 'idle' })
        }
      }
      return { ok: true }
    }
    case 'setVolume':
      state.volume = p.volume
      audio.volume = p.volume
      report({ volume: p.volume })
      return { ok: true }
    default:
      return { ok: false, error: `未知指令：${action}` }
  }
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || msg.target !== 'offscreen') return undefined

  if (msg.type === 'restore') {
    const { playback, settings: s } = msg.payload || {}
    if (s) settings = s
    if (playback) {
      state.queue = playback.queue || []
      state.index = playback.index || 0
      state.position = playback.position || 0
      state.duration = playback.duration || 0
      state.volume = playback.volume === undefined ? 1 : playback.volume
      state.qualityId = playback.qualityId || state.qualityId
      state.state = 'paused'
      audio.volume = state.volume
      updateMediaMetadata()
    }
    sendResponse({ ok: true })
    return undefined
  }

  if (msg.type === 'settings') {
    settings = { ...settings, ...msg.payload }
    if (settings.quality && settings.quality !== state.qualityId) {
      state.qualityId = settings.quality
      // 换音质要重新取流才生效；仅在正在播时才立刻换
      if (audio.src) playIndex(state.index, { resume: state.position, force: true })
    }
    sendResponse({ ok: true })
    return undefined
  }

  if (msg.type === 'command') {
    handleCommand(msg.payload && msg.payload.action, msg.payload || {})
      .then(sendResponse)
      .catch((e) => sendResponse({ ok: false, error: String((e && e.message) || e) }))
    return true
  }

  return undefined
})

/* ------------------------------------------------------------------ 启动 */

setupMediaSession()
audio.volume = state.volume
console.log('[Player] 播放宿主就绪')
