#!/usr/bin/env node
/**
 * 生成 MD3（Material Design 3）设计令牌 → src/ui/md3.tokens.css
 *
 * 色彩空间：OKLab / OKLCh（Björn Ottosson）。MD3 官方用的是 HCT，两者在
 * 「音调 = CIE L*」这条上是相通的：音调 T 的灰 = Y = f(T) 的灰，而 OKLab 的
 * 亮度 L = Y^(1/3)，于是 L_ok = ((L* + 16) / 116) 可直接换算。
 * 色度（chroma）按音调走一条钟形曲线（40–60 档最艳、两端收干），并在超出
 * sRGB 色域时二分收色度——和 HCT 音调板的行为一致。
 *
 * 用法：
 *
 *   node extension/scripts/gen_md3_tokens.mjs
 *
 * 改种子色 / 改角色映射后重跑。
 */

import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const OUT = fileURLToPath(new URL('../src/ui/md3.tokens.css', import.meta.url))

/* ------------------------------------------------------------ 色彩空间 */

/** sRGB 分量（0–1）→ 线性光 */
const toLinear = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
/** 线性光 → sRGB 分量（0–1，可能越界，调用方自己判） */
const toGamma = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055)

/** '#rrggbb' → OKLCh { L, C, h } */
function hexToOklch(hex) {
  const n = parseInt(hex.slice(1), 16)
  const r = toLinear(((n >> 16) & 255) / 255)
  const g = toLinear(((n >> 8) & 255) / 255)
  const b = toLinear((n & 255) / 255)
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  return { L, C: Math.hypot(a, bb), h: (Math.atan2(bb, a) * 180) / Math.PI }
}

/** OKLCh → [r, g, b]（0–1 sRGB 分量，未裁剪，越界即出域） */
function oklchToRgb(L, C, h) {
  const hr = (h * Math.PI) / 180
  const a = C * Math.cos(hr)
  const b = C * Math.sin(hr)
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3
  const lin = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ]
  return lin.map(toGamma)
}

const inGamut = ([r, g, b]) => [r, g, b].every((c) => c >= -0.0005 && c <= 1.0005)

/** 音调（CIE L* 0–100）→ OKLab 亮度 */
function toneToL(tone) {
  const y = tone > 8 ? (((tone + 16) / 116) ** 3) : tone / 903.3
  return Math.cbrt(Math.max(0, y))
}

/** 再收色度直到落进 sRGB */
function fitChroma(L, C, h) {
  if (inGamut(oklchToRgb(L, C, h))) return C
  let lo = 0
  let hi = C
  for (let i = 0; i < 24; i++) {
    const mid = (lo + hi) / 2
    if (inGamut(oklchToRgb(L, mid, h))) lo = mid
    else hi = mid
  }
  return lo
}

const toHex = ([r, g, b]) =>
  '#' +
  [r, g, b]
    .map((c) => Math.round(Math.min(1, Math.max(0, c)) * 255).toString(16).padStart(2, '0'))
    .join('')

/* ------------------------------------------------------------ 音调板 */

/** 音调 → 色度系数（钟形：40–60 最艳，往两端收） */
const CURVE = [
  [0, 0],
  [10, 0.46],
  [20, 0.62],
  [30, 0.78],
  [40, 0.95],
  [50, 1],
  [60, 1],
  [70, 0.95],
  [80, 0.88],
  [90, 0.72],
  [95, 0.6],
  [100, 0],
]

function curveAt(tone) {
  for (let i = 1; i < CURVE.length; i++) {
    const [t1, c1] = CURVE[i]
    if (tone <= t1) {
      const [t0, c0] = CURVE[i - 1]
      const k = (tone - t0) / (t1 - t0)
      return c0 + (c1 - c0) * k
    }
  }
  return 0
}

/**
 * 由色相 + 基础色度造一条音调板。
 * @param {number} hue OKLCh 色相（度）
 * @param {number} chroma 基础色度（在 tone 50 附近取满）
 * @returns {(tone:number)=>string} 音调 → hex
 */
function palette(hue, chroma) {
  const cache = new Map()
  return (tone) => {
    if (cache.has(tone)) return cache.get(tone)
    const L = toneToL(tone)
    const C = fitChroma(L, Math.max(0, chroma) * curveAt(tone), hue)
    const hex = toHex(oklchToRgb(L, C, hue))
    cache.set(tone, hex)
    return hex
  }
}

/* ------------------------------------------------------------ 种子与角色 */

// B 站粉做 primary 种子；error 用 MD3 官方基线的红（错误色不该跟着品牌色跑）
const PRIMARY_SEED = '#fb7299'
const ERROR_SEED = '#ba1a1a'

const seed = hexToOklch(PRIMARY_SEED)
const errSeed = hexToOklch(ERROR_SEED)

const tone40 = toneToL(40)
const hue = seed.h
const chromaBase = fitChroma(tone40, seed.C, hue) // 主色种子在自己的色相上能撑到的最大艳度

// 同一色相家族：primary 满艳、secondary 收干（次要按钮 / 选中态底）、tertiary 转 60° 拉开
const p = palette(hue, chromaBase)
const s = palette(hue, chromaBase * 0.42)
const t = palette(hue + 60, chromaBase * 0.92)
const e = palette(errSeed.h, fitChroma(tone40, errSeed.C, errSeed.h))
// 中性色也带一丝品牌色相（Material You 的「有色调的中性色」），靠极低色度实现
const n = palette(hue, 0.018)
const nv = palette(hue, 0.032)

/** 角色 → [中性板, 音调]；深浅两套 scheme 只是取的音调不同 */
const DARK = {
  '--md-primary': [p, 80],
  '--md-on-primary': [p, 20],
  '--md-primary-container': [p, 30],
  '--md-on-primary-container': [p, 90],
  '--md-inverse-primary': [p, 40],
  '--md-secondary': [s, 80],
  '--md-on-secondary': [s, 20],
  '--md-secondary-container': [s, 30],
  '--md-on-secondary-container': [s, 90],
  '--md-tertiary': [t, 80],
  '--md-on-tertiary': [t, 20],
  '--md-tertiary-container': [t, 30],
  '--md-on-tertiary-container': [t, 90],
  '--md-error': [e, 80],
  '--md-on-error': [e, 20],
  '--md-error-container': [e, 30],
  '--md-on-error-container': [e, 90],
  '--md-surface': [n, 6],
  '--md-surface-dim': [n, 6],
  '--md-surface-bright': [n, 24],
  '--md-surface-container-lowest': [n, 4],
  '--md-surface-container-low': [n, 10],
  '--md-surface-container': [n, 12],
  '--md-surface-container-high': [n, 17],
  '--md-surface-container-highest': [n, 22],
  '--md-on-surface': [n, 90],
  '--md-on-surface-variant': [nv, 80],
  '--md-surface-variant': [nv, 30],
  '--md-outline': [nv, 60],
  '--md-outline-variant': [nv, 30],
  '--md-inverse-surface': [n, 90],
  '--md-inverse-on-surface': [n, 20],
  '--md-scrim': [n, 0],
  '--md-shadow': [n, 0],
}

const LIGHT = {
  '--md-primary': [p, 40],
  '--md-on-primary': [p, 100],
  '--md-primary-container': [p, 90],
  '--md-on-primary-container': [p, 10],
  '--md-inverse-primary': [p, 80],
  '--md-secondary': [s, 40],
  '--md-on-secondary': [s, 100],
  '--md-secondary-container': [s, 90],
  '--md-on-secondary-container': [s, 10],
  '--md-tertiary': [t, 40],
  '--md-on-tertiary': [t, 100],
  '--md-tertiary-container': [t, 90],
  '--md-on-tertiary-container': [t, 10],
  '--md-error': [e, 40],
  '--md-on-error': [e, 100],
  '--md-error-container': [e, 90],
  '--md-on-error-container': [e, 10],
  '--md-surface': [n, 98],
  '--md-surface-dim': [n, 87],
  '--md-surface-bright': [n, 98],
  '--md-surface-container-lowest': [n, 100],
  '--md-surface-container-low': [n, 96],
  '--md-surface-container': [n, 94],
  '--md-surface-container-high': [n, 92],
  '--md-surface-container-highest': [n, 90],
  '--md-on-surface': [n, 10],
  '--md-on-surface-variant': [nv, 30],
  '--md-surface-variant': [nv, 90],
  '--md-outline': [nv, 50],
  '--md-outline-variant': [nv, 80],
  '--md-inverse-surface': [n, 20],
  '--md-inverse-on-surface': [n, 95],
  '--md-scrim': [n, 0],
  '--md-shadow': [n, 0],
}

/* ------------------------------------------------------------ 输出 */

const css = `/**
 * BiliMusic · MD3 设计令牌（生成物，勿手改）
 *
 * 由 scripts/gen_md3_tokens.mjs 生成：种子色 ${PRIMARY_SEED}（B 站粉）推音调板，
 * 角色按 MD3 官方 scheme 映射音调（深色取 80/90 档、浅色取 40/100 档…），
 * 中性色带一丝品牌色相。错误色固定用 MD3 基线的红 ${ERROR_SEED}。
 *
 * 用法：两个页面（popup.html / player.html）都引本文件，再由 md3.bridge.css 把角色
 * 接到 daisyUI 变量上；页面 css 只写自己的排版与组件形状，别在这里改值。
 * 换种子色 / 加角色改脚本后重跑，产物整体替换本文件。
 *
 *   node extension/scripts/gen_md3_tokens.mjs
 */

/* ------------------------------- 深色（默认） ------------------------------- */

[data-theme='bilimusic'],
:root {
${Object.entries(DARK)
  .map(([name, [pal, tone]]) => `  ${name}: ${pal(tone)};`)
  .join('\n')}
}

/* ------------------------------- 浅色 ------------------------------- */

[data-theme='bilimusic-light'] {
${Object.entries(LIGHT)
  .map(([name, [pal, tone]]) => `  ${name}: ${pal(tone)};`)
  .join('\n')}
}
`

writeFileSync(OUT, css)
console.log(`已写入 ${OUT}（${Object.keys(DARK).length} 个角色 × 2 套 scheme）`)
