/**
 * @system.device 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 语义对齐真机：
 *  - getInfo 是**回调式**接口（官方没有 Promise 形态），成功/失败都异步派发；
 *  - 设备信息是「一台机器一份」的全局事实 —— 桩同样只有一份 state，
 *    换机器走 __setInfo()，不是每个调用者各拿一份；
 *  - 默认值取 Xiaomi Watch S4（圆屏 + 在白名单内），这样一次桩调用就能同时
 *    覆盖「圆屏安全区」和「封面背景图白名单」两条路径。
 *
 * 三种模式（__setMode）覆盖真实世界里的三种可能：
 *  - 'ok'    正常返回信息              （新机型）
 *  - 'fail'  调 fail 回调              （接口在、但取不到信息）
 *  - 'throw' getInfo 同步抛错          （老 runtime 根本没有这个模块 /
 *                                       manifest 漏声明 system.device）
 * 后两种都必须让 deviceService 退化成「矩形屏 + 不渲染背景图」，不能把页面拖挂。
 */

const DEFAULT_INFO = {
  brand: 'Xiaomi',
  manufacturer: 'Xiaomi',
  model: 'Xiaomi Watch S4',
  product: 's4',
  osType: 'Vela',
  deviceType: 'watch',
  screenShape: 'circle',
  screenWidth: 466,
  screenHeight: 466,
  screenDensity: 2,
  APILevel: 3,
}

let state = Object.assign({}, DEFAULT_INFO)
let mode = 'ok'
let callCount = 0

function later(fn) {
  if (typeof fn === 'function') setTimeout(fn, 0)
}

export function getInfo(obj) {
  const o = obj || {}
  callCount++

  if (mode === 'throw') {
    throw new Error('[stub] system.device unavailable')
  }

  if (mode === 'fail') {
    later(() => {
      if (typeof o.fail === 'function') o.fail({}, 200)
      if (typeof o.complete === 'function') o.complete()
    })
    return
  }

  // 快照：回调是异步派发的，不能在回调里再读一次 state
  // （否则测试中途换机器会把新机器的信息算到这次调用头上）
  const snapshot = Object.assign({}, state)
  later(() => {
    if (typeof o.success === 'function') o.success(snapshot)
    if (typeof o.complete === 'function') o.complete()
  })
}

/* --------------------------- 测试专用入口 --------------------------- */

/** 换一台机器（只传要覆盖的字段） */
export function __setInfo(patch) {
  state = Object.assign({}, state, patch || {})
}

/** 'ok' | 'fail' | 'throw' */
export function __setMode(next) {
  mode = next
}

export function __state() {
  return Object.assign({}, state)
}

/** getInfo 被真实调用了几次（验证 deviceService 的幂等缓存） */
export function __calls() {
  return callCount
}

export function __reset() {
  state = Object.assign({}, DEFAULT_INFO)
  mode = 'ok'
  callCount = 0
}

// 默认导出就是快应用里 `import device from '@system.device'` 拿到的那个对象
export default { getInfo }
