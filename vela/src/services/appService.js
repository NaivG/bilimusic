import app from '@system.app'
import { formatAppVersion, normalizeAppInfo } from '../common/appinfo'

/**
 * 应用信息（@system.app）—— 关于页的唯一数据来源
 *
 * 语义与 @system.app 的关系：
 *   - getInfo() 是**同步返回**接口（与 @system.device 的回调式 getInfo 不同），
 *     拿到就是拿到，不需要 deviceService 那样的 whenReady() Promise；
 *   - 老 runtime / 异常环境下整个模块可能取不到（或没有 getInfo 方法），
 *     所以调用一律包 try/catch，失败退化成 available=false，绝不把页面拖挂；
 *   - 每个 page 一个独立 JS VM，模块级缓存**不跨页共享**，所以每页各自读一次。
 *     应用信息在一次运行里不会变，同一个 VM 内只问一次原生（幂等）。
 *
 * 为什么这里是顶层 `import`：@system.app 是快应用的基础能力，import 不会失败；
 * getInfo 调用本身仍然包了 try/catch（老 runtime 可能没有这个方法）。
 *
 * 分层：页面只消费本服务，不直接 import '@system.app' —— 与 volume.ux 走
 * playerService 读音量是同一条纪律（页面里出现原生 import 就是漏层了）。
 */

/** 没读到应用信息时的结论：available=false，各字段为空串 */
const FALLBACK = normalizeAppInfo(null)

let cached = null

/**
 * 读应用信息（首次调用真的问一次原生，之后走缓存）
 * @returns {object} normalizeAppInfo 的结果，永不抛错
 */
export function info() {
  if (cached) return cached

  let raw = null
  try {
    raw = app.getInfo()
  } catch (e) {
    console.warn('[App] getInfo 不可用:', e)
  }

  const normalized = normalizeAppInfo(raw)
  if (normalized.available) {
    console.log(
      '[App]',
      normalized.packageName || '(无包名)',
      normalized.name || '(无名称)',
      formatAppVersion(normalized) || '(无版本)'
    )
  } else {
    console.warn('[App] 未取到应用信息，关于页按「读取失败」显示')
  }

  cached = normalized
  return cached
}

/** 最近一次结果（同步读，未读过时是兜底值） */
export function getCached() {
  return cached || FALLBACK
}

/** 测试用：清掉缓存 */
export function reset() {
  cached = null
}

export default {
  info,
  getCached,
  reset,
}
