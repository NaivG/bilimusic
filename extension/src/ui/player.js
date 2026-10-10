/**
 * 全页播放器：搜索 / 队列 / 收藏夹 / 我的
 *
 * 状态来源只有两个：
 *   - chrome.storage（watchStorage 订阅，offscreen 死了也照常显示）
 *   - service worker 的消息回执（一次性操作的成败）
 * 页面不直接连播放宿主。
 */
import { send, watchStorage, readAll, onBroadcast, fmtTime, esc, applyTheme, displayPosition, startProgressTicker } from './shared/store.js'
import { applyRepeatButton, applyFavButton, isLocalFav, nextRepeat } from './shared/playControls.js'
import { RESULT_TYPES, RESULT_TYPE_LABELS } from '../core/search.js'
import { encode as qrEncode, toSvg as qrSvg } from '../qr/qr_encode.js'

const $ = (id) => document.getElementById(id)

/* --------------------------------------------------------------- 状态 */

let playback = null
let settings = null
let localFav = { tracks: [] }
let auth = null
let uiTheme = 'bilimusic'

// 搜索
let searchResults = []
let searchKeyword = ''
let searchPage = 1
let searchHasMore = false
let activeType = 'all'

// 收藏夹
let folders = []
let currentFolder = null
let folderTracks = []
let folderPage = 1
let folderHasMore = false

// 扫码轮询的本地倒计时
let qrTimer = null
let qrDeadline = 0
let qrMessage = '请用哔哩哔哩 App 扫码'

/* --------------------------------------------------------------- 工具 */

function toast(msg, isError) {
  const el = $('toast')
  el.innerHTML = `<div class="alert ${isError ? 'alert-error' : 'alert-success'} toastAlert"><span>${esc(msg)}</span></div>`
  el.hidden = false
  clearTimeout(el._t)
  el._t = setTimeout(() => {
    el.hidden = true
  }, isError ? 4200 : 2400)
}

/** 搜索结果 / 收藏夹条目 / 队列条目 → 统一的队列曲目形状 */
function normalizeTrack(t) {
  if (!t) return null
  if (t.artist && t.cover !== undefined) return t // 已经是队列形状
  const subtitle = t.subtitle || ''
  return {
    bvid: t.bvid || '',
    id: t.id || 0,
    cid: t.cid || 0,
    title: t.title || '未知',
    artist: t.artist || subtitle.split(' - ')[0] || '未知',
    cover: t.cover || t.coverUrl || '',
    duration: t.duration || 0,
  }
}

function playableResults(list) {
  return (list || []).filter((r) => r && r.bvid).map(normalizeTrack).filter(Boolean)
}

function cmd(action, payload) {
  return send('player', 'command', { action, ...payload })
}

/**
 * MD3 滑块的「已走过的那段」画在轨道渐变上（--pos，见 player.css 的滑块一节），
 * 不是 daisyUI 那套滑块阴影填充——所以每次改 .value 都要把百分比同步过去，
 * 拖动的过程中也要（change 才落盘，但轨道得跟着手指走）。
 * @param {HTMLInputElement} el
 * @param {number} pct 0–100
 */
function setRangePos(el, pct) {
  const v = Math.max(0, Math.min(100, Number(pct) || 0))
  el.style.setProperty('--pos', `${v}%`)
}

/* ----------------------------------------------------------- 图标辅助 */

/** 搜索类型筛选 chip 的图标 */
const TYPE_ICONS = {
  all: 'fas fa-th-large',
  video: 'fas fa-video',
  album: 'fas fa-compact-disc',
  author: 'fas fa-user',
  bangumi: 'fas fa-tv',
  topic: 'fas fa-comment',
  upuser: 'fas fa-at',
}

function applyMuteIcon(v) {
  const btn = $('muteBtn')
  btn.innerHTML =
    v <= 0
      ? '<i class="fas fa-volume-mute"></i>'
      : v <= 0.5
        ? '<i class="fas fa-volume-down"></i>'
        : '<i class="fas fa-volume-up"></i>'
  btn.title = v <= 0 ? '取消静音' : '静音'
}

/* ----------------------------------------------------------- 现在播放条 */

function renderNow() {
  const p = playback
  const track = p && p.queue && p.queue[p.index]

  if (!track) {
    $('npTitle').textContent = '未在播放'
    $('npSub').textContent = '搜索一首歌开始'
    $('npCover').removeAttribute('src')
    $('npCur').textContent = '0:00'
    $('npDur').textContent = '0:00'
    $('npSeek').value = 0
    setRangePos($('npSeek'), 0)
  } else {
    $('npTitle').textContent = track.title || '未知'
    $('npSub').textContent = track.artist || ''
    if (track.cover) $('npCover').src = track.cover
    else $('npCover').removeAttribute('src')

    const playing = p.state === 'playing'
    const t = $('btnToggle')
    t.innerHTML = p.state === 'loading'
      ? '<i class="fas fa-circle-notch fa-spin"></i>'
      : playing
        ? '<i class="fas fa-pause"></i>'
        : '<i class="fas fa-play"></i>'
    t.disabled = p.state === 'loading'
    t.title = p.state === 'loading' ? '加载中' : playing ? '暂停' : '播放'

    renderNpProgress()
  }

  const repeat = (settings && settings.repeat) || 'off'
  $('themeSel').value = uiTheme
  if (settings) {
    $('repeatSel2').value = repeat
    $('qualitySel').value = settings.quality || '30280'
    $('notifyChk').checked = !!settings.notify
  }
  // 播放控制条与 popup 同款（shared/playControls.js 出形状）：
  // 循环模式是全局设置；收藏键跟当前曲目走，没有曲目就禁用
  applyRepeatButton($('repeatBtn'), repeat)
  applyFavButton($('btnFav'), isLocalFav(localFav, track), !track)

  if (p && typeof p.volume === 'number') {
    const vol = p.volume
    $('volume').value = Math.round(vol * 100)
    setRangePos($('volume'), vol * 100)
    applyMuteIcon(vol)
  }

  const qLen = p && p.queue ? p.queue.length : 0
  const qBadge = $('queueBadge')
  qBadge.hidden = qLen === 0
  qBadge.textContent = qLen > 99 ? '99+' : String(qLen)
  $('queueInfo').innerHTML = qLen
    ? `<i class="fas fa-list-ul barIcon"></i> ${qLen} 首 · 当前第 ${p.index + 1} 首`
    : '<i class="fas fa-list-ul barIcon"></i> 队列为空'
}

let draggingSeek = false

/**
 * 进度行（npCur/npDur/npSeek）：值来自 displayPosition 的本地外推，两次
 * 落盘之间也走得动（见 store.js）。renderNow() 与 startProgressTicker 的
 * 心跳共用这一份；队列为空时什么都不做。
 */
function renderNpProgress() {
  const p = playback
  if (!p || !p.queue || !p.queue[p.index]) return
  const dur = p.duration || 0
  const pos = displayPosition(p)
  $('npCur').textContent = fmtTime(pos)
  $('npDur').textContent = fmtTime(dur)
  if (!draggingSeek) {
    $('npSeek').value = dur > 0 ? Math.round((pos / dur) * 1000) : 0
    $('npSeek').disabled = dur <= 0
    setRangePos($('npSeek'), dur > 0 ? (pos / dur) * 100 : 0)
  }
}

/* --------------------------------------------------------------- 搜索 */

function renderTypeFilter() {
  const chips = $('typeFilter')
  const types = ['all', ...RESULT_TYPES.filter((t) => searchResults.some((r) => r.type === t))]
  chips.innerHTML = types
    .map(
      (t) =>
        `<button type="button" data-type="${t}" class="btn btn-xs ${t === activeType ? 'btn-primary' : 'btn-ghost'}">` +
        `<i class="${TYPE_ICONS[t] || 'fas fa-tag'}"></i>` +
        `${t === 'all' ? '全部' : esc(RESULT_TYPE_LABELS[t] || t)}</button>`
    )
    .join('')
}

function renderSearch() {
  const box = $('searchResults')
  const list = activeType === 'all' ? searchResults : searchResults.filter((r) => r.type === activeType)

  if (!searchResults.length) {
    box.innerHTML =
      `<div class="empty"><i class="fas fa-${searchKeyword ? 'frown' : 'search'} emptyIcon"></i>` +
      `<div>${searchKeyword ? '没有搜到结果' : '输入关键词开始搜索'}</div></div>`
    $('loadMore').hidden = true
    renderTypeFilter()
    return
  }

  const currentBvid = playback && playback.queue && playback.queue[playback.index] && playback.queue[playback.index].bvid

  box.innerHTML =
    `<div class="panelBar"><span class="muted">「${esc(searchKeyword)}」${list.length} 条` +
    `${searchResults.length > list.length ? `（共 ${searchResults.length} 条）` : ''}</span>` +
    `<button id="playAllSearch" class="btn btn-primary btn-sm"><i class="fas fa-play"></i> 播放全部</button></div>` +
    (list.length
      ? list
          .map((r, i) => {
            const play = r.bvid
              ? `<button data-act="play" data-idx="${i}" title="播放" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-play"></i></button>`
              : `<button disabled title="不可播放" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-play"></i></button>`
            // 收藏到 B 站需要登录（接口要 csrf = bili_jct），未登录不显示这个按钮
            const addSite =
              r.bvid && auth && auth.loggedIn
                ? `<button data-act="bfav" data-idx="${i}" title="收藏到 B 站默认收藏夹" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-plus"></i></button>`
                : ''
            const isCurrent = r.bvid && r.bvid === currentBvid
            return (
              `<div class="list-row${isCurrent ? ' current' : ''}" data-idx="${i}" data-bvid="${esc(r.bvid || '')}">` +
              (r.coverUrl
                ? `<img class="cover" src="${esc(r.coverUrl)}" loading="lazy" alt="">`
                : `<div class="cover"></div>`) +
              `<div class="meta"><div class="title"><span class="txt">${esc(r.title)}</span>` +
              `${isCurrent ? '<span class="badge badge-xs badge-primary badge-soft">播放中</span>' : ''}</div>` +
              `<div class="sub">${esc(r.subtitle)}</div></div>` +
              `<div class="act">${play}${addSite}</div></div>`
            )
          })
          .join('')
      : '<div class="empty"><i class="fas fa-filter emptyIcon"></i><div>该类型下没有结果</div></div>')

  renderTypeFilter()
  $('loadMore').hidden = !searchHasMore

  $('playAllSearch')?.addEventListener('click', () => {
    const tracks = playableResults(activeType === 'all' ? searchResults : list)
    if (!tracks.length) return toast('没有可播放的结果', true)
    cmd('setQueue', { queue: tracks, index: 0, autoplay: true })
    toast(`已加入 ${tracks.length} 首`)
  })
}

async function runSearch(query, { append = false } = {}) {
  searchKeyword = query
  if (!append) {
    searchPage = 1
    searchResults = []
    $('searchResults').innerHTML =
      '<div class="empty"><i class="fas fa-circle-notch fa-spin emptyIcon"></i><div>搜索中…</div></div>'
  }

  const res = await send('search', 'search', { query, page: searchPage })
  if (!res.ok) {
    $('searchResults').innerHTML = `<div class="empty error">${esc(res.error || '搜索失败')}</div>`
    return
  }
  const data = res.data
  searchResults = append ? searchResults.concat(data.results) : data.results
  searchHasMore = !!data.hasMore
  searchPage = data.page || searchPage
  renderSearch()
}

/* ---------------------------------------------------------------- 队列 */

function renderQueue() {
  const box = $('queueList')
  const p = playback
  if (!p || !p.queue || !p.queue.length) {
    box.innerHTML = '<div class="empty"><i class="fas fa-list-ul emptyIcon"></i><div>还没有播放队列</div></div>'
    return
  }
  box.innerHTML = p.queue
    .map(
      (t, i) =>
        `<div class="list-row${i === p.index ? ' current' : ''}" data-idx="${i}">` +
        (t.cover ? `<img class="cover" src="${esc(t.cover)}" loading="lazy" alt="">` : '<div class="cover"></div>') +
        `<div class="meta"><div class="title"><span class="txt">${esc(t.title)}</span>` +
        `${i === p.index ? '<span class="badge badge-xs badge-primary badge-soft">播放中</span>' : ''}</div>` +
        `<div class="sub">${esc(t.artist)}</div></div>` +
        `<div class="act"><button data-act="remove" data-idx="${i}" title="移出队列" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-times"></i></button></div></div>`
    )
    .join('')
}

/* ------------------------------------------------------------- 收藏夹 */

function renderFolders() {
  const box = $('folderList')
  if (!auth || !auth.loggedIn) {
    box.innerHTML = '<div class="empty"><i class="fas fa-lock emptyIcon"></i><div>登录后可查看 B 站收藏夹</div></div>'
    return
  }
  if (!folders.length) {
    box.innerHTML = '<div class="empty"><i class="fas fa-folder-open emptyIcon"></i><div>没有找到收藏夹</div></div>'
    return
  }
  box.innerHTML = folders
    .map(
      (f) =>
        `<div class="list-row" data-mid="${f.mediaId}" data-title="${esc(f.title)}">` +
        (f.cover ? `<img class="cover" src="${esc(f.cover)}" loading="lazy" alt="">` : '<div class="cover"></div>') +
        `<div class="meta"><div class="title"><span class="txt">${esc(f.title)}</span></div>` +
        `<div class="sub">${f.count} 项</div></div>` +
        `<div class="act"><i class="fas fa-chevron-right chev"></i></div></div>`
    )
    .join('')
}

function renderFolderResources() {
  const box = $('resourceList')
  box.innerHTML = folderTracks
    .map(
      (t, i) =>
        `<div class="list-row" data-idx="${i}">` +
        (t.cover ? `<img class="cover" src="${esc(t.cover)}" loading="lazy" alt="">` : '<div class="cover"></div>') +
        `<div class="meta"><div class="title"><span class="txt">${esc(t.title)}</span></div>` +
        `<div class="sub">${esc(t.artist)}</div></div>` +
        `<div class="act"><button data-act="play" data-idx="${i}" title="播放" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-play"></i></button>` +
        `<button data-act="fav" data-idx="${i}" title="收藏到本地" class="btn btn-ghost btn-xs btn-circle"><i class="far fa-heart"></i></button></div></div>`
    )
    .join('')
  $('loadMoreFav').hidden = !folderHasMore
}

async function loadFolders() {
  if (!auth || !auth.loggedIn) return
  const res = await send('fav', 'folders', {})
  if (!res.ok) {
    $('folderList').innerHTML = `<div class="empty error">${esc(res.error)}</div>`
    return
  }
  folders = res.data || []
  renderFolders()
}

async function openFolder(mediaId, title) {
  currentFolder = { mediaId, title }
  folderTracks = []
  folderPage = 1
  folderHasMore = false
  $('folderTitle').textContent = title
  $('resourceList').innerHTML =
    '<div class="empty"><i class="fas fa-circle-notch fa-spin emptyIcon"></i><div>加载中…</div></div>'
  $('folderList').hidden = true
  $('resourcePane').hidden = false
  await loadFolderPage()
}

async function loadFolderPage() {
  const res = await send('fav', 'resources', { mediaId: currentFolder.mediaId, pn: folderPage })
  if (!res.ok) {
    $('resourceList').innerHTML = `<div class="empty error">${esc(res.error)}</div>`
    return
  }
  const data = res.data
  folderTracks = folderPage === 1 ? data.tracks : folderTracks.concat(data.tracks)
  folderHasMore = !!data.hasMore
  folderPage++
  renderFolderResources()
}

function renderLocalFav() {
  const box = $('localList')
  const tracks = localFav.tracks || []
  $('localInfo').innerHTML = tracks.length
    ? `<i class="fas fa-bookmark barIcon"></i> ${tracks.length} 首`
    : ''
  if (!tracks.length) {
    box.innerHTML =
      '<div class="empty"><i class="far fa-heart emptyIcon"></i><div>本地收藏为空（点歌曲右侧 ♥ 添加）</div></div>'
    return
  }
  box.innerHTML = tracks
    .map(
      (t, i) =>
        `<div class="list-row" data-idx="${i}">` +
        (t.cover ? `<img class="cover" src="${esc(t.cover)}" loading="lazy" alt="">` : '<div class="cover"></div>') +
        `<div class="meta"><div class="title"><span class="txt">${esc(t.title)}</span></div>` +
        `<div class="sub">${esc(t.artist)}</div></div>` +
        `<div class="act"><button data-act="play" data-idx="${i}" title="播放" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-play"></i></button>` +
        `<button data-act="unfav" data-idx="${i}" title="取消收藏" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-heart"></i></button></div></div>`
    )
    .join('')
}

/* --------------------------------------------------------------- 登录 */

function renderAuth() {
  const st = $('authStatus')
  if (auth && auth.loggedIn) {
    st.textContent = `已登录：${auth.uname || '（未取到昵称）'}${auth.mid ? ` · mid ${auth.mid}` : ''}`
    st.className = ''
    $('btnLogout').hidden = false
    $('btnQr').hidden = true
    $('btnImport').hidden = true
    $('qrBox').hidden = true
    stopQrPolling()
  } else {
    st.textContent = '未登录'
    st.className = 'muted'
    $('btnLogout').hidden = true
    $('btnQr').hidden = false
    $('btnImport').hidden = false
  }
}

function showQr(url) {
  const holder = $('qrHolder')
  qrMessage = '请用哔哩哔哩 App 扫码'
  try {
    const qr = qrEncode(url)
    holder.innerHTML = qrSvg(qr, { scale: 6, quiet: 2 })
    $('qrBox').hidden = false
    $('qrLink').href = url
    $('qrLink').hidden = false
    qrDeadline = Date.now() + 175000
    $('qrHint').textContent = `${qrMessage} · 175s`
    startQrCountdown()
  } catch (e) {
    holder.innerHTML = ''
    $('qrHint').textContent = `二维码生成失败：${e.message}，可直接用下面的链接`
    $('qrBox').hidden = false
    $('qrLink').href = url
    $('qrLink').hidden = false
  }
}

/**
 * 应用扫码状态（来自 service worker 广播，不在 storage 里）。
 * @param {object} s qr_login 的 snapshot
 */
function applyQrState(s) {
  if (!s) return
  if (s.status === 'success') {
    $('qrHint').textContent = s.message || '登录成功'
    stopQrPolling()
    refreshAuth()
    return
  }
  if (s.status === 'error') {
    $('qrHint').textContent = s.message || '登录失败'
    $('authError').textContent = s.message || '登录失败'
    stopQrPolling()
    return
  }
  if (s.status === 'expired') {
    $('qrHint').textContent = s.message || '二维码已失效'
    stopQrPolling()
    return
  }
  qrMessage = s.message || qrMessage
}

/**
 * 倒计时只在本地跑，**不发 IPC**：秒数是纯本地推算的，
 * 每秒去 service worker 问一次状态纯属浪费（状态变化由广播即时送达）。
 */
function startQrCountdown() {
  stopQrPolling()
  const tick = () => {
    const left = Math.max(0, Math.round((qrDeadline - Date.now()) / 1000))
    $('qrHint').textContent = `${qrMessage} · ${left}s`
    if (left <= 0) {
      $('qrHint').textContent = '二维码已失效，请重新获取'
      stopQrPolling()
    }
  }
  tick()
  qrTimer = setInterval(tick, 1000)
}

function stopQrPolling() {
  if (qrTimer) {
    clearInterval(qrTimer)
    qrTimer = null
  }
}

async function refreshAuth() {
  const res = await send('auth', 'status', {})
  if (res.ok) {
    auth = res.data
    renderAuth()
    if (auth && auth.loggedIn) loadFolders()
  }
}

/**
 * 诊断行文案：每项都带上落点域。
 *
 * 只列名字会骗人——host-only 落点（`www.bilibili.com`）的票据 api 子域收不到，
 * 会出现「已取得 SESSDATA」而上游一律回未登录。域名摆出来，这种错一眼可见。
 *
 * @param {{obtained?:string[], missing?:string[], domains?:object}} diag
 * @returns {string}
 */
function formatDiag(diag) {
  if (!diag) return ''
  const got = (diag.obtained || []).map((k) => {
    const d = diag.domains && diag.domains[k]
    return d ? `${k}@${d}` : k
  })
  const parts = [`已取得：${got.join(', ') || '无'}`]
  if (diag.missing && diag.missing.length) parts.push(`缺：${diag.missing.join(', ')}`)
  return parts.join(' · ')
}

/* --------------------------------------------------------------- 标签页 */

function switchTab(name) {
  document.querySelectorAll('.nav button').forEach((b) => {
    b.classList.toggle('active', b.dataset.tab === name)
  })
  document.querySelectorAll('.panel').forEach((p) => {
    p.classList.toggle('active', p.id === `tab-${name}`)
  })
  send('ui', 'set', { lastTab: name }).catch(() => {})
  if (name === 'fav' && folders.length === 0) {
    if (auth && auth.loggedIn) loadFolders()
    else renderFolders() // 未登录也要把「加载中…」换成提示，别让空状态一直转圈
  }
}

/* ---------------------------------------------------------------- 事件 */

function bindControls() {
  $('btnToggle').addEventListener('click', () => cmd('toggle'))
  $('btnPrev').addEventListener('click', () => cmd('prev'))
  $('btnNext').addEventListener('click', () => cmd('next'))

  $('npSeek').addEventListener('pointerdown', () => {
    draggingSeek = true
  })
  // 拖动过程中轨道填充要跟着走（值 0–1000 → 百分比）
  $('npSeek').addEventListener('input', () => setRangePos($('npSeek'), Number($('npSeek').value) / 10))
  $('npSeek').addEventListener('change', () => {
    draggingSeek = false
    const p = playback
    if (!p || !p.duration) return
    cmd('seek', { time: (Number($('npSeek').value) / 1000) * p.duration })
  })
  $('volume').addEventListener('input', () => {
    setRangePos($('volume'), Number($('volume').value))
    cmd('setVolume', { volume: Number($('volume').value) / 100 })
  })

  // 循环模式：顶栏图标按钮点一下切一档（off → all → one），设置页的下拉同步
  $('repeatBtn').addEventListener('click', () => {
    send('settings', 'set', { repeat: nextRepeat(settings && settings.repeat) })
  })

  // 收藏：切当前曲目的本地收藏（与 popup、本地收藏页同一份表）
  $('btnFav').addEventListener('click', async () => {
    const p = playback
    const track = p && p.queue && p.queue[p.index]
    if (!track) return
    const r = await send('fav', 'localToggle', { track })
    if (!r.ok) return toast(r.error || '收藏失败', true)
    if (r.data) localFav.tracks = r.data.tracks
    renderNow()
    renderLocalFav()
    toast(r.data && r.data.added ? '已收藏到本地' : '已取消收藏')
  })

  // 静音：记住上一次的非零音量，取消静音时还回去
  let lastVolume = 0.7
  $('muteBtn').addEventListener('click', () => {
    const v = playback && typeof playback.volume === 'number' ? playback.volume : 1
    if (v > 0) {
      lastVolume = v
      cmd('setVolume', { volume: 0 })
    } else {
      cmd('setVolume', { volume: lastVolume > 0 ? lastVolume : 0.7 })
    }
  })

  const applyRepeat = (v) => send('settings', 'set', { repeat: v })
  $('repeatSel2').addEventListener('change', (e) => applyRepeat(e.target.value))
  $('qualitySel').addEventListener('change', (e) => send('settings', 'set', { quality: e.target.value }))
  $('notifyChk').addEventListener('change', (e) => send('settings', 'set', { notify: e.target.checked }))

  // 主题：立即换（applyTheme 改 data-theme），选择落盘到 ui.theme——
  // 开着的 popup / 其他页面订阅 storage 变化，会跟着换
  $('themeSel').addEventListener('change', (e) => {
    uiTheme = applyTheme(e.target.value)
    send('ui', 'set', { theme: e.target.value })
  })

  // 侧栏导航
  document.querySelectorAll('.nav button').forEach((b) => {
    b.addEventListener('click', () => switchTab(b.dataset.tab))
  })
}

function bindSearch() {
  $('searchForm').addEventListener('submit', (e) => {
    e.preventDefault()
    const q = $('q').value.trim()
    if (!q) return
    switchTab('search')
    runSearch(q)
  })

  $('typeFilter').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-type]')
    if (!btn) return
    activeType = btn.dataset.type
    renderSearch()
  })

  $('loadMore').addEventListener('click', () => runSearch(searchKeyword, { append: true }))

  // 结果行：点歌区与操作按钮是兄弟节点，不嵌套点击
  $('searchResults').addEventListener('click', async (e) => {
    const act = e.target.closest('button[data-act]')
    const row = e.target.closest('.list-row')
    if (!row) return
    const bvid = row.dataset.bvid
    if (!bvid) return
    const list = activeType === 'all' ? searchResults : searchResults.filter((r) => r.type === activeType)
    const item = list[Number(row.dataset.idx)]
    if (!item || !item.bvid) return

    if (act && act.dataset.act === 'bfav') {
      const r = await send('fav', 'deal', { bvid: item.bvid, add: true })
      if (r.ok) toast('已收藏到 B 站')
      else toast(r.error || '收藏失败', true)
      return
    }
    if (act && act.dataset.act !== 'play') return

    await cmd('playTrack', { track: normalizeTrack(item) })
    toast('已开始播放')
  })
}

function bindQueue() {
  $('queueList').addEventListener('click', async (e) => {
    const act = e.target.closest('button[data-act]')
    const row = e.target.closest('.list-row')
    if (!row) return
    const idx = Number(row.dataset.idx)
    if (act && act.dataset.act === 'remove') {
      await cmd('removeAt', { index: idx })
      return
    }
    await cmd('playTrack', { track: playback.queue[idx] })
  })

  $('clearQueue').addEventListener('click', async () => {
    await cmd('setQueue', { queue: [], index: 0, autoplay: false })
    toast('队列已清空')
  })
}

function bindFav() {
  // 两枚分段按钮：选中态 = btn-primary，未选 = btn-ghost
  $('segOnline').addEventListener('click', () => {
    $('segOnline').className = 'btn btn-sm btn-primary'
    $('segLocal').className = 'btn btn-sm btn-ghost'
    $('onlinePane').hidden = false
    $('localPane').hidden = true
  })
  $('segLocal').addEventListener('click', () => {
    $('segLocal').className = 'btn btn-sm btn-primary'
    $('segOnline').className = 'btn btn-sm btn-ghost'
    $('localPane').hidden = false
    $('onlinePane').hidden = true
    renderLocalFav()
  })

  $('folderList').addEventListener('click', (e) => {
    const row = e.target.closest('.list-row')
    if (!row) return
    openFolder(Number(row.dataset.mid), row.dataset.title || '')
  })
  $('backFolders').addEventListener('click', () => {
    $('resourcePane').hidden = true
    $('folderList').hidden = false
    currentFolder = null
  })
  $('loadMoreFav').addEventListener('click', loadFolderPage)

  $('playAllFolder').addEventListener('click', () => {
    const tracks = folderTracks.filter((t) => t.bvid)
    if (!tracks.length) return toast('这个收藏夹里没有可播放内容', true)
    cmd('setQueue', { queue: tracks, index: 0, autoplay: true })
    toast(`已加入 ${tracks.length} 首`)
  })

  $('resourceList').addEventListener('click', async (e) => {
    const act = e.target.closest('button[data-act]')
    const row = e.target.closest('.list-row')
    if (!row) return
    const track = folderTracks[Number(row.dataset.idx)]
    if (!track) return
    if (act && act.dataset.act === 'fav') {
      const r = await send('fav', 'localToggle', { track })
      if (r.ok) {
        localFav.tracks = r.data.tracks
        toast(r.data.added ? '已收藏到本地' : '已取消收藏')
        renderLocalFav()
      } else toast(r.error, true)
      return
    }
    await cmd('playTrack', { track })
  })

  $('playAllLocal').addEventListener('click', () => {
    const tracks = (localFav.tracks || []).filter((t) => t.bvid)
    if (!tracks.length) return toast('本地收藏为空', true)
    cmd('setQueue', { queue: tracks, index: 0, autoplay: true })
    toast(`已加入 ${tracks.length} 首`)
  })

  $('localList').addEventListener('click', async (e) => {
    const act = e.target.closest('button[data-act]')
    const row = e.target.closest('.list-row')
    if (!row) return
    const track = localFav.tracks[Number(row.dataset.idx)]
    if (!track) return
    if (act && act.dataset.act === 'unfav') {
      const r = await send('fav', 'localToggle', { track })
      if (r.ok) {
        localFav.tracks = r.data.tracks
        renderLocalFav()
        toast('已取消收藏')
      } else toast(r.error, true)
      return
    }
    await cmd('playTrack', { track })
  })
}

function bindMine() {
  $('btnQr').addEventListener('click', async () => {
    $('authError').textContent = ''
    const res = await send('auth', 'start', {})
    if (!res.ok) {
      $('authError').textContent = res.error || '申请二维码失败'
      return
    }
    $('btnStopQr').hidden = false
    showQr(res.data.qrUrl)
  })

  $('btnStopQr').addEventListener('click', async () => {
    await send('auth', 'stop', {})
    stopQrPolling()
    $('qrBox').hidden = true
    $('btnStopQr').hidden = true
  })

  $('btnImport').addEventListener('click', async () => {
    $('authError').textContent = ''
    const res = await send('auth', 'import', {})
    if (!res.ok) {
      $('authError').textContent = res.error || '导入失败'
      return
    }
    await refreshAuth()
    const diag = await send('auth', 'diagnostics', {})
    if (diag.ok) $('authDiag').textContent = formatDiag(diag.data)
    toast('已导入 Chrome 登录态')
  })

  $('btnLogout').addEventListener('click', async () => {
    const res = await send('auth', 'logout', {})
    if (!res.ok) return toast(res.error, true)
    auth = res.data
    folders = []
    renderFolders()
    renderAuth()
    toast('已退出登录')
  })
}

/* ---------------------------------------------------------------- 启动 */

async function init() {
  const all = await readAll()
  playback = all.playback
  settings = all.settings
  localFav = all.localFav || { tracks: [] }
  auth = all.auth
  uiTheme = applyTheme(all.ui && all.ui.theme)

  renderNow()
  renderQueue()
  renderLocalFav()
  renderAuth()

  bindControls()
  bindSearch()
  bindQueue()
  bindFav()
  bindMine()

  watchStorage((changes) => {
    if (changes.playback) playback = changes.playback.newValue
    if (changes.settings) settings = changes.settings.newValue
    if (changes.localFav) localFav = changes.localFav.newValue
    if (changes.ui) uiTheme = applyTheme(changes.ui.newValue && changes.ui.newValue.theme)
    if (changes.auth) {
      auth = changes.auth.newValue
      renderAuth()
      // 登录态变化后收藏夹列表跟着刷新（登录成功 → 自动拉一次；登出 → 清空展示）
      if (auth && auth.loggedIn) {
        if (folders.length === 0) loadFolders()
      } else {
        folders = []
        renderFolders()
      }
    }
    renderNow()
    renderQueue()
    renderLocalFav()
  })

  // 进度显示本地外推（500ms 心跳）：storage 里的 position 是节流落盘的采样点，
  // 靠它驱动显示会「5 秒一跳」；外推基线由上面的 onChanged 每次落盘刷新。
  // 后台标签页计时器被节流也没关系——落盘事件仍会触发 renderNow 兜底刷新
  startProgressTicker(renderNpProgress)

  // 扫码进度不在 storage 里（转瞬即变），走广播
  onBroadcast((msg) => {
    if (msg.ns === 'auth' && msg.type === 'state') applyQrState(msg.payload)
  })

  // popup 传过来的搜索词（标签页已开时走消息，新开时走 URL）
  chrome.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.target !== 'page' || msg.ns !== 'nav' || msg.type !== 'search') return
    const q = msg.payload && msg.payload.query
    if (q) {
      $('q').value = q
      runSearch(q)
    }
  })

  const fromUrl = new URLSearchParams(location.search).get('q')
  if (fromUrl) {
    $('q').value = fromUrl
    switchTab('search')
    runSearch(fromUrl)
  } else {
    const saved = (all.ui && all.ui.lastTab) || 'search'
    switchTab(saved)
  }

  refreshAuth()
  if (auth && auth.loggedIn) loadFolders()

  // 扫码状态机跑在 service worker 里，关掉页面它还在轮询——
  // 重新打开要把二维码和进度接回来
  const st = await send('auth', 'state', {})
  if (st.ok && st.data && st.data.qrUrl && ['waiting', 'scanned', 'loading'].includes(st.data.status)) {
    showQr(st.data.qrUrl)
    applyQrState(st.data)
    $('btnStopQr').hidden = false
  }
}

init()
