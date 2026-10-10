/**
 * 生成 src/ui/vendor/daisyui.subset.css —— daisyUI 5 官方分文件的按需拼接
 *
 * 用法（需要网络，仅生成时）：
 *
 *   node extension/scripts/gen_daisyui_subset.mjs
 */

import { writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const VERSION = '5.7.46'
const CDN = `https://cdn.jsdelivr.net/npm/daisyui@${VERSION}`

/** 拼接顺序即 @layer 出现顺序：base 在前、utilities 在后（与官方整包一致）。 */
const FILES = [
  ['base/properties.css', '@property'],
  ['base/rootcolor.css', '--root-bg'],
  ['base/scrollbar.css', 'scrollbar-color'],
  ['base/svg.css', '--fx-noise'],
  ['base/reset.css', '@layer base'],
  ['utilities/join.css', '.join{'],
  ['components/button.css', '.btn{'],
  ['components/input.css', '.input{'],
  ['components/select.css', '.select{'],
  ['components/toggle.css', '.toggle{'],
  ['components/range.css', '.range{'],
  ['components/badge.css', '.badge{'],
  ['components/card.css', '.card{'],
  ['components/list.css', '.list{'],
  ['components/loading.css', '.loading{'],
  ['components/status.css', '.status{'],
  ['components/toast.css', '.toast{'],
  ['components/alert.css', '.alert{'],
]

async function fetchFile(path) {
  const res = await fetch(`${CDN}/${path}`)
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`)
  return res.text()
}

/** 剥掉 @media (width>=Npx){…} 断点复份（花括号配平扫描，嵌套安全） */
function stripBreakpointBlocks(css) {
  let out = css
  let stripped = 0
  for (;;) {
    const start = out.indexOf('@media (width>=')
    if (start === -1) break
    const open = out.indexOf('{', start)
    let depth = 0
    let end = -1
    for (let i = open; i < out.length; i++) {
      if (out[i] === '{') depth++
      else if (out[i] === '}' && --depth === 0) {
        end = i
        break
      }
    }
    if (end === -1) throw new Error('花括号不配平，断点块剥离中止')
    out = out.slice(0, start) + out.slice(end + 1)
    stripped++
  }
  return { out, stripped }
}

const parts = []
const provenance = []

for (const [path, marker] of FILES) {
  const raw = await fetchFile(path)
  const { out, stripped } = stripBreakpointBlocks(raw)
  if (out.includes('@media (width')) {
    throw new Error(`${path}: 剥离后仍残留 width 断点块，需要人工检查`)
  }
  if (!out.includes(marker)) {
    throw new Error(`${path}: 关键选择器 ${marker} 不在场，来源文件形态变了？`)
  }
  const balance = [...out].reduce((n, c) => n + (c === '{' ? 1 : c === '}' ? -1 : 0), 0)
  if (balance !== 0) throw new Error(`${path}: 花括号不配平（差 ${balance}）`)
  parts.push(out)
  provenance.push(` *   ${path.padEnd(26)} ${String(out.length).padStart(7)} B（剥除断点复份 ${stripped} 块）`)
}

const header = `/*! BiliMusic · daisyUI ${VERSION} 按需子集 —— 由 scripts/gen_daisyui_subset.mjs 生成，勿手改
 *
 * 来源：daisyUI ${VERSION} 官方分文件原样拼接（MIT License，https://daisyui.com）。
 * 未包含：其余组件、颜色工具类、33 套额外主题、响应式断点复份。
 * 升级 / 增减组件：改脚本里的 FILES 后重跑，产物整体替换本文件。
 * 主题变量（--color-* / --radius-* 等）由 src/ui/md3.bridge.css 从 MD3 角色改接而来，
 * 不来自本文件（daisyUI 5 的主题变量一律由宿主提供，子集里只有 rootcolor 那条）。
 *
 * 拼接清单（剥除断点后）：
${provenance.join('\n')}
 */
`

const css = header + parts.join('\n') + '\n'
const outPath = fileURLToPath(new URL('../src/ui/vendor/daisyui.subset.css', import.meta.url))
writeFileSync(outPath, css)
console.log(`已生成 ${outPath}`)
console.log(`体积：${css.length} B`)
console.log(`sha256：${createHash('sha256').update(css).digest('hex')}`)
