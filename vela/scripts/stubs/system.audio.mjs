/**
 * @system.audio 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 刻意按**最坏语义**实现：全进程只有一份回调表，`audio.onxxx = fn` 是「后设置者覆盖」。
 * 本项目的绑定纪律（app VM 只绑控制类、主页 VM 只绑展示类，两边不重叠）
 * 只要在这种语义下成立，在「按 VM 实例分发」的真机语义下必然也成立；
 * 反过来若做成「每个 VM 各自一份回调」，就测不出两个 VM 抢同一属性这种事故。
 *
 * 另外它是全局单例状态（src/currentTime/duration/state），
 * 对应真机上 @system.audio 是全局原生播放器：任何 VM 都能读能控。
 */

const state = {
  src: '',
  currentTime: 0,
  duration: 0,
  volume: 1,
  loop: false,
  muted: false,
  state: 'stop', // play | pause | stop（与 getPlayState 的取值一致）
}

const handlers = {}
const durations = new Map()

const audio = {}

const EVENT_NAMES = [
  'onplay',
  'onpause',
  'onstop',
  'onloadeddata',
  'onended',
  'ondurationchange',
  'onerror',
  'ontimeupdate',
  'onprevious',
  'onnext',
]

EVENT_NAMES.forEach((name) => {
  Object.defineProperty(audio, name, {
    enumerable: true,
    configurable: true,
    get: () => handlers[name] || null,
    set: (fn) => {
      handlers[name] = fn
    },
  })
})

Object.defineProperty(audio, 'src', {
  enumerable: true,
  get: () => state.src,
  set: (value) => {
    state.src = value || ''
    state.currentTime = 0
    state.duration = durations.has(state.src) ? durations.get(state.src) : 0
  },
})

Object.defineProperty(audio, 'currentTime', {
  enumerable: true,
  get: () => state.currentTime,
  set: (value) => {
    state.currentTime = Number(value) || 0
  },
})

Object.defineProperty(audio, 'duration', {
  enumerable: true,
  get: () => (state.duration > 0 ? state.duration : NaN),
})

Object.defineProperty(audio, 'volume', {
  enumerable: true,
  get: () => state.volume,
  set: (value) => {
    state.volume = Number(value)
  },
})

Object.defineProperty(audio, 'loop', {
  enumerable: true,
  get: () => state.loop,
  set: (value) => {
    state.loop = !!value
  },
})

audio.meta = null
audio.title = ''
audio.artist = ''
audio.cover = ''

export function play() {
  if (!state.src) return
  state.state = 'play'
  // 真机顺序：先 onloadeddata（首次拿到数据）再 onplay
  emit('onloadeddata')
  emit('onplay')
}

export function pause() {
  state.state = 'pause'
  emit('onpause')
}

export function stop() {
  state.state = 'stop'
  state.currentTime = 0
  emit('onstop')
}

export function getPlayState(obj) {
  const { success, fail } = obj || {}
  if (typeof success === 'function') {
    success({
      state: state.state,
      src: state.src,
      currentTime: state.state === 'stop' ? -1 : state.currentTime,
      percent: state.duration > 0 ? (state.currentTime / state.duration) * 100 : 0,
      autoplay: false,
      loop: state.loop,
      volume: state.volume,
      muted: state.muted,
      notificationVisible: true,
      duration: state.duration,
    })
  } else if (typeof fail === 'function') {
    fail(null, -1)
  }
}

function emit(name, arg) {
  const fn = handlers[name]
  if (typeof fn !== 'function') return
  // 原生事件都是异步派发的
  setTimeout(() => fn(arg), 0)
}

/* --------------------------- 测试专用入口 --------------------------- */

/** 手动触发一个原生事件（模拟系统行为：音频焦点被抢、通知栏按钮等） */
export function __emit(name, arg) {
  emit(name, arg)
}

/** 给某个 URL 预置时长，模拟真实音轨 */
export function __setDuration(src, seconds) {
  durations.set(src, seconds)
}

/** 推进播放位置并派发 ontimeupdate（4HZ 那条链路） */
export function __tick(seconds) {
  state.currentTime += seconds
  emit('ontimeupdate')
}

export function __state() {
  return Object.assign({}, state)
}

export function __handlers() {
  return handlers
}

export function __reset() {
  state.src = ''
  state.currentTime = 0
  state.duration = 0
  state.volume = 1
  state.loop = false
  state.state = 'stop'
  durations.clear()
  EVENT_NAMES.forEach((name) => {
    delete handlers[name]
  })
}

// 默认导出就是快应用里的 `import audio from '@system.audio'` 拿到的那个对象：
// 属性（含事件回调）与方法都挂在它身上
export default Object.assign(audio, { play, pause, stop, getPlayState })
