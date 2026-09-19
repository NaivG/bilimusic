/**
 * @system.volume 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 语义对齐真机：
 *  - 系统媒体音量是**全进程唯一**的一份（音量子系统），任何 VM 读到的都是同一个数 ——
 *    这正是「与外部音量保持一致」的依据，桩必须同样只有一份 state；
 *  - `onMediaValueChanged` 只有一个回调槽，后设置者覆盖（与 system.audio 桩同样的
 *    最坏语义），这样「两个 VM 抢同一个原生事件」这类事故在离线测试里就能暴露；
 *  - 原生回调都是异步派发的（统一走 setTimeout 0）。
 *
 * `__setMediaValue()` 是**测试专用**入口，模拟外部改音量（实体键 / 系统设置 /
 * 别的应用）——它和 setMediaValue 一样会派发 onMediaValueChanged。
 */

const state = {
  value: 1, // 系统媒体音量 0.0-1.0
}

let handler = null

const volume = {}

Object.defineProperty(volume, 'onMediaValueChanged', {
  enumerable: true,
  configurable: true,
  get: () => handler,
  set: (fn) => {
    handler = fn
  },
})

function clamp(v) {
  const n = Number(v)
  if (!isFinite(n)) return state.value
  return Math.max(0, Math.min(1, n))
}

function later(fn) {
  if (typeof fn === 'function') setTimeout(fn, 0)
}

function dispatch(value) {
  // 事件携带的是「变化发生那一刻」的音量：回调是异步派发的，
  // 不能在回调里再读一次 state（那样会把之后的变化算到这次事件头上）
  const v = clamp(value === undefined ? state.value : value)
  later(() => {
    if (typeof handler === 'function') handler({ value: v })
  })
}

export function getMediaValue(obj) {
  const o = obj || {}
  later(() => {
    if (typeof o.success === 'function') o.success({ value: state.value })
    if (typeof o.complete === 'function') o.complete()
  })
}

export function setMediaValue(obj) {
  const o = obj || {}
  const next = clamp(o.value)
  const changed = next !== state.value
  state.value = next
  later(() => {
    if (typeof o.success === 'function') o.success()
    if (typeof o.complete === 'function') o.complete()
  })
  if (changed) dispatch(next)
}

/* --------------------------- 测试专用入口 --------------------------- */

/** 模拟外部（实体键 / 系统设置）把音量改成 v */
export function __setMediaValue(v) {
  const next = clamp(v)
  const changed = next !== state.value
  state.value = next
  if (changed) dispatch(next)
}

export function __state() {
  return Object.assign({}, state)
}

export function __handler() {
  return handler
}

export function __reset() {
  state.value = 1
  handler = null
}

// 默认导出就是快应用里 `import volume from '@system.volume'` 拿到的那个对象：
// 事件回调挂在它身上，方法也在它身上
export default Object.assign(volume, { getMediaValue, setMediaValue })
