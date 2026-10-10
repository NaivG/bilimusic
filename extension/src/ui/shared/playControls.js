/**
 * 播放控制按钮的共享形状：popup 与全页播放器同款同序
 *
 * 两页的播放控制条都是五个键，从左到右：循环模式 → 上一首 → 播放/暂停 → 下一首 → 收藏。
 * 「循环模式」的图标映射与档位轮转、「收藏」的状态判定与呈现都收在这里，
 * 页面只负责把自己的按钮 id 挂上来；上一首/播放/下一首三键两页本就一致，不在这里管。
 *
 * 本文件只做纯呈现，不碰 chrome.* —— 消息发送留在页面侧（verify.mjs 的接线
 * 核对只扫 popup.js / player.js / store.js），收藏状态判定依赖的曲目同一性
 * 来自 core/tracks.js（纯函数）。
 */

import { trackKey } from '../../core/tracks.js'

/** 循环三档的点击轮转顺序：不循环 → 列表循环 → 单曲循环 */
export const REPEAT_ORDER = ['off', 'all', 'one']

/** 循环三档在按钮上的呈现：all/one 亮主题色（accentText），one 另带角标「1」 */
export const REPEAT_ICONS = {
  off: { icon: 'fas fa-redo', label: '不循环', accent: false },
  all: { icon: 'fas fa-sync', label: '列表循环', accent: true },
  one: { icon: 'fas fa-redo', label: '单曲循环', accent: true },
}

/** 点一下切一档（off → all → one → off…）；未知值安全回到 off */
export function nextRepeat(mode) {
  const cur = REPEAT_ORDER.indexOf(mode || 'off')
  return REPEAT_ORDER[(cur + 1 + REPEAT_ORDER.length) % REPEAT_ORDER.length]
}

/**
 * 把循环模式画到按钮上：图标、单曲循环角标「1」、title、主题色。
 * 角标绝对定位于按钮右上角，按钮要有 position:relative 做锚（页面 CSS 给出）。
 * @param {HTMLButtonElement} btn
 * @param {string} repeat off|all|one
 */
export function applyRepeatButton(btn, repeat) {
  const meta = REPEAT_ICONS[repeat] || REPEAT_ICONS.off
  btn.innerHTML = `<i class="${meta.icon}"></i>` + (repeat === 'one' ? '<span class="oneMark">1</span>' : '')
  btn.classList.toggle('accentText', !!meta.accent)
  btn.title = `循环模式：${meta.label}`
}

/** 当前曲目是否已在本地收藏里（按曲目同一性 key 对，见 core/tracks.js） */
export function isLocalFav(localFav, track) {
  const key = trackKey(track)
  if (!key) return false
  const tracks = (localFav && localFav.tracks) || []
  return tracks.some((t) => t && t.key === key)
}

/**
 * 把收藏状态画到按钮上：已收藏实心 + 主题色，未收藏轮廓；没有当前曲目时禁用。
 * @param {HTMLButtonElement} btn
 * @param {boolean} faved 当前曲目已在本地收藏里
 * @param {boolean} disabled 没有当前曲目（空队列）
 */
export function applyFavButton(btn, faved, disabled) {
  btn.innerHTML = faved ? '<i class="fas fa-heart"></i>' : '<i class="far fa-heart"></i>'
  btn.classList.toggle('accentText', !!faved)
  btn.disabled = !!disabled
  btn.title = faved ? '取消收藏' : '收藏'
}

export default { REPEAT_ORDER, REPEAT_ICONS, nextRepeat, applyRepeatButton, isLocalFav, applyFavButton }
