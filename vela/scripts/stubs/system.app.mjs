/**
 * @system.app 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 语义对齐真机（文档 https://iot.mi.com/vela/quickapp/zh/features/basic/app.html）：
 *  - getInfo() 是**同步返回**接口（与 @system.device 的回调式 getInfo 不同），
 *    官方示例就是 `JSON.stringify(app.getInfo())` 直接取值；
 *  - 应用信息是「一个应用一份」的全局事实 —— 桩同样只有一份 state，
 *    换应用走 __setInfo()，不是每个调用者各拿一份；
 *  - 默认值刻意与 src/manifest.json 的字段错开一点点（name/versionName 同名同值，
 *    但通过 __setInfo 改一份就能看出页面显示的是原生值而不是写死的常量）。
 *
 * 三种模式（__setMode）覆盖真实世界里的三种可能：
 *  - 'ok'    正常返回信息            （新机型）
 *  - 'empty' 返回空对象              （老 runtime 字段全缺）
 *  - 'throw' getInfo 同步抛错        （老 runtime 根本没有这个模块）
 * 后两种都必须让 appService 退化成 available=false，不能把关于页拖挂。
 */

const DEFAULT_INFO = {
  packageName: 'github.naivg.bilimusic',
  name: 'bilimusic',
  versionName: '1.0.0',
  versionCode: 1,
  icon: '/common/logo.png',
  logLevel: 'log',
  source: {
    packageName: '',
    type: 'shortcut',
  },
}

function clone(info) {
  return Object.assign({}, info, {
    source: Object.assign({}, info && info.source),
  })
}

let state = clone(DEFAULT_INFO)
let mode = 'ok'
let callCount = 0

export function getInfo() {
  callCount++

  if (mode === 'throw') {
    throw new Error('[stub] system.app unavailable')
  }
  if (mode === 'empty') {
    return {}
  }

  // 快照：调用方可能马上改 state，不能让返回值跟着变
  return clone(state)
}

/* --------------------------- 测试专用入口 --------------------------- */

/** 换一份应用信息（只传要覆盖的字段） */
export function __setInfo(patch) {
  state = Object.assign({}, state, patch || {}, {
    source:
      patch && patch.source
        ? Object.assign({}, patch.source)
        : Object.assign({}, state.source),
  })
}

/** 'ok' | 'empty' | 'throw' */
export function __setMode(next) {
  mode = next
}

export function __state() {
  return clone(state)
}

/** getInfo 被真实调用了几次（验证 appService 的幂等缓存） */
export function __calls() {
  return callCount
}

export function __reset() {
  state = clone(DEFAULT_INFO)
  mode = 'ok'
  callCount = 0
}

// 默认导出就是快应用里 `import app from '@system.app'` 拿到的那个对象
export default { getInfo }
