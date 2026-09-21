/**
 * 音量换算与步进（纯函数，不依赖 @system，可被 Node 单测覆盖）
 *
 * 音量的唯一真相是**系统媒体音量**（`@system.volume`，读写见 services/playerService.js），
 * 应用不自己存一份、也不写 `audio.volume`（它的默认值本来就是「当前系统媒体音量」）。
 * 本文件只放「0.0-1.0 ↔ 0-100 百分比」与音量页的步进规则，
 * 让 volume.ux 不留逻辑，也让 scripts/verify.mjs 能离线覆盖这段换算。
 */

/** 归一到 0.0-1.0；非法值（NaN / undefined）退化成 fallback */
export function clampVolume(value, fallback = 0) {
  const v = Number(value)
  if (!isFinite(v)) return fallback
  return Math.max(0, Math.min(1, v))
}

/** 0.0-1.0 → 0-100 整数百分比（UI 显示用） */
export function toPercent(value) {
  return Math.round(clampVolume(value) * 100)
}

/**
 * 音量页 +/- 的步进规则：
 *   -1：小于 10% 直接归零，否则减 10%
 *   +1：大于 90% 直接拉满，否则加 10%
 *
 * @param {number} percent 当前百分比（0-100）
 * @param {number} dir -1（减）或 +1（加）
 * @returns {number} 步进后的百分比，已夹在 0-100
 */
export function stepPercent(percent, dir) {
  const cur = Math.max(0, Math.min(100, Math.round(Number(percent) || 0)))
  const next = dir === -1 ? (cur < 10 ? 0 : cur - 10) : cur > 90 ? 100 : cur + 10
  return Math.max(0, Math.min(100, next))
}

export default {
  clampVolume,
  toPercent,
  stepPercent,
}
