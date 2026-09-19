/**
 * 应用信息（@system.app 的 getInfo() 返回值）—— 纯函数，不 import 任何 @system.* 模块
 *
 * 文档：https://iot.mi.com/vela/quickapp/zh/features/basic/app.html
 *   app.getInfo() 返回 { packageName, icon, name, versionName, versionCode,
 *                        logLevel, source: { packageName, type } }
 *   官方标注「接口声明：无需声明」（运行时不声明也能用），但 aiot build 要求
 *   源码里用到的 @system.* 必须在 manifest.features 里出现，否则报 missing feature
 *   —— 所以 manifest 里有 system.app，别照着文档把它删掉。
 *
 * 关于页要显示的东西**一律来自原生**，页面里不写死包名/版本号：
 * 这一层负责把原生返回值归一化成固定形状（字段缺失、类型不对、整个接口不可用
 * 三种情况都要能兜住），页面只负责绑定。
 */

/* ------------------------------ 归一化 ------------------------------ */

function asString(v) {
  return v === undefined || v === null ? '' : String(v)
}

function asInteger(v) {
  const n = Number(v)
  return isFinite(n) ? Math.floor(n) : 0
}

/**
 * 把 app.getInfo() 的返回值归一化成固定形状。
 *
 * 容忍三种情况：字段缺失（老 runtime）、类型不对、整个 getInfo 失败（传 null）。
 * `available` 是给调用方判断「到底拿没拿到应用信息」用的 —— 没拿到时页面
 * 一律走「读取失败」分支，不去猜包名和版本。
 *
 * `available` 的判据是「里面确实有能显示的东西」：返回空对象（`{}`）也算失败。
 * 与 @system.device 那边「拿到对象就算 available」不同 —— 设备信息即使字段全空，
 * 保守结论（矩形屏 + 不渲染背景图）本身是可用的；而关于页没有值就没有内容可显示，
 * 让它继续走成功分支只会渲染出一屏空白。
 */
export function normalizeAppInfo(raw) {
  const r = raw && typeof raw === 'object' ? raw : {}
  const source = r.source && typeof r.source === 'object' ? r.source : {}

  const packageName = asString(r.packageName)
  const name = asString(r.name)
  const versionName = asString(r.versionName)
  const versionCode = asInteger(r.versionCode)
  const icon = asString(r.icon)

  return {
    available: !!(packageName || name || versionName || versionCode > 0 || icon),
    packageName,
    name,
    versionName,
    versionCode,
    icon,
    logLevel: asString(r.logLevel),
    // 二级来源：source.packageName 是「来源 app 的包名」，一级来源
    sourcePackage: asString(source.packageName),
    sourceType: asString(source.type).toLowerCase(),
  }
}

/* ------------------------------ 展示值 ------------------------------ */

/**
 * 版本号展示串：`1.0.0 (1)`。
 *
 *   - versionName 与 versionCode 都在 → `1.0.0 (1)`
 *   - 只有 versionName（老 runtime 不给 versionCode）→ `1.0.0`
 *   - 只有 versionCode → `1`
 *   - 都没有 → ''（调用方据此不渲染版本行）
 *
 * versionCode <= 0 视为「没给」（0 不是合法构建号，出现即说明字段缺失/类型不对），
 * 不显示成 `1.0.0 (0)`。
 *
 * @param {object} info normalizeAppInfo 的结果
 * @returns {string}
 */
export function formatAppVersion(info) {
  const i = info || {}
  const versionName = asString(i.versionName)
  const versionCode = asInteger(i.versionCode)
  if (versionName && versionCode > 0) return versionName + ' (' + versionCode + ')'
  if (versionName) return versionName
  if (versionCode > 0) return String(versionCode)
  return ''
}

/**
 * 启动来源类型的中文说明（source.type，见官方文档「入参格式」下的 source 小节）。
 *
 * 未知取值**原样透传**而不是显示「未知」：宁可露出原生值，也不吞掉信息
 * （新 runtime 可能会加枚举值）。
 */
export const APP_SOURCE_LABELS = {
  shortcut: '桌面快捷方式',
  push: '推送唤起',
  url: '链接唤起',
  barcode: '扫码唤起',
  nfc: 'NFC 唤起',
  bluetooth: '蓝牙唤起',
  other: '其它入口',
}

/**
 * @param {string} type source.type
 * @returns {string} 中文说明；空值返回 ''（调用方据此不渲染该行）
 */
export function describeAppSource(type) {
  const key = asString(type).toLowerCase()
  if (!key) return ''
  return APP_SOURCE_LABELS[key] || key
}
