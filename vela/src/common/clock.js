/**
 * 时间展示（纯函数，不 import 任何 @system.* 模块，可被 Node 单测）
 *
 * 主页播放器标题上方那行小字时间（player.ux 的 .clock-row）用它拼串。
 *
 * 为什么入参是 Date 实例而不是时间戳：既省掉调用方的时间戳换算，也让纯函数在
 * Node 里能用固定时刻断言（`new Date(2026, 0, 5, 9, 7)`）。
 * 
 */

/** 星期中文（0=周日，与 Date#getDay() 对齐） */
export const WEEKDAY_LABELS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

function pad2(n) {
  return n < 10 ? '0' + n : String(n)
}

/**
 * 把时刻拆成展示片段，字段全部是**已补零的字符串**。
 *
 *   - 传进来的不是合法 Date（`new Date('x')`、空值、别的类型）→ 所有字段为 ''，
 *     调用方据此不渲染那一行，不显示 `NaN:NaN`；
 *   - 小时 / 分钟 / 秒一律两位（`9:07` → `09:07`），月 / 日不补零（`9月5日`）；
 *   - 年 → 月 → 日 → 星期，中间用空格分隔。
 *
 * @param {Date} date 已构造好的时刻（页面侧 `new Date()` 取当前时间）
 * @returns {{valid: boolean, time: string, date: string, weekday: string, text: string}}
 */
export function formatClockParts(date) {
  const invalid = { valid: false, time: '', date: '', weekday: '', text: '' }
  if (!(date instanceof Date)) return invalid
  const t = date.getTime()
  if (!isFinite(t)) return invalid

  const hhmm = pad2(date.getHours()) + ':' + pad2(date.getMinutes())
  const weekday = WEEKDAY_LABELS[date.getDay()]
  const dateText =
    date.getFullYear() +
    '年' +
    (date.getMonth() + 1) +
    '月' +
    date.getDate() +
    '日 ' +
    weekday

  return {
    valid: true,
    // 秒不进展示串：主页这行是给「协调布局」的小字，秒级跳动纯属噪音
    // （定时器仍按 1 秒对账，见 player.ux 的 startClock —— 展示串变了才会重绘）
    time: hhmm,
    date: dateText,
    weekday,
    text: hhmm + ' ' + dateText,
  }
}

/**
 * 只要一行展示串的便捷包装（`14:05 2026年1月5日 周一`，见 formatClockParts.text）；
 * 拿不到合法时刻返回 ''。
 *
 * @param {Date} date
 * @returns {string}
 */
export function formatClock(date) {
  return formatClockParts(date).text
}
