/**
 * 生成 src/ui/vendor/fontawesome.subset.css + src/ui/vendor/webfonts/*.woff2
 *
 * 用法（需要网络，仅生成时）：
 *
 *   node extension/scripts/gen_fontawesome_subset.mjs
 *
 */

import { writeFileSync, mkdirSync, readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const VERSION = '5.15.4'
const PKG = `@fortawesome/fontawesome-free@${VERSION}`
const CDN = `https://cdn.jsdelivr.net/npm/${PKG}`

/** solid（.fas）图标白名单：class 名不带 fa- 前缀 */
const SOLID = [
  'arrow-left', 'arrow-right', 'at', 'bell', 'bookmark', 'chevron-down', 'chevron-right',
  'circle-notch', 'cloud', 'comment', 'compact-disc', 'external-link-alt', 'file-import',
  'filter', 'folder-open', 'frown', 'heart', 'info-circle', 'list-ul', 'lock', 'music',
  'palette', 'pause', 'play', 'plus', 'qrcode', 'redo', 'sync', 'search', 'shield-alt',
  'sign-out-alt', 'sliders-h', 'spinner', 'step-backward', 'step-forward', 'stop',
  'tag', 'th-large', 'times', 'trash-alt', 'tv', 'user', 'user-circle',
  'video', 'volume-down', 'volume-mute', 'volume-up',
]

/** 要以 regular（.far，轮廓线）呈现的图标 */
const REGULAR = ['heart']

/**
 * brands（.fab / fa-brands）图标白名单
 *
 * 单独一档是因为 brands 是**第三套字体**（Font Awesome 5 Brands，字重 400），
 * 码位与 solid 不共用：fa-github 的 \f09b 在 Free 字体里没有对应字形，
 * 少了 fa-brands-400.woff2 就是一排方块。
 */
const BRANDS = ['github']

/** 字体：900 = solid，400 = regular / brands；用不到的不下载 */
const FONTS = [
  { cls: 'fas', family: "'Font Awesome 5 Free'", weight: 900, file: 'fa-solid-900.woff2', used: SOLID.length > 0 },
  { cls: 'far', family: "'Font Awesome 5 Free'", weight: 400, file: 'fa-regular-400.woff2', used: REGULAR.length > 0 },
  { cls: 'fab', family: "'Font Awesome 5 Brands'", weight: 400, file: 'fa-brands-400.woff2', used: BRANDS.length > 0 },
]

const SOLID_SET = new Set(SOLID)
const REGULAR_SET = new Set(REGULAR)
const BRANDS_SET = new Set(BRANDS)
/** 字形规则只按名字发一份，白名单三档合起来查 */
const KEEP = new Set([...SOLID, ...BRANDS])
for (const n of REGULAR) {
  if (!SOLID_SET.has(n)) {
    throw new Error(`REGULAR 里的 ${n} 不在 SOLID 里：regular 与 solid 共用码位，字形规则只按名字发一份`)
  }
}

/** 需要保留的非字形规则选择器前缀（版式 / 动画 / 屏幕阅读器专用类） */
const STRUCTURAL = /^\.(fa|fas|far|fab|fal|fad|fa-[\w-]*|sr-only)\b/

/** 反查 src/ui 时要跳过的工具类（它们不是图标字形） */
const NON_GLYPH = new Set([
  'spin', 'fw', 'ul', 'li', 'border', 'pull-left', 'pull-right', 'inverse', 'stack',
  'swap-opacity', 'rotate-90', 'rotate-180', 'rotate-270', 'rotate-by',
  'flip-horizontal', 'flip-vertical', 'pulse', 'spin-reverse',
])

async function fetchBuf(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`)
  return Buffer.from(await res.arrayBuffer())
}

async function fetchText(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`)
  return res.text()
}

/**
 * 顶层规则切分（花括号配平扫描；@media 内的嵌套交给调用方递归）
 *
 * 切之前先把注释剥掉：上游 all.min.css 开头是一段许可证注释，它不含花括号，
 * 会被原样粘在第一条规则的选择器前面。第一条恰好是
 * `.fa,.fab,.fad,.fal,.far,.fas{…font-style:normal…}` —— isStructural 拿带注释的
 * 选择器去匹配会匹配不上，整条就会丢掉。丢了它没有字形缺失、没有 @font-face 缺失，
 * 只表现为「所有图标变斜体」（<i> 的浏览器默认就是 italic）。
 */
function splitRules(css) {
  const src = css.replace(/\/\*[\s\S]*?\*\//g, '')
  const out = []
  let depth = 0
  let start = 0
  for (let i = 0; i < src.length; i++) {
    const c = src[i]
    if (c === '{') depth++
    else if (c === '}') {
      if (--depth === 0) {
        out.push(src.slice(start, i + 1).trim())
        start = i + 1
      }
    }
  }
  const tail = src.slice(start).trim()
  if (tail) out.push(tail)
  return out
}

const atName = (rule) => rule.slice(1, rule.search(/[\s({]/)).replace(/-$/, '')

/** 一条规则里的图标字形：逐个选择器给出 {名字, 码位} */
function glyphEntries(rule) {
  const open = rule.indexOf('{')
  const selector = rule.slice(0, open)
  const body = rule.slice(open + 1, rule.lastIndexOf('}'))
  const codes = [...body.matchAll(/content\s*:\s*"\\([0-9a-fA-F]+)"/g)].map((m) => m[1])
  if (!codes.length) return null
  const entries = []
  selector.split(',').map((s) => s.trim()).forEach((part, i) => {
    const m = part.match(/\.fa-([\w-]+):(?:before|after)$/)
    if (!m) return
    entries.push({ name: m[1], hex: codes[i] ?? codes[0] })
  })
  return entries.length ? entries : null
}

const isStructural = (rule) => {
  const selectors = rule.slice(0, rule.indexOf('{')).split(',').map((s) => s.trim())
  return selectors.every((s) => STRUCTURAL.test(s))
}
const isSpin = (rule) => rule.startsWith('.fa-spin')

/* ------------------------------ 裁剪上游 CSS ------------------------------ */

const upstream = await fetchText(`${CDN}/css/all.min.css`)
if (!upstream.includes('.fa-play:before') || !upstream.includes('Font Awesome 5 Free')) {
  throw new Error('上游 all.min.css 形态变了（找不到 .fa-play:before 或字体族声明），需要人工检查')
}

const base = []
const spin = []
const keyframes = []
const glyphs = new Map() // 图标名 → 码位
let droppedGlyphs = 0
let glyphRules = 0

/** 收一条普通规则（字形 / 结构性） */
function collect(rule) {
  const entries = glyphEntries(rule)
  if (entries) {
    glyphRules += entries.length
    for (const e of entries) {
      // 白名单外的全丢
      if (KEEP.has(e.name)) glyphs.set(e.name, e.hex)
      else droppedGlyphs++
    }
    return
  }
  if (!isStructural(rule)) return
  if (isSpin(rule)) spin.push(rule)
  else base.push(rule)
}

for (const rule of splitRules(upstream)) {
  if (!rule.startsWith('@')) {
    collect(rule)
    continue
  }
  const name = atName(rule)
  if (name.endsWith('keyframes')) {
    if (rule.includes('fa-spin')) keyframes.push(rule)
    continue
  }
  if (name === 'media' || name === 'supports') {
    const inner = splitRules(rule.slice(rule.indexOf('{') + 1, rule.lastIndexOf('}')))
    const kept = []
    for (const r of inner) {
      const g = glyphEntries(r)
      if (g ? g.some((e) => KEEP.has(e.name)) : isStructural(r)) kept.push(r)
    }
    if (kept.length) base.push(`${rule.slice(0, rule.indexOf('{'))}{${kept.join('')}}`)
    continue
  }
}

/**
 * `.fa-brands` 是 `.fab` 的别名，上游 all.min.css 里没有这个类。
 *
 * UI 写 `class="fa-brands fa-github"` 时，只补一条 font-family 别名是不够的：
 * 上游那组「族规则」的第一条是版式规则
 * `.fa,.fab,.fad,.fal,.far,.fas{…font-style:normal;display:inline-block…}`，
 * 选择器里并没有 `.fa-brands`。于是 brands 图标拿不到 font-style:normal，
 * 退回 `<i>` 的浏览器默认 italic —— 症状是字形齐、字体在，只有那个图标歪着。
 *
 * 所以这里复用上游那条版式规则的声明块（不手抄，跟上游一起升级），
 * 补齐 `.fa-brands` 的版式 + brands 字体族 + 400 字重。
 */
if (BRANDS.length) {
  const typo = base.find((r) => /^\.[\w-]+(,\s*\.[\w-]+)*\{[^}]*font-style:normal/.test(r))
  if (!typo) throw new Error('上游版式规则（font-style:normal）没被收进子集：无法给 .fa-brands 对齐版式')
  const decl = typo.slice(typo.indexOf('{') + 1, typo.lastIndexOf('}')).replace(/;\s*$/, '')
  base.push(`.fa-brands{${decl};font-family:"Font Awesome 5 Brands";font-weight:400}`)
}

/** 取字形码位；缺失则报错 */
const codeOf = (name) => {
  const hex = glyphs.get(name)
  if (!hex) throw new Error(`上游 all.min.css 里找不到 .fa-${name}:before 的字形——白名单写了 FA5 没有的图标名？`)
  return hex
}

/* ------------------------------ 字体文件 ------------------------------ */

const webfontDir = fileURLToPath(new URL('../src/ui/vendor/webfonts/', import.meta.url))
mkdirSync(webfontDir, { recursive: true })
const faceBlocks = []
let fontBytes = 0
for (const font of FONTS) {
  if (!font.used) continue
  const buf = await fetchBuf(`${CDN}/webfonts/${font.file}`)
  // woff2 自检
  if (buf.length < 1024 || buf.readUInt32BE(0) !== 0x774f4632) {
    throw new Error(`${font.file}: 不是合法 woff2（${buf.length} B，头 4 字节 ${buf.subarray(0, 4).toString('hex')}）`)
  }
  writeFileSync(webfontDir + font.file, buf)
  fontBytes += buf.length
  faceBlocks.push(
    `@font-face {\n` +
      `  font-family: ${font.family};\n` +
      `  font-style: normal;\n` +
      `  font-weight: ${font.weight};\n` +
      `  font-display: block;\n` +
      `  src: url('./webfonts/${font.file}') format('woff2');\n` +
      `} /* ${font.cls} */`
  )
  console.log(`已拉取 webfonts/${font.file}：${buf.length} B`)
}

/* ---------------------- 反查：UI 用到的图标是否都在白名单 ---------------------- */

const uiDir = fileURLToPath(new URL('../src/ui/', import.meta.url))
const usedSolid = new Set()
const usedRegular = new Set()
const usedBrands = new Set()
/** 族前缀 → 白名单：far 走轮廓字体、fab / fa-brands 走独立的 brands 字体 */
const setOf = (fam) => (fam === 'far' ? usedRegular : fam === 'fab' || fam === 'fa-brands' ? usedBrands : usedSolid)
const add = (set, name) => {
  if (!NON_GLYPH.has(name)) set.add(name)
}
for (const f of ['popup.html', 'player.html', 'popup.js', 'player.js', 'shared/common.css', 'shared/store.js']) {
  const src = readFileSync(uiDir + f, 'utf8')
  // 常规 class="fas fa-play" / 'far fa-heart' / 'fa-brands fa-github'：族前缀决定用哪套字体
  for (const m of src.matchAll(/\b(fa|fas|far|fab|fal|fad|fa-brands)\s+fa-([a-z][\w-]*)/g)) {
    add(setOf(m[1]), m[2])
  }
  // 模板拼接：<i class="fas fa-${cond ? 'frown' : 'search'}"> —— 名字藏在三元里
  for (const m of src.matchAll(/\b(fa|fas|far|fab|fal|fad|fa-brands)\s+fa-\$\{([^}]*)\}/g)) {
    const set = setOf(m[1])
    for (const s of m[2].matchAll(/'([a-z][\w-]*)'/g)) add(set, s[1])
  }
}
const missingSolid = [...usedSolid].filter((n) => !SOLID_SET.has(n))
const missingRegular = [...usedRegular].filter((n) => !SOLID_SET.has(n) || !REGULAR_SET.has(n))
const missingBrands = [...usedBrands].filter((n) => !BRANDS_SET.has(n))
if (missingSolid.length || missingRegular.length || missingBrands.length) {
  if (missingSolid.length) {
    console.error(`\nsrc/ui 用到、但没在脚本 SOLID 白名单里的图标：\n  ${missingSolid.join('\n  ')}`)
  }
  if (missingRegular.length) {
    console.error(`\nsrc/ui 以 .far 轮廓样式用到、但没在脚本 REGULAR 白名单里的图标：\n  ${missingRegular.join('\n  ')}`)
  }
  if (missingBrands.length) {
    console.error(`\nsrc/ui 以 .fab / fa-brands 用到、但没在脚本 BRANDS 白名单里的图标：\n  ${missingBrands.join('\n  ')}`)
  }
  console.error('加进白名单后重跑本脚本，否则生成的子集里没有对应字形 / 轮廓字体。\n')
  process.exit(1)
}
const unused = [...SOLID, ...BRANDS].filter((n) => !usedSolid.has(n) && !usedRegular.has(n) && !usedBrands.has(n))
if (unused.length) {
  console.log(`\n提示：白名单里这 ${unused.length} 个图标 src/ui 已经不用了：${unused.join(' ')}`)
}

/* -------------------------------- 产物 -------------------------------- */

/** 一个名字只发一条 `.fa-x:before`：solid / regular 共用码位，切样式靠字体 */
const glyphLines = () =>
  [...SOLID, ...BRANDS].map((n) => `.fa-${n}:before {\n  content: "\\${codeOf(n)}";\n}`).join('\n')

const header = [
  `/*! BiliMusic · Font Awesome ${VERSION} Free 按需子集 —— 由 scripts/gen_fontawesome_subset.mjs 生成，勿手改`,
  ' *',
  ` * 来源：${PKG}（Font Awesome Free 5.15.4 · CC BY 4.0 / SIL OFL 1.1 / MIT 三许可 · https://fontawesome.com）`,
  ' * 自托管：字体随扩展本地加载，与 daisyUI 子集同一套「构建脚本拉取、产物入库」的约定。',
  ' * 增删图标：改脚本里的 SOLID / REGULAR / BRANDS 白名单后重跑本脚本，产物整体替换本文件',
  ' *          （脚本会反查 src/ui 的实际用法，白名单漏了会直接报错并列出缺哪些）。',
  ' *',
  ` * 裁剪：官方 all.min.css ${upstream.length} B / ${glyphRules} 个字形 → 保留 ${SOLID.length + BRANDS.length} 个，丢弃 ${droppedGlyphs} 个`,
  ` * 字体：${FONTS.filter((f) => f.used).map((f) => f.file).join(' + ')} 共 ${fontBytes} B，自托管于 vendor/webfonts/（只留 woff2）`,
  ` * 样式：.fas 与 .far 共用同一批字形码位，靠 ${REGULAR.length ? 'fa-regular-400.woff2' : '（无 .far 用法）'} 切轮廓`,
  ` *       ${BRANDS.length ? '.fab / .fa-brands 走独立的 Font Awesome 5 Brands 字体（fa-brands-400.woff2），码位与 solid 不共用' : '（无 brands 用法）'}`,
  ` * 结构：${base.length} 条无字形规则（.fa/.fas/.far 版式与字体族、.sr-only 等）原样保留 + .fa-spin 动画与 keyframes`,
  ' */',
  '',
].join('\n')

const css =
  `${header}\n` +
  `/* ---- 字体（vendor/webfonts/ 自托管，只引 woff2） ---- */\n` +
  `${faceBlocks.join('\n\n')}\n\n` +
  `/* ---- 版式与字体族（.fas → 900 实心 / .far → 400 轮廓 / .fab → Brands） ---- */\n${base.join('\n')}\n\n` +
  `/* ---- 旋转动画（fa-spin） ---- */\n${[...spin, ...keyframes].join('\n')}\n\n` +
  `/* ---- 图标字形（.fa / .fas / .far 共用；.fab / .fa-brands 靠各自的字体族） ---- */\n${glyphLines()}\n`

const balance = [...css].reduce((n, c) => n + (c === '{' ? 1 : c === '}' ? -1 : 0), 0)
if (balance !== 0) throw new Error(`花括号不配平（差 ${balance}）`)
if (!css.includes('fa-solid-900.woff2')) throw new Error('solid 字体段缺失：.fas 会退化成方块')
if (REGULAR.length && !css.includes('fa-regular-400.woff2')) {
  throw new Error('regular 字体段缺失：.far 会画成实心')
}
if (BRANDS.length && !css.includes('fa-brands-400.woff2')) {
  throw new Error('brands 字体段缺失：.fab / .fa-brands 会画成方块（码位与 Free 字体不共用）')
}
const baseText = base.join('\n')
if (!/^\.fa,[^{]*\{[^}]*font-style:normal/m.test(baseText)) {
  throw new Error('基础版式规则（.fa,…{font-style:normal}）不在场：图标会退回 <i> 的默认斜体')
}
if (!/^\.fa,[^{]*\{[^}]*display:inline-block/m.test(baseText)) {
  throw new Error('基础版式规则（display:inline-block）不在场：图标基线与居中会跑偏')
}
if (!/^\.fa,\.far,\.fas\{font-family:"Font Awesome 5 Free"\}/m.test(baseText)) {
  throw new Error('字体族规则不在场：找不到 .fa,.far,.fas 的 font-family 声明')
}
if (!/\.far\{font-weight:400\}/.test(baseText)) {
  throw new Error('.far 的 font-weight:400 不在场：轮廓字体会被渲染成实心')
}
if (BRANDS.length) {
  // 上游只有 .fab；少了别名，UI 写 fa-brands 时元素落回 Free 字体族、字形变方块
  if (!/^\.fab\{font-family:"Font Awesome 5 Brands"\}/m.test(baseText)) {
    throw new Error('.fab 的字体族规则不在场：brands 图标会落回 Free 字体')
  }
  const alias = baseText.match(/^\.fa-brands\{[^}]*\}/m)
  if (!alias) {
    throw new Error('.fa-brands 别名规则不在场：class="fa-brands fa-x" 的图标会落回 Free 字体')
  }
  // 别名规则必须同时带上版式与字重：只补 font-family 时 <i> 的默认 italic
  // 照样生效（图标歪着，字形却不缺），所以三项缺一不可
  for (const [re, why] of [
    [/font-family:"Font Awesome 5 Brands"/, '字体族（否则字形变方块）'],
    [/font-style:normal/, 'font-style:normal（否则退回 <i> 的默认斜体）'],
    [/display:inline-block/, 'display:inline-block（否则基线与居中跑偏）'],
    [/font-weight:400/, 'font-weight:400（否则被合成粗体）'],
  ]) {
    if (!re.test(alias[0])) throw new Error(`.fa-brands 别名规则缺 ${why}`)
  }
}
for (const n of [...SOLID, ...BRANDS]) {
  if (!css.includes(`.fa-${n}:before {`)) throw new Error(`产物里没有字形规则：.fa-${n}:before`)
}

const outPath = fileURLToPath(new URL('../src/ui/vendor/fontawesome.subset.css', import.meta.url))
writeFileSync(outPath, css)

console.log(`\n已生成 ${outPath}`)
console.log(`体积：${css.length} B（上游 ${upstream.length} B）`)
console.log(`字形：${glyphs.size} / ${glyphRules}（丢弃 ${droppedGlyphs}）`)
console.log(`sha256：${createHash('sha256').update(css).digest('hex')}`)