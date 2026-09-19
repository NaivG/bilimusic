/**
 * @system.storage 的 Node 桩（仅供 scripts/verify.mjs 离线测试）
 *
 * 语义要点：**进程内共享一份 KV** —— 对应真机上 storage 是全局原生服务，
 * 各 page VM 读到的都是同一份数据（这也是跨 VM 状态同步唯一的通道）。
 * 异步回调用 setTimeout 模拟原生 IPC，保证被测代码里的 await 顺序与真机一致。
 */

const store = new Map()

function finish(success, complete, value) {
  setTimeout(() => {
    if (typeof success === 'function') success(value)
    if (typeof complete === 'function') complete()
  }, 0)
}

export function get(obj) {
  const { key, default: dft = '', success, complete } = obj || {}
  const value = store.has(key) ? store.get(key) : dft
  finish(success, complete, value)
}

export function set(obj) {
  const { key, value, success, complete } = obj || {}
  // 真机语义：写入空字符串等于删除该数据项
  if (value === undefined || value === '') store.delete(key)
  else store.set(key, String(value))
  finish(success, complete)
}

function remove(obj) {
  const { key, success, complete } = obj || {}
  store.delete(key)
  finish(success, complete)
}

export function clear(obj) {
  const { success, complete } = obj || {}
  store.clear()
  finish(success, complete)
}

export function key(obj) {
  const { index, success, complete } = obj || {}
  const keys = Array.from(store.keys())
  finish(success, complete, keys[index])
}

export function __reset() {
  store.clear()
}

/** 预置 KV（测试里造「上次已保存的登录态」用） */
export function __seed(map) {
  Object.keys(map || {}).forEach((k) => store.set(k, String(map[k])))
}

export function __dump() {
  const out = {}
  store.forEach((v, k) => {
    out[k] = v
  })
  return out
}

export { remove as delete }

export default { get, set, delete: remove, clear, key }
