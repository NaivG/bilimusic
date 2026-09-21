/**
 * 设备能力与屏幕安全区（纯函数，不 import 任何 @system.* 模块）
 *
 * 为什么用 @system.device 而不是 @media 媒体查询：
 *   1. 媒体查询是 APILevel 2+ 特性（width/height/pill-shaped 更是 3+），
 *      而 device.getInfo() 的 screenShape 没有 APILevel 门槛、
 *      device 接口本身也是快应用的基础能力；
 *   2. 官方《媒体查询》支持明细里，小米 S1 Pro / Redmi Watch 4 / 手环 8 Pro
 *      直接「不支持」—— 其中 S1 Pro 恰恰是圆屏，最需要安全区。
 *      靠 @media 做适配在这些机型上会静默失效，靠 JS 判定不会。
 *
 * 文档：
 *   设备信息 https://iot.mi.com/vela/quickapp/zh/features/basic/device.html
 *   媒体查询 https://iot.mi.com/vela/quickapp/zh/guide/framework/style/media-query.html
 *   多屏设计 https://iot.mi.com/vela/quickapp/zh/guide/design/multi-screens.html
 *   背景图样式 https://iot.mi.com/vela/quickapp/zh/components/general/background-img-styles.html
 */

/** 屏幕形状（取值与 @system.device.getInfo().screenShape 对齐） */
export const SHAPE_CIRCLE = 'circle'
export const SHAPE_RECT = 'rect'
export const SHAPE_PILL = 'pill-shaped'

/**
 * 圆屏安全区：内容收进「内接正方形」。
 * 内接正方形边长 = 直径 / √2 ≈ 0.7071·D，即内容宽度约 71%。
 * 官方多屏设计示例取的是 466 基准下左右各 80px（≈65.7%），更保守；
 * 这里用理论内接值 —— 既保证不越出圆弧，又不白扔屏幕。
 */
export const CIRCLE_SAFE_WIDTH_PERCENT = 71

/** 矩形屏内容宽度（%）：两侧各留 6%，纯属观感留白，不参与圆弧计算 */
export const RECT_SAFE_WIDTH_PERCENT = 88

/**
 * 各形状「左右安全内缩」占屏宽的比例 =（100% - 内容宽）/ 2：
 * 圆屏 14.5%、矩形屏 6%、胶囊屏 0（维持全宽）。
 */
export const SAFE_HORIZONTAL_INSET = {
  circle: (100 - CIRCLE_SAFE_WIDTH_PERCENT) / 200,
  rect: (100 - RECT_SAFE_WIDTH_PERCENT) / 200,
  'pill-shaped': 0,
}

/**
 * 拿不到 screenWidth 时的兜底基准宽。
 * 首帧按 480 × 6% ≈ 29px 内缩，和老版「矩形屏 88%」的首帧观感一致；
 * device.getInfo() 回来后页面会立刻用真实屏宽重算。
 */
const FALLBACK_SCREEN_WIDTH = 480

/**
 * 为什么安全区是「px 内缩」而不是「百分比宽度盒子」：
 *
 *   「百分比宽 + 交叉轴居中」的盒子在 Vela 渲染层不可靠：给 .safe 挂 width: 71%
 *   再靠页面根节点的 align-items: center 居中，渲染出来是**左锚定**的 ——
 *   右边组件被收进到 71% 处（视觉上挤到中间），左边却贴着屏幕边缘。
 *
 *   现在的方案让对称性**由构造保证**：.safe 保持 width: 100%，左右各内缩同一
 *   个 px 值 —— 不经过 flex 对齐、也不依赖百分比宽度的解析，左右必然对称。
 *
 *   px 在这里是精确的而不是近似：
 *   - manifest 的 config.designWidth = "device-width"，style 里的 px 与物理像素
 *     1:1（getInfo 把 screenWidth 交到手里，换算就不成问题）；
 *   - px 数值 = round(screenWidth × 内缩比例)，每台机器各自算各自的。
 */
export function safeHorizontalInsetPx(info) {
  const i = info || {}
  const shape = resolveScreenShape(i)
  const ratio =
    SAFE_HORIZONTAL_INSET[shape] !== undefined
      ? SAFE_HORIZONTAL_INSET[shape]
      : SAFE_HORIZONTAL_INSET.rect
  const width = asNumber(i.screenWidth) > 0 ? asNumber(i.screenWidth) : FALLBACK_SCREEN_WIDTH
  return Math.round(width * ratio)
}

/**
 * 「封面背景图」机型白名单
 *
 * 依据官方《背景图样式》支持明细：
 *   支持   ：小米手环 10 / Xiaomi Watch S4 / REDMI Watch 5 / REDMI Watch 6 / Xiaomi Watch S5
 *   不支持 ：小米 S1 Pro 运动健康手表 / 小米手环 8 Pro / 小米手环 9 / 9 Pro /
 *            Xiaomi Watch S3 / Redmi Watch 4 / 小米腕部心电血压记录仪
 *
 * 语义是**白名单**（fail-closed）：没命中就不渲染背景层，宁可纯黑底，
 * 也不要在不支持的机型上糊一屏铺不满/破图的封面。
 *
 * 两个实现细节：
 *   1. device.getInfo() 的 model / product 各机型字符串不统一（中英文、代号混用），
 *      所以 token 先做「去空白/连字符 + 转小写」归一，再按**包含**匹配；
 *   2. 归一后**逐字段**匹配（brand / manufacturer / model / product 各自比一遍），
 *      不是拼成一整串 —— 否则 "Redmi" + "Xiaomi" + "Watch 5" 拼起来会把
 *      `redmiwatch5` 这种跨字段 token 冲散。
 *
 * 新机型适配：把它的品牌+代次片段加进 tokens 即可（离线自检覆盖白名单语义）。
 */
export const COVER_BACKGROUND_DEVICES = [
  { name: 'Xiaomi Watch S4 / S4 Sport', tokens: ['watchs4'] },
  { name: 'Xiaomi Watch S5', tokens: ['watchs5'] },
  { name: 'REDMI Watch 5', tokens: ['redmiwatch5', 'watch5'] },
  { name: 'REDMI Watch 6', tokens: ['redmiwatch6', 'watch6'] },
  { name: '小米手环 10', tokens: ['band10', '手环10', 'smartband10'] },
  { name: 'Emulator', tokens: ['Emulator-Vela','Emulator','emulator']} // 添加模拟器支持
]

/**
 * 封面缩略图后缀。
 *
 * B 站图片 CDN 支持 `@<宽>w_<高>h_<裁切>.jpg` 形式的处理参数；
 * 手表铺个背景没必要拉原图（封面原图 672×378 起步）。
 *
 */
export const COVER_THUMB_SUFFIX = '@480w_480h_1c.jpg'

/* ------------------------------ 归一化 ------------------------------ */

function asString(v) {
  return v === undefined || v === null ? '' : String(v)
}

function asNumber(v) {
  const n = Number(v)
  return isFinite(n) ? n : 0
}

/** 归一化 token：去掉空白与常见分隔符并转小写（"Watch S4 Sport" -> "watchs4sport"） */
export function normalizeToken(v) {
  return asString(v)
    .toLowerCase()
    .replace(/[\s\-_/|]+/g, '')
}

/**
 * 把 device.getInfo() 的返回值归一化成固定形状。
 *
 * 容忍三种情况：字段缺失（老 runtime）、类型不对、整个 getInfo 失败（传 null）。
 * `available` 是给调用方判断「到底拿没拿到设备信息」用的 —— 没拿到时页面
 * 一律走保守分支（矩形屏 + 不渲染背景图）。
 */
export function normalizeDeviceInfo(raw) {
  const r = raw && typeof raw === 'object' ? raw : {}
  return {
    available: !!(raw && typeof raw === 'object'),
    brand: asString(r.brand),
    manufacturer: asString(r.manufacturer),
    model: asString(r.model),
    product: asString(r.product),
    deviceType: asString(r.deviceType),
    screenShape: asString(r.screenShape).toLowerCase(),
    screenWidth: asNumber(r.screenWidth),
    screenHeight: asNumber(r.screenHeight),
    screenDensity: asNumber(r.screenDensity),
    apiLevel: asNumber(r.APILevel),
  }
}

/* ------------------------------ 屏幕形状 ------------------------------ */

/**
 * 判定屏幕形状：优先用原生 screenShape，缺失时按宽高比兜底。
 *
 * 兜底阈值来自官方多屏设计数据：
 *   圆屏 W/H = 1；矩形屏 0.5 <= W/H < 1（Redmi Watch 5 是 432/514 = 0.84）；
 *   胶囊屏 0.3 < W/H < 0.5（手环 9 是 192/490 = 0.39，手环 10 是 212/520 = 0.41）。
 * 取 0.9 作为「够圆」的门限：比 0.84 留了余量，又不会把矩形屏误判成圆屏。
 */
export function resolveScreenShape(info) {
  const i = info || {}
  const declared = asString(i.screenShape).toLowerCase()
  if (
    declared === SHAPE_CIRCLE ||
    declared === SHAPE_RECT ||
    declared === SHAPE_PILL
  ) {
    return declared
  }

  const w = asNumber(i.screenWidth)
  const h = asNumber(i.screenHeight)
  if (w <= 0 || h <= 0) return SHAPE_RECT

  const ratio = w / h
  if (ratio >= 0.9) return SHAPE_CIRCLE
  if (ratio <= 0.5) return SHAPE_PILL
  return SHAPE_RECT
}

/**
 * 页面根节点上的形状 class（`.shape-circle` / `.shape-rect` / `.shape-pill`）。
 *
 * 注意：安全区宽度已经不走这个 class 了（见 safeHorizontalInsetPx 的说明——
 * 百分比宽 + 交叉轴居中在渲染层不可靠）。现在它只作为形状的**摘要值**存在，
 * 给 deviceService.capabilities() / 日志 / 离线校验用。
 */
export function shapeClassOf(info) {
  const shape = resolveScreenShape(info)
  if (shape === SHAPE_CIRCLE) return 'shape-circle'
  if (shape === SHAPE_PILL) return 'shape-pill'
  return 'shape-rect'
}

/* ------------------------------ 背景图白名单 ------------------------------ */

/**
 * 该机型是否在白名单内（fail-closed：没拿到信息 / 不认识 = false）
 *
 * @param {object} info normalizeDeviceInfo 的结果
 */
export function supportsCoverBackground(info) {
  const i = info || {}
  const fields = [i.brand, i.manufacturer, i.model, i.product]
    .map(normalizeToken)
    .filter((f) => f.length > 0)
  if (!fields.length) return false

  return COVER_BACKGROUND_DEVICES.some((device) =>
    device.tokens.some((token) => fields.some((field) => field.indexOf(token) >= 0))
  )
}

/** 命中的白名单条目名（打日志用，未命中返回 ''） */
export function matchedCoverDevice(info) {
  const i = info || {}
  const fields = [i.brand, i.manufacturer, i.model, i.product]
    .map(normalizeToken)
    .filter((f) => f.length > 0)

  const hit = COVER_BACKGROUND_DEVICES.find((device) =>
    device.tokens.some((token) => fields.some((field) => field.indexOf(token) >= 0))
  )
  return hit ? hit.name : ''
}

/* ------------------------------ 封面地址 ------------------------------ */

/**
 * 归一化封面地址（给 <image> 组件当 src 用）
 *
 *   - B 站返回的 pic 常是协议相对地址（`//i2.hdslb.com/...`），补 https；
 *   - 顺手把 http 升到 https（Vela 运行时可能不允许明文）；
 *   - 追加缩略图参数，别为了一块被压暗的背景拉原图；
 *   - 非 http(s) 的一律返回空串 —— 调用方据此不渲染背景层。
 *
 * @returns {string} 可用的 https 地址，或 ''（不可用）
 */
export function normalizeCoverUrl(raw) {
  let url = asString(raw).trim()
  if (!url) return ''

  if (url.indexOf('//') === 0) url = 'https:' + url
  else if (url.indexOf('http://') === 0) url = 'https://' + url.slice(7)

  if (url.indexOf('https://') !== 0) return ''

  // 已经带过 B 站图片处理参数（@数字）就不重复追加
  if (!/@\d/.test(url)) url += COVER_THUMB_SUFFIX
  return url
}
