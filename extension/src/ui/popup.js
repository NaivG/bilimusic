/**
 * Popup：精简播控 + 队列
 *
 * 关掉 popup 不影响播放——播放宿主在 offscreen，UI 只是指令的发送端。
 * 状态一律从 chrome.storage 读（onChanged 订阅），不直接连播放宿主。
 */

import { send, watchStorage, readAll, fmtTime, esc, applyTheme, displayPosition, startProgressTicker } from './shared/store.js'
import { applyRepeatButton, applyFavButton, isLocalFav, nextRepeat } from './shared/playControls.js'

const $ = (id) => document.getElementById(id)

let playback = null
let settings = null
let localFav = { tracks: [] }
let dragging = false
// 队列上一次渲染出来的签名：位置是节流落盘的，不比对就会每次心跳重建 DOM、
// 把用户的滚动位置和 hover 一起冲掉
let queueSig = null

/* ------------------------------------------------------------ 渲染 */

/**
 * MD3 滑块的「已走过的那段」画在轨道渐变上（--pos，见 popup.css 的滑块一节），
 * daisyUI 那套挂在滑块上的阴影填充（--range-fill-*）在 popup.css 里已清零。
 * 唯一的写入口就是这个函数。
 */
function setRangePos(el, pct) {
  const v = Math.max(0, Math.min(100, Number(pct) || 0))
  el.style.setProperty('--pos', `${v}%`)
}

function render() {
  const p = playback
  const track = p && p.queue && p.queue[p.index]

  // 队列先画：空队列也是它负责表达，且下面这条分支会提前 return
  renderQueue()

  // 播放控制条与全页播放器同款（shared/playControls.js 出形状）：
  // 循环模式是全局设置，不看当前曲目，空队列也照常显示；
  // 收藏键跟当前曲目走，没有曲目就禁用
  applyRepeatButton($('repeat'), (settings && settings.repeat) || 'off')
  applyFavButton($('fav'), isLocalFav(localFav, track), !track)

  if (!track) {
    $('title').textContent = '未在播放'
    $('artist').textContent = '展开右上角全页搜索'
    $('cover').removeAttribute('src')
    $('cur').textContent = '0:00'
    $('dur').textContent = '0:00'
    $('seek').value = 0
    setRangePos($('seek'), 0)
    $('toggle').innerHTML = '<i class="fas fa-play"></i>'
    $('toggle').disabled = false
    $('status').textContent = ''
    return
  }

  $('title').textContent = track.title || '未知标题'
  $('artist').textContent = track.artist || ''
  $('artist').title = track.artist || ''

  const cover = track.cover || ''
  if (cover) {
    $('cover').src = cover
    $('cover').alt = track.title || ''
  } else {
    $('cover').removeAttribute('src')
  }

  const isPlaying = p.state === 'playing'
  const isLoading = p.state === 'loading'
  $('toggle').innerHTML = isLoading
    ? '<i class="fas fa-circle-notch fa-spin"></i>'
    : isPlaying
      ? '<i class="fas fa-pause"></i>'
      : '<i class="fas fa-play"></i>'
  $('toggle').disabled = isLoading
  $('toggle').title = isLoading ? '加载中' : isPlaying ? '暂停' : '播放'

  renderProgress()

  // 状态行只报错误：「已暂停 / 空闲 / 播放结束」由播放键的图标与队列列表表达，
  // 写在卡片底部只是白白占一行高度（空的时候这行整条塌掉，见 popup.css）
  const pos = $('status')
  if (p.state === 'error' && p.error) {
    pos.textContent = p.error
    pos.className = 'statusLine error'
  } else {
    pos.textContent = ''
    pos.className = 'statusLine'
  }
}

/**
 * 队列列表：行点播、× 移出。
 *
 * 只有签名变了才重画 —— 进度落盘 / 音量变化都会触发 render()，无脑重建 innerHTML
 * 会把滚动位置弹回顶部。签名里有 index，所以「换曲」照样会重画并把当前行滚进视野。
 */
function renderQueue() {
  const p = playback
  const queue = (p && p.queue) || []
  const index = p ? p.index : -1

  $('queueCount').textContent = queue.length ? `${queue.length} 首 · 第 ${index + 1} 首` : '队列为空'
  $('clearQueue').disabled = queue.length === 0

  const sig = `${index}|${queue.map((t) => `${t.bvid || ''}:${t.title || ''}`).join('|')}`
  if (sig === queueSig) return
  queueSig = sig

  const box = $('queueList')
  if (!queue.length) {
    box.innerHTML = '<div class="queueEmpty">队列为空 · 右上角展开全页搜索</div>'
    return
  }

  box.innerHTML = queue
    .map(
      (t, i) =>
        `<div class="qrow${i === index ? ' current' : ''}" data-idx="${i}">` +
        (t.cover ? `<img class="qcover" src="${esc(t.cover)}" loading="lazy" alt="">` : '<div class="qcover"><i class="fas fa-music"></i></div>') +
        `<div class="qmeta"><div class="qtitle">${esc(t.title || '未知标题')}</div>` +
        `<div class="qsub">${esc(t.artist || '')}</div></div>` +
        `<div class="qact"><button data-act="remove" title="移出队列" class="btn btn-ghost btn-xs btn-circle"><i class="fas fa-times"></i></button></div></div>`
    )
    .join('')

  const cur = box.querySelector('.qrow.current')
  if (cur) cur.scrollIntoView({ block: 'nearest' })
}

/**
 * 进度行（cur/dur/seek）：值来自 displayPosition 的本地外推，两次落盘之间
 * 也走得动（见 store.js）。render() 与 startProgressTicker 的心跳共用这一份；
 * 队列为空时什么都不做，空态文案由 render() 负责。
 */
function renderProgress() {
  const p = playback
  if (!p || !p.queue || !p.queue[p.index]) return
  const dur = p.duration || 0
  const pos = displayPosition(p)
  $('cur').textContent = fmtTime(pos)
  $('dur').textContent = fmtTime(dur)
  if (!dragging) {
    $('seek').value = dur > 0 ? Math.round((pos / dur) * 1000) : 0
    $('seek').disabled = dur <= 0
    setRangePos($('seek'), dur > 0 ? (pos / dur) * 100 : 0)
  }
}

function renderSettings() {
  if (!settings) return
  const vol = Math.round(((playback && playback.volume) || 1) * 100)
  $('volume').value = vol
  setRangePos($('volume'), vol)
}

/* ------------------------------------------------------------ 事件 */

function cmd(action, payload) {
  send('player', 'command', { action, ...payload })
}

$('toggle').addEventListener('click', () => cmd('toggle'))
$('prev').addEventListener('click', () => cmd('prev'))
$('next').addEventListener('click', () => cmd('next'))

// 循环模式：点一下切一档（off → all → one），与全页播放器同款；落盘到 settings，
// 全页播放器顶栏与设置页的下拉都会跟着变
$('repeat').addEventListener('click', () => {
  send('settings', 'set', { repeat: nextRepeat(settings && settings.repeat) })
})

// 收藏：切当前曲目的本地收藏（与全页播放器、本地收藏页同一份表）
$('fav').addEventListener('click', async () => {
  const p = playback
  const track = p && p.queue && p.queue[p.index]
  if (!track) return
  const r = await send('fav', 'localToggle', { track })
  if (r.ok && r.data) {
    localFav = { tracks: r.data.tracks }
    render()
  }
})

$('seek').addEventListener('pointerdown', () => {
  dragging = true
})
$('seek').addEventListener('input', () => {
  const p = playback
  if (!p || !p.duration) return
  const t = (Number($('seek').value) / 1000) * p.duration
  $('cur').textContent = fmtTime(t)
  setRangePos($('seek'), Number($('seek').value) / 10)
})
$('seek').addEventListener('change', () => {
  dragging = false
  const p = playback
  if (!p || !p.duration) return
  cmd('seek', { time: (Number($('seek').value) / 1000) * p.duration })
})

// 音量用 input 实时生效（本地），change 时才落盘
$('volume').addEventListener('input', () => {
  const vol = Number($('volume').value)
  setRangePos($('volume'), vol)
  cmd('setVolume', { volume: vol / 100 })
})

// 队列行：点歌区与操作按钮是兄弟节点，不嵌套点击
$('queueList').addEventListener('click', async (e) => {
  const row = e.target.closest('.qrow')
  if (!row) return
  const act = e.target.closest('button[data-act]')
  const idx = Number(row.dataset.idx)
  const p = playback
  if (!p || !p.queue || !p.queue[idx]) return
  if (act && act.dataset.act === 'remove') {
    await cmd('removeAt', { index: idx })
    return
  }
  await cmd('playTrack', { track: p.queue[idx] })
})

$('clearQueue').addEventListener('click', async (e) => {
  e.preventDefault()
  await cmd('setQueue', { queue: [], index: 0, autoplay: false })
})

$('expand').addEventListener('click', async (e) => {
  e.preventDefault()
  await send('ui', 'openPlayer', {})
  window.close()
})

/* ------------------------------------------------------------ 启动 */

async function init() {
  const all = await readAll()
  playback = all.playback
  settings = all.settings
  localFav = all.localFav || { tracks: [] }
  applyTheme(all.ui && all.ui.theme)
  render()
  renderSettings()

  watchStorage((changes) => {
    if (changes.playback) playback = changes.playback.newValue
    if (changes.settings) settings = changes.settings.newValue
    if (changes.localFav) localFav = changes.localFav.newValue
    // 主题在「我的」页换，popup 跟着变
    if (changes.ui) applyTheme(changes.ui.newValue && changes.ui.newValue.theme)
    render()
    renderSettings()
  })
  // 这里不做「有队列就自动 play」：打开 popup 是查看动作，不该自己出声。

  // 进度显示本地外推（500ms 心跳）：storage 里的 position 是节流落盘的采样点，
  // 靠它驱动显示会「5 秒一跳」；外推基线由上面的 onChanged 每次落盘刷新
  startProgressTicker(renderProgress)
}

init()
