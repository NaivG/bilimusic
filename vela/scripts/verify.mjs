/**
 * 离线校验脚本（纯 Node，无需真机/模拟器）
 *
 *   cd vela && node scripts/verify.mjs
 *
 * 覆盖几块最容易出错、且不需要设备就能验证的逻辑：
 *   1. MD5 与 WBI 签名（对照 bilibili-API-collect 官方测试向量）
 *   2. @system.fetch 返回形态归一化（官方文档与本地 API 定义不一致）
 *   3. 扫码登录的纯逻辑：请求头 Cookie 解析、APP 签名（TV 端唯一路径；Web 端已移除，见第 6b 节）
 *   4. 跨 VM 共享播放态的合并规则，以及真实的 playerService 三 VM 端到端流程
 *      （Vela 每个 page 一个独立 JS VM，见 common/playstate.js 与第 9 节）
 *   4a. 页面不可见时进度不广播（第 9e 节：原生 ontimeupdate 4HZ 在切走页面后
 *      仍绑在主页 VM 上，靠 setVisible 挡广播省电；只挡广播、不挡镜像刷新）
 *   4b. 原生机型直链失败兜底的错误处理纪律（第 9d 节：CDN 不收空 Referer →
 *      onerror 无载荷连发 / code=28 超时释义 / 兜底期间切歌的竞态守卫）
 *   5. manifest 后台运行声明（第 10 节）与系统音量语义（第 11 节，含音量页官方示例布局：
 *      不做安全区、音量条吃满屏宽、贴底圆形关闭钮）
 *   6. 设备能力：封面背景图机型白名单与圆屏安全区（第 12 节）
 *   7. 更多页数据链路：推荐流/热门解析、曲目匹配、点播与来源解耦（第 13 节）
 *   8. 登录态门禁：带 Cookie 的请求先等 session.ready（第 7b 节，favDetail -403 回归）
 *   9. 关于页：@system.app 应用信息（第 14 节，值全部来自原生、不硬编码）
 *  10. 登录页只 back 不改入口链（第 10c 节：「进入更多」与「返回」同去处的回归）
 *  11. 网桥：本机没有 @system.fetch 时的联网通道（第 15 节：握手协商 / 分片 + 累计 ACK /
 *      无授权与断连的错误归类；桩扮演的是真插件，跑真实协议往返）
 *  12. B 档音频链路（第 16-19 节：v4 开放长度流的 CRC32 / 乱序重组 / go-back-N 重传 /
 *      取消与空闲超时；audioCache 缓存管理的复用 / .part 转正 / 清理 / 预取取消；
 *      网桥机型「落盘 → 播本地文件 → 预取下一首」的端到端）
 */

import { md5, deriveMixinKey, signWbi, signApp } from '../src/services/crypto.js'
import {
  normalizeFetchResult,
  describeFetchShape,
  describeBodyShape,
  bytesOfBody,
  describeNetCode,
  cdnNodeClass,
  isDirectLinkCapable,
  sortForDirectLink,
  directLinkBudget,
  urlDeadline,
  isUrlFresh,
  filterFreshUrls,
  flattenAudioTiers,
  parseCookieHeader,
  parseTvCookieInfo,
  buildCookieDiagnostics,
  buildQuery,
  parseRecommendItem,
  parsePopularItem,
} from '../src/common/parse.js'
import { trackKey, sameTrack, findTrackIndex } from '../src/common/tracks.js'
import {
  BRIDGE_ERRORS,
  buildLocalCaps,
  negotiateCaps,
  ChunkAssembler,
  StreamAssembler,
  base64Decode,
  hexDecode,
  utf8Decode,
  decodeSingleBody,
  crc32,
  binaryToUint8,
  buildFetchRequest,
} from '../src/common/fetchbridge.js'
import {
  normalizeShareState,
  bumpShareState,
  isShareNewer,
  isQueueNewer,
  describeShareState,
} from '../src/common/playstate.js'
import { clampVolume, toPercent, stepPercent } from '../src/common/volume.js'
import {
  APP_SOURCE_LABELS,
  describeAppSource,
  formatAppVersion,
  normalizeAppInfo,
} from '../src/common/appinfo.js'
import {
  WEEKDAY_LABELS,
  formatClock,
  formatClockParts,
} from '../src/common/clock.js'
import {
  CIRCLE_SAFE_WIDTH_PERCENT,
  SAFE_HORIZONTAL_INSET,
  COVER_THUMB_SUFFIX,
  normalizeDeviceInfo,
  resolveScreenShape,
  safeHorizontalInsetPx,
  shapeClassOf,
  supportsCoverBackground,
  normalizeCoverUrl,
} from '../src/common/device.js'
import { register } from 'node:module'
import { readFileSync } from 'node:fs'
import { CONFIG, PLAY } from '../src/common/config.js'

// Node 加载 src/**.js 时会先按 CommonJS 试解析、失败后再按 ESM 重解析，于是每次都提示
// MODULE_TYPELESS_PACKAGE_JSON。给 package.json 加 "type": "module" 会影响 aiot 构建链路，
// 所以这里只把这一条已知提示吞掉（npm run verify 另外用 --disable-warning 关掉它），
// 其它 warning 照常打印。
const rawEmitWarning = process.emitWarning.bind(process)
process.emitWarning = function (warning, ...rest) {
  if (rest[0] === 'MODULE_TYPELESS_PACKAGE_JSON') return
  return rawEmitWarning(warning, ...rest)
}

let passed = 0
let failed = 0

function ok(name, cond, detail) {
  if (cond) {
    passed++
    console.log(`  ✓ ${name}`)
  } else {
    failed++
    console.log(`  ✗ ${name}${detail ? ' → ' + detail : ''}`)
  }
}

function eq(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  ok(name, a === e, `期望 ${e}，实际 ${a}`)
}

/* ---------------------------- 1. MD5 ---------------------------- */

console.log('\n[1] MD5')
eq('空串', md5(''), 'd41d8cd98f00b204e9800998ecf8427e')
eq('"a"', md5('a'), '0cc175b9c0f1b6a831c399e269772661')
eq('"abc"', md5('abc'), '900150983cd24fb0d6963f7d28e17f72')
eq('"message digest"', md5('message digest'), 'f96b697d7cb7938d525a2f31aaf161d0')
eq('字母表', md5('abcdefghijklmnopqrstuvwxyz'), 'c3fcd3d76192e4007dfb496cca67e13b')
eq('中文（UTF-8）', md5('中文测试'), '089b4943ea034acfa445d050c7913e55')

/* ---------------------------- 2. WBI 签名 ---------------------------- */

console.log('\n[2] WBI 签名')
const imgKey = '7cd084941338484aae1ad9425b84077c'
const subKey = '4932caff0ff746eab6f01bf08b70ac45'
const mixinKey = deriveMixinKey(imgKey, subKey)
eq('mixin_key 派生', mixinKey, 'ea1db124af3c7062474693fa704f4ff8')

const signed = signWbi({ foo: '114', bar: '514', zab: 1919810 }, mixinKey, 1702204169)
eq('w_rid（官方测试向量）', signed.w_rid, '8f6f2b5b3d485fe1886cec6a0be8c5d4')
eq('wts 注入', signed.wts, 1702204169)
ok(
  '返回键集合 = 原始参数 + wts + w_rid',
  Object.keys(signed).sort().join(',') === 'bar,foo,w_rid,wts,zab',
  Object.keys(signed).sort().join(',')
)

// 特殊字符过滤 + 中文编码应遵循 encodeURIComponent（空格 %20，非 +）
const q = buildQuery({ foo: 'one one four', bar: '五一四', baz: 1919810 })
eq('中文/空格编码', q, 'foo=one%20one%20four&bar=%E4%BA%94%E4%B8%80%E5%9B%9B&baz=1919810')

/* -------------------- 3. fetch 返回形态归一化 -------------------- */

console.log('\n[3] fetch 返回形态归一化')

// 形态 A：本地 d.ts 的 Promise 形态 { code, data, headers }
const shapeA = normalizeFetchResult({
  code: 200,
  data: { code: 0, message: '0', data: { url: 'x' } },
  headers: { 'set-cookie': 'a=b' },
})
eq('形态A httpCode', shapeA.httpCode, 200)
eq('形态A body 保留业务信封', shapeA.body, { code: 0, message: '0', data: { url: 'x' } })
eq('形态A headers 不丢', shapeA.headers, { 'set-cookie': 'a=b' })

// 形态 B：官方文档的 Promise 示例 { data: { code, data, headers } }
const shapeB = normalizeFetchResult({
  data: { code: 200, data: { code: -101, message: '未登录' }, headers: { 'x-a': '1' } },
})
eq('形态B httpCode', shapeB.httpCode, 200)
eq('形态B body', shapeB.body, { code: -101, message: '未登录' })
eq('形态B headers', shapeB.headers, { 'x-a': '1' })

// 形态 C：本地 d.ts 的回调形态 { code, data }（无 headers）
const shapeC = normalizeFetchResult({ code: 200, data: { code: 0, message: '0', data: {} } })
eq('形态C httpCode', shapeC.httpCode, 200)
eq('形态C body', shapeC.body, { code: 0, message: '0', data: {} })
eq('形态C headers 缺失时为 {}', shapeC.headers, {})

eq('null 输入', normalizeFetchResult(null), { httpCode: 0, body: null, headers: {} })

// 状态码字段名：**官方给的是 `code`**（success 返回值表：code/data/headers），
// `status` 只是别名兜底。这条曾经写错过：业务侧直接读 `res.status`，真机上恒
// undefined，音频分块下载全废，报错只剩「CDN 返回 undefined」——
// 而离线桩当时也自创了 `status`，两边一起错，500+ 项全绿。教训：
// **桩必须照抄真机形态**（stubs/system.fetch.mjs 里也钉了这句话）。
eq('官方 success 形态 code=206 被认下来', normalizeFetchResult({ code: 206, data: 'x' }).httpCode, 206)
eq('status 别名兜底（不是主路径）', normalizeFetchResult({ status: 206, data: 'x' }).httpCode, 206)
eq('code 优先于 status', normalizeFetchResult({ code: 206, status: 200, data: 'x' }).httpCode, 206)
eq('认不出的形态不猜（httpCode=0，交给调用方报错）', normalizeFetchResult({ foo: 'bar' }).httpCode, 0)
eq(
  '认不出时报错能带上「本机给的是什么字段」',
  describeFetchShape({ foo: 1, bar: 'x' }),
  'foo=number, bar=string'
)

/* ------------- 3a. 响应体 → 字节（真机可能「状态码齐全但没有字节」） ------------- */

// 真机现场（2026-09-18）：`responseType:'arraybuffer'` 的 Range 请求回了 206 +
// 合法 Content-Range + 正确请求头，`data` 却是空的。屏幕上只有一句「分块响应体为空」，
// 完全看不出本机给的是什么形态。这一节把「怎么认字节、认不出怎么说话」钉死。

console.log('\n[3a] 响应体 → 字节（拿不到要能说清是什么形态）')

eq('形态 undefined', describeBodyShape(undefined), 'undefined')
eq('形态 null', describeBodyShape(null), 'null')
eq('形态 string 带长度', describeBodyShape('abcd'), 'string(4)')
eq('形态 ArrayBuffer 带长度', describeBodyShape(new ArrayBuffer(8)), 'ArrayBuffer(8)')
eq('形态 Uint8Array 带长度', describeBodyShape(new Uint8Array(5)), 'Uint8Array(5)')
eq('形态 怪对象带 byteLength', describeBodyShape({ byteLength: 9 }), 'object{byteLength=9,keys=byteLength}')
eq('形态 空对象', describeBodyShape({}), 'object{keys=空}')

eq('取字节 ArrayBuffer', Array.from(bytesOfBody(new ArrayBuffer(3))), [0, 0, 0])
eq('取字节 Uint8Array 视图（带 byteOffset 的子视图不能多取）', Array.from(bytesOfBody(new Uint8Array([1, 2, 3, 4]).subarray(1, 3))), [2, 3])
eq('取字节 {buffer} 包装（file.readArrayBuffer 的返回形态）', Array.from(bytesOfBody({ buffer: new Uint8Array([7, 8]) })), [7, 8])
eq('取字节 二进制字符串', Array.from(bytesOfBody('AB')), [65, 66])
eq('空串 → null（不是空数组）', bytesOfBody(''), null)
eq('空 ArrayBuffer → null', bytesOfBody(new ArrayBuffer(0)), null)
// 防呆：只有 byteLength 属性、并不是真缓冲区的对象，`new Uint8Array(obj)` 会得到
// **0 长度**（静默的假成功）。长度对不上就当「拿不到」——否则会把空字节当音频写下去。
eq('假缓冲区（只有 byteLength）→ null，不许静默给空', bytesOfBody({ byteLength: 5 }), null)

/* ------------- 3b. CDN 节点类 / 候选地址 / 有效期（防盗链按节点类生效） ------------- */

// 真机对照（2026-09-18 打表）：@system.audio 的 src **发不了 Referer**，而
//   mcdn 节点不校验 → 直链能播；upos / edge 校验 → 直链必 403（要落盘再播）。
// 这一节把「哪些地址能用直链」这条判据钉死：它决定了起播顺序与直链额度。

console.log('\n[3b] CDN 节点类 / 候选地址 / 有效期')

eq('节点类 mcdn', cdnNodeClass('https://xy116x196x153x35xy.mcdn.bilivideo.cn:8082/x.m4s'), 'mcdn')
eq('节点类 upos', cdnNodeClass('https://upos-sz-mirror08c.bilivideo.com/x.m4s'), 'upos')
eq('节点类 edge', cdnNodeClass('https://cn-jsnj-...edge...bilivideo.com/x.m4s'), 'edge')
eq('节点类 其它', cdnNodeClass('https://cdn.example/x.m4s'), 'other')
eq('空地址不炸', cdnNodeClass(''), 'other')
eq('能直链播 = mcdn', isDirectLinkCapable('https://a.mcdn.bilivideo.cn:8082/x'), true)
eq('upos 不能直链播', isDirectLinkCapable('https://upos-sz-mirror08c.bilivideo.com/x'), false)

const uposA = 'https://upos-sz-mirror08c.bilivideo.com/a.m4s'
const uposB = 'https://upos-sz-estgoss.bilivideo.com/b.m4s'
const mcdnC = 'https://xy.mcdn.bilivideo.cn:8082/c.m4s'
eq('直链顺序：mcdn 提到最前（其余保持原序）', sortForDirectLink([uposA, uposB, mcdnC]), [
  mcdnC,
  uposA,
  uposB,
])
eq('没有 mcdn 时顺序不动', sortForDirectLink([uposA, uposB]), [uposA, uposB])
// 额度：有 mcdn 才值得多试几条；一条都没有时试第 2 条纯属让用户多等一次失败
eq('额度：有 mcdn → DIRECT_TRIES', directLinkBudget([uposA, mcdnC, uposB], 3), 3)
eq('额度：无 mcdn → 只 1 条', directLinkBudget([uposA, uposB, uposA + '?x=1'], 3), 1)
eq('额度：空列表 → 0', directLinkBudget([], 3), 0)
eq('额度：候选比上限少时取候选数', directLinkBudget([mcdnC], 3), 1)

const now = 1800000000
const freshUrl = uposA + '?deadline=' + (now + 7200) + '&upsig=abc'
const staleUrl = uposB + '?deadline=' + (now - 10) + '&upsig=abc'
const soonUrl = uposB + '?deadline=' + (now + 60) + '&upsig=abc'
eq('解析 deadline', urlDeadline(freshUrl), now + 7200)
eq('没有 deadline → 0', urlDeadline(uposA), 0)
eq('有效期：还剩 2 小时 → 有效', isUrlFresh(freshUrl, now), true)
eq('有效期：已过期 → 无效', isUrlFresh(staleUrl, now), false)
eq('有效期：只剩 1 分钟（不足余量）→ 当无效', isUrlFresh(soonUrl, now), false)
eq('没有 deadline 的地址一律当有效（不瞎猜）', isUrlFresh(mcdnC, now), true)
eq('滤掉过期地址', filterFreshUrls([freshUrl, staleUrl, mcdnC], now), [freshUrl, mcdnC])

// ★ 跨档拍平：真机上「固定播不了」的稿件形状（BV1cogp6fEFv 实测）
//   30280 upos×3 / 30216 upos×3，唯一的 mcdn 地址在 30232 档里。
//   旧实现只取带宽最高的一档 → 那条 mcdn 永远轮不到 → 直链全 403、落盘又被超时打死。
const tiersFixture = [
  { id: 30280, bandwidth: 99400, baseUrl: 'https://upos-sz-estgoss.bilivideo.com/80.m4s', backupUrl: ['https://upos-sz-mirroralib.bilivideo.com/80b.m4s'] },
  { id: 30216, bandwidth: 66000, baseUrl: 'https://upos-sz-mirror08c.bilivideo.com/16.m4s', backupUrl: ['https://upos-sz-mirrorhwb.bilivideo.com/16b.m4s'] },
  { id: 30232, bandwidth: 99800, baseUrl: 'https://xy.mcdn.bilivideo.cn:8082/32.m4s', backupUrl: ['https://upos-sz-estgcos.bilivideo.com/32b.m4s'] },
]
const flat = flattenAudioTiers(tiersFixture)
eq(
  '拍平后档从高到低（30232 带宽最高 → 它的地址排在最前）',
  flat[0],
  'https://xy.mcdn.bilivideo.cn:8082/32.m4s'
)
ok('拍平包含各档的地址（3 档 × 2 条）', flat.length === 6, `共 ${flat.length} 条: ${flat.join(' ')}`)
ok(
  '★ 别的档里那条 mcdn 现在能轮到（直链就能播，不用等几十秒落盘）',
  sortForDirectLink(flat)[0] === 'https://xy.mcdn.bilivideo.cn:8082/32.m4s',
  '排在最前的: ' + sortForDirectLink(flat)[0]
)
eq('拍平会去重', flattenAudioTiers([{ bandwidth: 1, baseUrl: mcdnC, backupUrl: [mcdnC] }]), [mcdnC])
eq('拍平空输入不炸', flattenAudioTiers(null), [])


// 底层传输码释义：Vela 的 @system.fetch 从未给过失败码表，真机 fail(code) 透传的是
// libcurl 的码（28=超时，即「直链与落盘均失败：code=28」的 28）；业务码不掺和
eq('传输码 28 → 网络超时', describeNetCode(28), '网络超时')
eq('传输码 7 → 无法连接', describeNetCode(7), '无法连接服务器')
eq('传输码 56 → 传输中断', describeNetCode(56), '接收数据失败（传输中断）')
eq('快应用业务码 1000 不翻', describeNetCode(1000), '')
eq('B 站业务码 -403 不翻', describeNetCode(-403), '')
eq('未知传输码给空串', describeNetCode(99), '')

/* ------------------- 4. 请求头 Cookie 解析 ------------------- *//* ------------------- 7. 请求头 Cookie 解析 ------------------- */

console.log('\n[4] 请求头 Cookie 解析')
eq('分号分隔', parseCookieHeader('SESSDATA=a; bili_jct=b; DedeUserID=1'), {
  SESSDATA: 'a',
  bili_jct: 'b',
  DedeUserID: '1',
})
eq('空输入', parseCookieHeader(''), {})

/* ------------------- 5. APP 签名（TV 端登录用） ------------------- */

console.log('\n[5] APP 签名')
const appSign = signApp(
  { id: 114514, str: '1919810', test: 'いいよ，こいよ' },
  '1d8b6e7d45233436',
  '560c52ccd288fed045859ed18bffd973'
)
eq('sign（官方测试向量）', appSign.sign, '01479cf20504d865519ac50f33ba3a7d')
eq('appkey 已并入参数', appSign.appkey, '1d8b6e7d45233436')

// TV 端登录实际用到的参数形态
const tvAuth = signApp({ local_id: 0, ts: 0 }, '4409e2ce8ffd12b8', '59b43e04ad6965f34319062b478f83dd')
eq('TV 参数键集合', Object.keys(tvAuth).sort().join(','), 'appkey,local_id,sign,ts')
eq('TV sign 长度', tvAuth.sign.length, 32)
// sign 本身不参与签名计算：改 ts 必然改 sign
const tvAuth2 = signApp({ local_id: 0, ts: 1700000000 }, '4409e2ce8ffd12b8', '59b43e04ad6965f34319062b478f83dd')
ok('ts 变化则 sign 变化', tvAuth.sign !== tvAuth2.sign)

/* ------------- 6. TV 端 Cookie（cookie_info.cookies[]） ------------- */

console.log('\n[6] TV 端 Cookie 提取')
const tvCookies = parseTvCookieInfo({
  cookies: [
    { name: 'SESSDATA', value: 'tv-sess', http_only: 1, expires: 1679988973, secure: 0 },
    { name: 'bili_jct', value: 'tv-jct', http_only: 0, expires: 1679988973, secure: 0 },
    { name: 'DedeUserID', value: '10086', http_only: 0, expires: 1679988973, secure: 0 },
    { name: 'DedeUserID__ckMd5', value: 'tv-md5', http_only: 0, expires: 1679988973, secure: 0 },
    { name: 'sid', value: 'tv-sid', http_only: 0, expires: 1679988973, secure: 0 },
  ],
  domains: ['.bilibili.com'],
})
eq('TV Cookie 全量', Object.keys(tvCookies).sort().join(','), 'DedeUserID,DedeUserID__ckMd5,SESSDATA,bili_jct,sid')
eq('TV SESSDATA', tvCookies.SESSDATA, 'tv-sess')
const tvDiag = buildCookieDiagnostics(tvCookies, { via: 'tv' })
eq('TV 关键项齐全', tvDiag.missingKeyCookies, [])
eq('TV 诊断含 obtained', tvDiag.obtained.length, 5)
eq('cookie_info 缺失时', parseTvCookieInfo(null), {})
eq(
  'cookie_info 结构异常时',
  parseTvCookieInfo({ cookies: 'not-an-array' }),
  {}
)

// 6b. 回归：Web 端扫码路径已整体移除
//
// 曾经 authService 有 'tv' / 'web' 两种模式，当前方式取不到 SESSDATA 就自动换另一种重扫。
// 真机实测 Web 端两条 Cookie 来源同时断（多条 Set-Cookie 被运行时合并成一条只留 sid、
// data.url 跨域地址只带扫码页参数，复现数据见 README「四、扫码登录」），因此那条路永远
// 只会把用户引到「登录成功却没登上」的死循环里 —— 连同它的解析函数一起删掉，别再加回来。
const authServiceSource = readFileSync(
  new URL('../src/services/authService.js', import.meta.url),
  'utf8'
)
const biliApiSource = readFileSync(new URL('../src/services/biliApi.js', import.meta.url), 'utf8')
const parseSource = readFileSync(new URL('../src/common/parse.js', import.meta.url), 'utf8')
ok(
  'CONFIG.LOGIN 里不再有 MODE（扫码登录只剩 TV 一条路）',
  !('MODE' in CONFIG.LOGIN),
  `MODE=${CONFIG.LOGIN.MODE}`
)
ok(
  'biliApi 不再有 Web 端出码/轮询接口',
  ['generateQrCode', 'pollQrCode', 'qrcode_key'].every((s) => biliApiSource.indexOf(s) < 0),
  'biliApi 里仍有 Web 端扫码接口'
)
ok(
  'authService 不再有 Web 端分支与自动降级',
  ['generateQrCode', 'extractLoginCookies', 'triedModes', 'qrcodeKey', 'MODE_LABEL'].every(
    (s) => authServiceSource.indexOf(s) < 0
  ),
  'authService 里仍有 Web 端分支'
)
ok(
  'parse.js 里 Set-Cookie / 跨域地址解析已删除（只剩 TV 端 cookie_info）',
  ['parseSetCookie', 'parseCrossDomainUrl', 'extractLoginCookies', 'findHeader'].every(
    (s) => parseSource.indexOf(s) < 0
  ),
  'parse.js 里仍有 Web 端解析函数'
)

/* ------ 7. session.restore / ready 幂等性（防 page 与 bootstrap 抢跑） ------ */

// 这个测试不直接 import session.js（它依赖 @system.storage），而是把 session.js
// 的幂等 Promise 模式提炼出来跑一遍——验证「restore 只跑一次 + ready 共享结果」
// 的契约，避免「登录成功后进入其他页面立刻显示未登录」的竞态回归。
//
// 注意：这份幂等只保证「同一个 VM 内只读一次」。真机上每个 page 都是独立 VM，
// 各自都会读一遍 storage（日志里同一行 `[Session] restored` 打了三次），
// 那是正常的 —— 各 VM 读到的内容一致，不会出问题。

console.log('\n[7] session.restore / ready 幂等性')

async function testRestoreIdempotent() {
  let restorePromise = null
  let restoreCount = 0
  let resolveStorage
  const storagePromise = new Promise((r) => {
    resolveStorage = r
  })
  let loaded = false
  const state = { cookieHeader: '' }

  // 注意：必须写成同步函数，否则 async 会把返回值再包一层 Promise，
  // 表面上 p1 !== p2 但内部仍然共享，restoreCount 不会涨——但下面的同一性断言就过不了。
  function restore() {
    if (restorePromise) return restorePromise
    restorePromise = (async () => {
      restoreCount++
      const saved = await storagePromise
      if (saved && saved.cookieHeader) state.cookieHeader = saved.cookieHeader
      loaded = true
      return { ...state }
    })()
    return restorePromise
  }

  function ready() {
    if (loaded) return Promise.resolve({ ...state })
    return restore().then(() => ({ ...state }))
  }

  // 三个并发 restore() 必须复用同一份 Promise
  const p1 = restore()
  const p2 = restore()
  const p3 = restore()
  ok('restore() 并发调用返回同一 Promise', p1 === p2 && p2 === p3)
  ok('restore() 只触发一次底层读取', restoreCount === 1)

  // ready() 在 loaded 之前也必须复用同一份 restore
  const r1 = ready()
  const r2 = ready()
  ok('ready() 在未 loaded 时也只触发一次 restore', restoreCount === 1)

  // 让 storage 返回已保存的登录态
  resolveStorage({ cookieHeader: 'SESSDATA=test,middleware' })
  const after = await r1
  ok('storage 完成后 ready() 拿到已恢复的 cookie', state.cookieHeader === 'SESSDATA=test,middleware')
  ok('ready() resolve 当前 state', after.cookieHeader === 'SESSDATA=test,middleware')

  // loaded 之后再调 ready() 应该立即 resolve（不触发新的 storage 读取）
  const before = restoreCount
  const r3 = ready()
  await r3
  ok('loaded 后 ready() 不再触发 restore', restoreCount === before)
}

await testRestoreIdempotent()

/* --------- 7b. 登录态门禁：带 Cookie 的请求不能裸奔（favDetail 真机 -403 回归） --------- */

// 真机故障现场：收藏夹列表页正常，点进收藏夹详情却报
//   `获取收藏内容失败：code=-403 访问权限不足`
// 根因**不是签名**：这两个收藏夹接口实测都不校验 w_rid（不签名、不登录都返回 code 0，
// 未登录只是看不到私密夹）；而是**详情页那个 VM 从头到尾没读过登录态** ——
// favDetail.ux 没 import session、也没等 ready()，而 Vela 每个 page 一个独立 JS VM，
// 模块级 state 不跨页共享，于是 /x/v3/fav/resource/list 请求裸奔（无 Cookie），
// 私密收藏夹被后端判成「不是主人」→ -403（接口文档：查询权限收藏夹需要相应用户登录）。
//
// 两道防线都要在，本节两条都测：
//   1. 请求层兜底 —— api.js 凡带 Cookie 的请求先 await session.ready()（幂等）；
//   2. 页面显式门禁 —— 打需要登录态的接口的页面自己等登录态（fav / favDetail）。

console.log('\n[7b] 登录态门禁（带 Cookie 的请求先等 session.ready）')

// 从这里开始要加载 src/services/*（会 import @system.*），先把解析钩子挂上。
// 第 9 节的三个 VM 测试复用这几个桩实例（模块缓存，对应真机上全局的原生服务）。
register('./aiot-hooks.mjs', import.meta.url)

const audioStub = await import('../scripts/stubs/system.audio.mjs')
const volumeStub = await import('../scripts/stubs/system.volume.mjs')
const storageStub = await import('../scripts/stubs/system.storage.mjs')
const fetchStub = await import('../scripts/stubs/system.fetch.mjs')
const requestStub = await import('../scripts/stubs/system.request.mjs')
const interconnectStub = await import('../scripts/stubs/system.interconnect.mjs')

// @system.fetch / @system.interconnect 是"可能不存在"的接口（Redmi Watch 4 / Watch H1 E
// 上就没有 fetch），源码里走的是 require + try/catch（见 aiot-hooks.mjs 的说明）。
// Node ESM 里裸 require 是个未声明标识符 —— 往 globalThis 上挂一个，源码里的
// `require('@system.fetch')` 就能拿到桩；这个开关同时也让我们能模拟"这台机型没有它"。
let fetchFeatureAvailable = true
// 同理：@system.request 也是"可能不存在"的接口（audioCache 的整份原生下载通道）
let requestFeatureAvailable = true
// 真机上一台设备要么有 @system.fetch 要么没有，api.js 的 nativeBroken 是单向锁存；
// 离线自检要在同一个 Node 进程里先后扮演两种机型，所以：
//   - 桩按 fetchFeatureAvailable 决定 require 抛不抛错；
//   - 切回「有 fetch」时由 api.js 暴露的 __resetNativeProbe() 复位那个锁存（见 18i）。
globalThis.require = (name) => {
  if (name === '@system.fetch') {
    if (!fetchFeatureAvailable) throw new Error('feature not supported: @system.fetch')
    return fetchStub
  }
  if (name === '@system.interconnect') return interconnectStub
  // @system.request（原生整份下载，原生机型的兜底通道）：支持明细里部分机型没有，
  // 源码同样走 require + try/catch；这里按开关决定有没有
  if (name === '@system.request') {
    if (!requestFeatureAvailable) throw new Error('feature not supported: @system.request')
    return requestStub
  }
  // 其它 @system.* 不给桩：crypto.js 取 @system.crypto 失败会自己退回 JS 实现（预期行为）
  throw new Error('离线自检没有为 ' + name + ' 准备桩')
}

const apiSource = readFileSync(new URL('../src/services/api.js', import.meta.url), 'utf8')
ok(
  'api.js 带 Cookie 的请求先 await sessionReady()（页面忘了 ready 也不裸奔）',
  /await\s+sessionReady\(\)/.test(apiSource),
  'api.js 里找不到 await sessionReady()'
)
ok(
  'api.js 把 Cookie 有无打进日志（cookie=on/off，403 时一眼分清是登录态还是签名）',
  apiSource.indexOf('cookie=') >= 0,
  '日志里没有 cookie=on/off'
)

const favDetailSource = readFileSync(
  new URL('../src/pages/favDetail/favDetail.ux', import.meta.url),
  'utf8'
)
ok(
  'favDetail.ux import 了 session（详情页也要读登录态）',
  favDetailSource.indexOf('services/session') >= 0
)
ok(
  'favDetail.ux 加载前等 session.ready()（-403 的直接根因）',
  /session\s*\.\s*ready\(\)/.test(favDetailSource),
  'favDetail.ux 没有等登录态就发请求'
)
;['fav', 'favDetail'].forEach((name) => {
  const src = readFileSync(new URL(`../src/pages/${name}/${name}.ux`, import.meta.url), 'utf8')
  ok(
    `${name}.ux 调收藏夹接口前等登录态（页面 VM 不共享内存）`,
    /session\s*\.\s*ready\(\)/.test(src)
  )
})
ok(
  'favDetail.ux 对 -403 给人话（未登录时提示去登录，而不是甩一串 code）',
  favDetailSource.indexOf('需要登录后查看') >= 0
)

// 行为回归：往 storage 里预置一份登录态，再让一个**没跑过 restore 的 VM**直接发请求，
// 请求头里必须带 Cookie —— 这正是 favDetail 的故障现场（那个 VM 从未读过登录态）。
// 注意顺序：本节必须排在后面任何 VM 测试之前，用的是这个进程里唯一一份「还没读过
// 登录态」的 session 实例（真机对应刚创建的 page VM）；被读脏了这条就失去意义。
storageStub.__seed({
  [CONFIG.STORAGE_KEYS.AUTH]: JSON.stringify({
    cookieHeader: 'SESSDATA=vmtest%2C1700000000%2Cabc; bili_jct=jct; DedeUserID=42',
    mid: 42,
    uname: 'tester',
  }),
})
const favApiVm = await import('../src/services/biliApi.js?vm=favdetail')

fetchStub.__setJson({
  code: 0,
  data: { list: [{ id: 44233921, title: '默认收藏夹', media_count: 3 }] },
})
const favFolders = await favApiVm.getCreatedFavFolders(42)
const foldersReq = fetchStub.__last()
ok(
  '★ 收藏夹列表请求带上了 Cookie（VM 没先 ready 也不裸奔）',
  !!foldersReq && /SESSDATA=/.test((foldersReq.header || {}).Cookie || ''),
  `实际请求头：${JSON.stringify(foldersReq && foldersReq.header)}`
)
ok('收藏夹列表请求带 up_mid', /up_mid=42/.test((foldersReq && foldersReq.url) || ''))
eq('收藏夹列表解析出条目', favFolders.length, 1)

fetchStub.__setJson({ code: 0, data: { medias: [], has_more: false, info: { media_count: 0 } } })
await favApiVm.getFavResources(44233921, 1)
const resReq = fetchStub.__last()
ok(
  '★ 收藏夹详情请求带上了 Cookie（-403 的现场）',
  !!resReq && /SESSDATA=/.test((resReq.header || {}).Cookie || ''),
  `实际请求头：${JSON.stringify(resReq && resReq.header)}`
)
ok('收藏夹详情请求带 media_id', /media_id=44233921/.test((resReq && resReq.url) || ''))
ok(
  '收藏夹请求仍带 Referer/Origin（不是「用 Referer 换 Cookie」）',
  /bilibili\.com/.test((resReq.header || {}).Referer || '') &&
    /bilibili\.com/.test((resReq.header || {}).Origin || '')
)

// 反向确认：取流/CDN 抓文件那类请求不该顺手带上登录态（withCookie 默认 false）。
// 原测试是给 api.fetchToFile 写的「单次落盘请求的请求头契约」；该函数已被删除，
// 整文件落盘的请求头契约由 audioCache.cdnHeaders() 集中维护（永不带 Cookie +
// 必带 Referer），落盘行为本身由第 18 节端到端覆盖。withCookie 默认值在
// 上面 521/526 行附近已有断言（带 Cookie 的请求会带 Cookie，没带的就是没带）。

// 撤掉注入的响应：后面的用例若意外发起真实网络请求，桩要继续抛错（本来就是这个约定）
fetchStub.__reset()

/* ------------- 8. 跨 VM 共享播放态（多 page 独立 VM 的对账协议） ------------- */

// 真机日志实证：Vela 给每个 page 起一个独立 JS VM（`new page, new vm`），
// list.ux 里 import 的 playerService 与 pages/player 里的是两个实例。
// 于是「当前播哪首」只能经 @system.storage 共享，多个 VM 会并发写同一条记录，
// 所以这里重点验证「只写自己改动的字段」不会把别人的数据冲掉。

console.log('\n[8] 跨 VM 共享播放态')

eq('空记录 → 默认值', normalizeShareState(null), {
  ver: 0,
  ts: 0,
  index: -1,
  queueVer: 0,
  state: '',
  loop: false,
})

eq('脏数据归一化', normalizeShareState({
  ver: -5,
  index: 'abc',
  queueVer: 'x',
  state: 'wtf',
  loop: 'yes',
}), {
  ver: 0,
  ts: 0,
  index: -1,
  queueVer: 0,
  state: '',
  loop: true,
})

// 音量不在共享态里：唯一真相是系统媒体音量（@system.volume，见第 11 节）。
// 老版本写过的 volume 字段必须被安静忽略 —— 既不能报错，也不能漏进归一化结果。
const legacyRecord = normalizeShareState({ ver: 3, index: 1, volume: 0.42 })
ok('老记录里的 volume 被忽略（共享态不含该字段）', !('volume' in legacyRecord), JSON.stringify(legacyRecord))
eq('忽略 volume 不影响其它字段', [legacyRecord.ver, legacyRecord.index], [3, 1])

// VM B（选歌页）点歌：只写 index / queueVer / state
const afterB = bumpShareState(
  { ver: 7, ts: 1, index: 3, queueVer: 100, state: 'paused', volume: 0.6, loop: false },
  { index: 8, queueVer: 200, state: 'loading' },
  1700000000000
)
eq('ver 自增', afterB.ver, 8)
eq('ts 采用注入值', afterB.ts, 1700000000000)
eq('B 的改动生效', [afterB.index, afterB.queueVer, afterB.state], [8, 200, 'loading'])
eq('B 没碰的循环原样保留', afterB.loop, false)
ok('写入后共享态依然没有 volume 字段', !('volume' in afterB), JSON.stringify(afterB))

// VM A（app VM）只是暂停：绝不能把 B 刚切的歌冲掉 ← 本 bug 的核心回归点
const afterA = bumpShareState(afterB, { state: 'paused' }, 1700000001000)
eq('A 暂停不影响 index', afterA.index, 8)
eq('A 暂停不影响 queueVer', afterA.queueVer, 200)
eq('A 暂停只改 state', afterA.state, 'paused')
eq('ver 继续自增', afterA.ver, 9)

const kept = bumpShareState(afterA, { state: 'not-a-state', volume: NaN, index: 'oops' }, 1)
eq('非法 state 不覆盖旧值', kept.state, 'paused')
eq('非法 index 不覆盖旧值', kept.index, 8)
ok('patch 里的 volume 不产生任何字段（音量已归系统）', !('volume' in kept), JSON.stringify(kept))

ok('首次对账（本地 -1）需要同步', isShareNewer(0, -1))
ok('版本相同无需同步', !isShareNewer(9, 9))
ok('版本变化需要同步', isShareNewer(10, 9))
ok('storage 被清空（ver 归零）也要同步', isShareNewer(0, 9))
ok(
  '队列版本变化才读队列',
  isQueueNewer(200, 100) && !isQueueNewer(200, 200) && isQueueNewer(0, -1)
)
ok(
  '日志描述含关键字段',
  describeShareState(afterA).indexOf('index=8') >= 0 &&
    describeShareState(afterA).indexOf('state=paused') >= 0,
  describeShareState(afterA)
)
ok(
  '日志描述里不再有音量字段',
  describeShareState(afterA).indexOf('vol') < 0,
  describeShareState(afterA)
)

/* --------- 9. 跨 VM 端到端：选歌页 VM 点歌 → 主页 VM 对账（真机故障回归） --------- */

// 这一段跑的是**真实的 playerService 代码**，不是提炼出来的模式：
// scripts/aiot-hooks.mjs 把 @system.* 换成桩，`?vm=` 查询串让 Node 把同一个文件
// 加载成多份互不共享模块级变量的实例 —— 等价于真机上 app / 选歌页 / 主页三个 VM
// （选歌页 = 更多/收藏夹/推荐等临时页面，语义同旧 list 页）。
//
// 真机故障现场：选歌页 VM 点歌能出声（@system.audio 是全局的），
// 但主页 VM 那份 player 仍是 queue=[], index=-1 → 回到主页永远「未在播放」。
// 只要有人把 adopt()（共享态对账）从页面里删掉，或让发布动作把对账水位推高，
// 这一节就会红。

console.log('\n[9] 跨 VM 端到端（选歌页 VM 点歌 → 主页 VM 对账）')

const PLAY_STATE_KEY = 'bilimusic_play_state'
const PLAYLIST_KEY = 'bilimusic_playlist'

const appVm = (await import('../src/services/playerService.js?vm=app')).default
const moreVm = (await import('../src/services/playerService.js?vm=more')).default
const homeVm = (await import('../src/services/playerService.js?vm=player')).default
// 音量页那个 VM：@system.volume 是全局原生服务，它读写的是同一份系统音量
const volumeVm = (await import('../src/services/playerService.js?vm=volume')).default

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

/** 轮询等条件成立：跨 VM 的写入要过几次 storage 异步回调，别用固定 sleep 赌时序 */
async function until(check, ms = 800) {
  const deadline = Date.now() + ms
  while (Date.now() < deadline) {
    if (check()) return true
    await wait(5)
  }
  return check()
}

const readShare = () => JSON.parse(storageStub.__dump()[PLAY_STATE_KEY] || '{}')

audioStub.__setDuration('https://cdn.example/BV1.m4s', 180)
audioStub.__setDuration('https://cdn.example/BV2.m4s', 200)
audioStub.__setDuration('https://cdn.example/BV3.m4s', 220)

appVm.init({ display: false, control: true }) // app VM：只绑控制类
homeVm.init() // 主页 VM：只绑展示类（拿不到队列的就是这一份实例）
// 每个 VM 各持一份 playerService 实例（urlResolver 也是各存一份），三个都得注入
const fakeResolver = async (track) => 'https://cdn.example/' + track.bvid + '.m4s'
appVm.setUrlResolver(fakeResolver)
homeVm.setUrlResolver(fakeResolver)
moreVm.setUrlResolver(fakeResolver)

await appVm.adopt() // 等价于 app.ux bootstrap
await homeVm.adopt()

const vmTracks = [
  { bvid: 'BV1', title: 'A', artist: 'u1', duration: 180 },
  { bvid: 'BV2', title: 'B', artist: 'u2', duration: 200 },
  { bvid: 'BV3', title: 'C', artist: 'u3', duration: 220 },
]

await moreVm.setQueue(vmTracks, 0) // 「播放全部」：来源页用整份列表建队列（内部会等取流 + 起播）
await until(() => readShare().state === 'playing') // 等 onplay 那条链路落定

eq('more VM 起播后拿到曲目', moreVm.getSnapshot().track.title, 'A')
ok('队列已落盘', String(storageStub.__dump()[PLAYLIST_KEY] || '').length > 0)
eq('主页 VM 对账前仍是空队列（真机故障现场）', homeVm.getSnapshot().track, null)
eq('共享态写下了 index', readShare().index, 0)
eq('共享态写下了 state', readShare().state, 'playing')

const homeSnap = await homeVm.adopt()
eq('★ 主页对账后拿到同一首', homeSnap.track.title, 'A')
eq('主页拿到队列长度', homeSnap.queueLength, 3)
eq('主页拿到播放状态', homeSnap.state, 'playing')
await until(() => homeVm.getSnapshot().duration > 0)
eq('主页进度环拿到时长（getPlayState 全局可读）', homeVm.getSnapshot().duration, 180)

// 通知栏「下一首」由 app VM 处理：必须先对账，不能拿自己那份旧队列切歌
audioStub.__emit('onnext')
await until(() => readShare().index === 1)
eq('app VM 基于共享态切到第 2 首', readShare().index, 1)
eq('more VM 本地还停在旧的（跨 VM 不共享内存）', moreVm.getSnapshot().index, 0)
eq('more VM 对账后跟上', (await moreVm.adopt()).index, 1)

// 播完自动下一首只由 app VM 处理：若两个 VM 都绑了 onended，这里会跳两首
audioStub.__emit('onended')
await until(() => readShare().index === 2)
eq('onended 只前进一首（没有重复处理）', readShare().index, 2)
eq('主页对账后跟到第 3 首', (await homeVm.adopt()).track.title, 'C')

// 读-改-写：只改音量的 VM 不能把别人刚切的 index 冲掉
//
// 音量本身**不进共享态**：改的是系统媒体音量（@system.volume），
// 任何 VM 都能直接读到真值，所以下面同时验证「应用没在自维护音量」。
const systemVolumeNow = () => volumeStub.__state().value

await moreVm.setVolume(0.25)
eq('setVolume 写的是系统音量', systemVolumeNow(), 0.25)
ok('共享态里没有被写入音量', !('volume' in readShare()), JSON.stringify(readShare()))
eq('改音量不影响别人刚切的 index', readShare().index, 2)
eq('音量镜像与本 VM 写入一致', moreVm.getSnapshot().volume, 0.25)
eq('不再改写 audio.volume（保持默认 = 跟随系统音量）', audioStub.__state().volume, 1)

// 外部改音量（实体键 / 系统设置 / 别的应用）：另一个 VM 读回来必须是同一个数
volumeStub.__setMediaValue(0.4)
eq('★ 另一个 VM 立刻读到外部音量', await homeVm.syncVolume(), 0.4)
eq('主页镜像与外部音量一致', homeVm.getSnapshot().volume, 0.4)

// 音量页：挂载即接管（事件 + 对账），加减改的也是系统音量
volumeVm.startVolumeWatch()
await until(() => volumeVm.getSnapshot().volume === 0.4)
eq('音量页挂载即读到系统音量', volumeVm.getSnapshot().volume, 0.4)

volumeStub.__setMediaValue(0.7)
await until(() => volumeVm.getSnapshot().volume === 0.7)
eq('★ 外部改音量 → 音量页跟着变（不再各调各的）', volumeVm.getSnapshot().volume, 0.7)

await volumeVm.setVolume(0.5)
eq('音量页 +/- 改的就是系统音量', systemVolumeNow(), 0.5)
eq('音量页镜像同步', volumeVm.getSnapshot().volume, 0.5)

volumeVm.stopVolumeWatch()
eq('解绑后把原生回调槽还回去', volumeStub.__handler(), null)

/* ------------- 9b. 队列移除（播放队列页 × 按钮的跨 VM 端到端） ------------- */

// 承接上一节的现场：队列 [A, B, C]，共享态 index=2（正在播 C）。
// removeFromQueue 的三条语义都必须过共享态走一遍，别的 VM 对账后才不会指错歌：
//   1) 移除当前曲目之前的歌 → 共享态 index 平移，播放不打断；
//   2) 移除正在播的歌 → 从同一位置接下去播（删的是队尾则环绕回队首）；
//   3) 队列被清空 → 停播回 idle（主页回到「点「更多」选歌播放」）。

console.log('\n[9b] 队列移除（removeFromQueue 跨 VM 端到端）')

await moreVm.adopt()
eq('more VM 先对账回当前曲目', moreVm.getSnapshot().track.title, 'C')

// 1) 移除 A（在当前曲目之前）：C 的下标 2 -> 1
await homeVm.removeFromQueue(0)
await until(() => readShare().index === 1)
eq('移除前面的歌后共享态 index 平移', readShare().index, 1)
eq('共享态 state 不被移除动作碰掉', readShare().state, 'playing')
eq('队列落盘少了一首', JSON.parse(storageStub.__dump()[PLAYLIST_KEY] || '[]').length, 2)
eq('移除方本 VM 仍在播 C', (await homeVm.adopt()).track.title, 'C')
eq('别的 VM 对账后同样指到 C', (await moreVm.adopt()).track.title, 'C')

// 2) 移除正在播的 C：队列 [B, C] -> [B]，从同一位置环绕接播 B
await homeVm.removeFromQueue(1)
await until(() => readShare().index === 0 && readShare().state === 'playing')
eq('移除当前曲目后接播下一首（环绕）', (await moreVm.adopt()).track.title, 'B')
eq('接播把 index 写回了共享态', readShare().index, 0)
eq('audio 确实在播新曲目', audioStub.__state().state, 'play')

// 3) 移除最后一首：队列清空，停播回 idle
await homeVm.removeFromQueue(0)
await until(() => readShare().index === -1 && readShare().state === 'idle')
eq('队列清空后回到 idle', readShare().state, 'idle')
eq('audio 已停止', audioStub.__state().state, 'stop')
const emptied = await homeVm.adopt()
eq('清空后队列长度为 0', emptied.queueLength, 0)
eq('清空后 track 为空', emptied.track, null)
eq('空队列再移除是 no-op', await homeVm.removeFromQueue(0), false)

/* -------- 9c. 点播与来源解耦（playTrackNow：更多页/收藏夹/推荐的单曲点按） -------- */

// 「收藏夹与播放列表解耦」的核心语义：来源列表页**只负责选歌**，不再像旧 list 页
// 那样用整份列表替换队列。单曲点播 = 已在队列里就跳播、否则插到当前曲目之后立即播。
// 连播整个来源走「播放全部」（setQueue，第 9 节已覆盖）。
//
// 承接 12b 的现场：队列刚被清空（idle）。

console.log('\n[9c] 点播与来源解耦（playTrackNow 跨 VM 端到端）')

const pickT1 = { bvid: 'BVP1', title: 'P1', artist: 'fav', duration: 100 }
const pickT2 = { bvid: 'BVP2', title: 'P2', artist: 'fav', duration: 110 }
const pickT3 = { bvid: 'BVP3', title: 'P3', artist: 'rcmd', duration: 120 }

// 1) 空队列点播：以这首歌建队列
const at1 = await moreVm.playTrackNow(pickT1)
eq('空队列点播返回下标 0', at1, 0)
await until(() => readShare().state === 'playing')
eq('空队列点播后队列就是这一首', JSON.parse(storageStub.__dump()[PLAYLIST_KEY]).map((t) => t.bvid), ['BVP1'])
eq('空队列点播即起播', (await moreVm.adopt()).track.title, 'P1')

// 2) 队列非空再点一首：插到当前曲目之后，旧队列原样保留
const at2 = await moreVm.playTrackNow(pickT2)
eq('第二首插在当前曲目之后', at2, 1)
eq('队列 = [P1, P2]（旧内容保留）', JSON.parse(storageStub.__dump()[PLAYLIST_KEY]).map((t) => t.bvid), ['BVP1', 'BVP2'])
eq('点播的歌立即播放', (await moreVm.adopt()).track.title, 'P2')

// 3) 点队列里已有的歌：跳播，不重复插入
const at3 = await moreVm.playTrackNow(pickT1)
eq('点已有曲目返回其队列下标', at3, 0)
eq('跳播不改变队列长度', JSON.parse(storageStub.__dump()[PLAYLIST_KEY]).length, 2)
eq('跳播后正在播 P1', (await moreVm.adopt()).track.title, 'P1')

// 4) 第三首：继续插在当前曲目之后，按点按顺序排列
const at4 = await moreVm.playTrackNow(pickT3)
eq('第三首仍插在当前曲目之后', at4, 1)
eq('队列 = [P1, P3, P2]', JSON.parse(storageStub.__dump()[PLAYLIST_KEY]).map((t) => t.bvid), ['BVP1', 'BVP3', 'BVP2'])
eq('共享态 index 指向点播的歌', readShare().index, 1)

// 5) 主页 VM 对账：看到的就是点播后的队列与当前曲目（跨 VM 一致性）
const pickSnap = await homeVm.adopt()
eq('主页对账拿到点播曲目', pickSnap.track.title, 'P3')
eq('主页对账拿到解耦后的队列长度', pickSnap.queueLength, 3)

// 6) 空曲目是 no-op
eq('playTrackNow(null) 返回 -1', await moreVm.playTrackNow(null), -1)

// 收尾：停掉 1 秒对账定时器，别让 Node 事件循环挂着
homeVm.stopTicking()
appVm.stopTicking()

/* ------- 9e. 不可见页面不重算进度（可见性挡广播，省电且零风险） ------- */

// 真机现场：播放页切到「更多 / 推荐」时页面**不销毁**，原生展示类事件
// （ontimeupdate 4HZ）仍绑在主页 VM 上 —— 只 stopTicking 挡不住那 4HZ，
// 不可见的页面照样每秒被喂约 5 次 progress（≈10 次 setField + 封面归一化 +
// session.isLoggedIn），在表上就是白烧电。这一节锁住两条纪律：
//   1) setVisible(false) 之后 progress 一律不广播（页面 onHide 调它）；
//   2) **只挡广播、不挡镜像刷新** —— 不可见期间 currentTime 照旧更新，
//      回到前台 adopt() 一读就是最新值，不存在「回来要等一秒才动」。
// 谁把 shouldEmitProgress 那道闸拆了、或者让可见性顺手把镜像刷新也掐了，这里都会红。

console.log('\n[9e] 不可见页面不重算进度（playerService.setVisible）')

const visVm = (await import('../src/services/playerService.js?vm=visible')).default
visVm.init() // 主页 VM 语义：绑展示类事件（含 ontimeupdate，4HZ 那条链路）
visVm.setUrlResolver(fakeResolver)

let progressEmits = 0
let lastPercent = -1
const unsubVis = visVm.subscribe((type, snap) => {
  if (type !== 'progress') return
  progressEmits++
  lastPercent = snap.percent
})

audioStub.__setDuration('https://cdn.example/BVS1.m4s', 120)
await visVm.setQueue([{ bvid: 'BVS1', title: 'S1', artist: 'u', duration: 120 }], 0)
// 状态拉回 PLAYING：audio 桩的播放态是全局的，9d 那节的 VM 之后可能把它停在
// pause，而本节第 2 步要验的正是「不可见时仍刷新镜像」，前提得干净。
// toggle 是双向的（在播时会暂停），所以先判一下再调。
if (visVm.getSnapshot().state !== 'playing') await visVm.toggle()
await until(() => visVm.getSnapshot().state === 'playing')

// 1) 不可见：原生 ontimeupdate 照发，但订阅方一次都不该被叫醒
visVm.setVisible(false)
const emittedBefore = progressEmits
audioStub.__tick(30)
await wait(30)
eq('★ 不可见时 ontimeupdate 不广播 progress', progressEmits - emittedBefore, 0)
eq('不可见时进度镜像照常刷新（只挡广播，回来即可读到最新值）', visVm.getSnapshot().currentTime, 30)

// 2) 不可见时的 1 秒对账（syncPlayState）同样只刷镜像、不广播
audioStub.__tick(5)
lastPercent = -1
await visVm.syncPlayState()
eq('对账把镜像推到 35s', visVm.getSnapshot().currentTime, 35)
eq('不可见时对账也不广播 progress', lastPercent, -1)

// 3) 回到前台：下一次原生事件照常广播（订阅方的快照计算随之恢复）
visVm.setVisible(true)
audioStub.__tick(5)
await until(() => progressEmits > emittedBefore)
ok('★ 可见恢复后进度事件立刻回来', progressEmits > emittedBefore, `emits=${progressEmits}`)
eq('恢复后的进度值正确', lastPercent, (40 / 120) * 100)

unsubVis()
visVm.stopTicking()
visVm.setVisible(false)

/* ------- 9d. 原生机型直链失败兜底（onerror 无载荷 → audioCache.refreshTrackFile） ------- */

// 真机现场（原生机型）：B 站 CDN 直链不接受空 Referer，而 @system.audio 的 src
// 发不了自定义请求头 → 直链时灵时不灵，「带 Referer 落盘再播」的兜底成了主路径。
// 这一节锁住兜底的四条纪律：
//   1) 兜底下载失败时把底层码翻成人话（Vela fetch 的 fail(code) 透传 libcurl：28=超时）；
//   2) Vela 的 onerror 不带参数（audio.d.ts: onerror(): void）且同轮故障连发多次：
//      兜底进行中 / 已停在错误态时的重复 onerror 必须吞掉——否则把进行中的抢救掐死、
//      把准确的报错冲成没有上下文的「播放失败：未知错误」（两条真机报错的直接来源）；
//   3) 兜底期间切歌：落盘完成也不得抢播旧歌的本地文件；
//   4) 兜底失败时已切歌：不得把旧歌的错甩到新歌头上（state/error 都不动）。

console.log('\n[9d] 原生机型直链失败兜底（onerror → audioCache.refreshTrackFile）')

const errVm = (await import('../src/services/playerService.js?vm=errfix')).default
errVm.init() // 绑展示类事件（含 onerror）——真机上兜底就是在这类 VM 里跑的
errVm.setUrlResolver(fakeResolver)
await errVm.adopt()

const errTracks = [
  { bvid: 'BVE1', title: 'E1', artist: 'u', duration: 60 },
  { bvid: 'BVE2', title: 'E2', artist: 'u', duration: 60 },
]
// 原生机型落盘现在走「@system.fetch + Range 分块」这条路（见 audioCache.downloadNativeToFile），
// 所以兜底要能成，必须先给这两个地址种上可下载的字节。
const bveBody = (n) => 'E' + n + '-' + String(n).repeat(64)
fetchStub.__setFile('https://cdn.example/BVE1.m4s', bveBody(1))
fetchStub.__setFile('https://cdn.example/BVE2.m4s', bveBody(2))
/** 落盘请求数：原生机型是 arraybuffer 的分块请求（不再是整份 responseType:'file'） */
const dlCount = () => fetchStub.__requests().filter((r) => r.responseType === 'arraybuffer').length
/** 缓存路径（与第 18 节同一套命名，起播命中/迟到的落盘都按它断言） */
const errFileStub = await import('../scripts/stubs/system.file.mjs')
const CACHE_DIR = CONFIG.AUDIO_CACHE.DIR
const errCacheNameOf = (key) => CONFIG.AUDIO_CACHE.PREFIX + key + CONFIG.AUDIO_CACHE.EXT
// 本节只关心 onerror 抢救链路：预取会在后台同时下载下一首（原生机型现在也预取），
// 它会跟「落盘失败/成功」的计数纠缠在一起，先关掉，第 19 节另有专门断言。
const prefetchWasOn = PLAY.PREFETCH
PLAY.PREFETCH = false
await errVm.setQueue(errTracks, 0)
await until(() => readShare().state === 'playing')
eq('兜底 VM 直链起播', errVm.getSnapshot().track.title, 'E1')

// 1) 直链失败 + 落盘也失败（持续超时）：报错必须是「码 + 人话」，不能只有一串 code=28
fetchStub.__setFailAlways(28, '')
audioStub.__emit('onerror')
await until(() => errVm.getSnapshot().state === 'error')
eq(
  '★ 兜底超时报错带 curl 码释义',
  errVm.getSnapshot().error,
  '直链与落盘均失败：code=28 网络超时 分块请求失败 code=28'
)

// 2) 错误态里的重复 onerror 被吞：准确报错不被冲成「未知错误」
audioStub.__emit('onerror')
await wait(20)
eq(
  '错误态吞掉重复 onerror',
  errVm.getSnapshot().error,
  '直链与落盘均失败：code=28 网络超时 分块请求失败 code=28'
)

// 3) 兜底进行中的重复 onerror 被吞：整个兜底只跑一轮分块下载
await errVm.playAt(0) // playAt 重置兜底标记，直链照常起播
await until(() => errVm.getSnapshot().state === 'playing')
fetchStub.__setFailAlways(28, '') // 保持失败
fetchStub.__setDelay(30)
const fileReqBefore = dlCount()
audioStub.__emit('onerror')
audioStub.__emit('onerror') // 同轮故障连发：第二次必须被 _recovering 守卫吞掉
await until(() => errVm.getSnapshot().state === 'error')
fetchStub.__setDelay(0)
eq(
  '重复 onerror 只跑一轮分块下载（= CHUNK_RETRIES 次尝试，不是两轮）',
  dlCount() - fileReqBefore,
  CONFIG.AUDIO_CACHE.CHUNK_RETRIES
)

// 4a) 兜底期间切歌：落盘完成也不抢播旧歌的本地文件
fetchStub.__setFailAlways(null) // 放行落盘：这次的兜底会成功
await errVm.playAt(1)
await until(() => errVm.getSnapshot().state === 'playing')
eq('已切到 E2', errVm.getSnapshot().track.title, 'E2')
fetchStub.__setDelay(40)
audioStub.__emit('onerror') // E2 直链失败，兜底开始下载 E2
await wait(10)
await errVm.playAt(0) // 兜底还在路上，用户切回 E1
audioStub.__emit('onerror') // E1 自己的直链也失败 → 它自己那份落盘（= 迟到的兜底）
await wait(10)
fetchStub.__setDelay(0)
// 等到两份落盘都转正（转正是异步的，固定 sleep 会跟分块次数赛跑）
await until(() => errFileStub.__exists(CACHE_DIR + errCacheNameOf('bv_BVE1')), 2000)
eq('迟到的兜底不抢播（仍在播 E1）', errVm.getSnapshot().track.title, 'E1')
ok(
  '★ 兜底完成但已切歌：旧歌的本地文件不抢播',
  audioStub.__state().src === 'https://cdn.example/BVE1.m4s',
  'src=' + audioStub.__state().src
)
// 迟到的落盘不是白干：E1 的完整文件留在缓存里，下次播它直接秒开
ok(
  '★ 迟到的落盘留在缓存（没白下，下次秒开）',
  errFileStub.__exists(CACHE_DIR + errCacheNameOf('bv_BVE1')),
  `miss ${CACHE_DIR + errCacheNameOf('bv_BVE1')} | files=${JSON.stringify(Object.keys(errFileStub.__files()))}`
)

// 4b) 兜底失败时已切歌：错误不甩给新歌
fetchStub.__setFailAlways(28, '')
fetchStub.__setDelay(40)
audioStub.__emit('onerror') // E1 直链失败，兜底开始下载 E1
await wait(10)
await errVm.playAt(1) // 用户切到 E2
fetchStub.__setDelay(0)
await wait(120) // 让迟到的兜底走完（失败）
eq('迟到的兜底失败不影响新歌（仍在播 E2）', errVm.getSnapshot().track.title, 'E2')
ok(
  '★ 迟到的兜底失败不污染新曲目（无错误态）',
  errVm.getSnapshot().state === 'playing' && errVm.getSnapshot().error === '',
  `state=${errVm.getSnapshot().state} error=${errVm.getSnapshot().error}`
)

// 5) ★ 直链额度：候选要逐条试完（额度 3）之后**必须**转落盘。
//    早期版本在 ① 换候选那里用一个「整轮只抢救一次」的开关卡住，换了 1 条候选就
//    直接报「播放失败：直链播放失败」，落盘兜底永远轮不到 —— 真机上「upos 全档 +
//    唯一 mcdn 在别档」的稿件必现（用户报告的固定失败对就是这么来的）。
{
  fetchStub.__setFailAlways(null)
  fetchStub.__setDelay(0)
  const ladder = (n) => `https://l${n}.mcdn.bilivideo.cn:8082/audio.m4s`
  // 只给最后一条候选种字节：下载阶段逐条试，前两条失败、第三条成功
  fetchStub.__setFile(ladder(3), 'LADDER-BODY')
  errVm.setUrlResolver(async () => [ladder(1), ladder(2), ladder(3)])
  await errVm.setQueue([{ bvid: 'BVL1', title: 'L1', artist: 'u', duration: 60 }], 0)
  await until(() => errVm.getSnapshot().state === 'playing')
  eq('直链起播用的是第一条候选', audioStub.__state().src, ladder(1))

  audioStub.__emit('onerror') // ① 换候选（额度还剩 2）
  await until(() => audioStub.__state().src === ladder(2))
  eq('直链失败换第 2 条候选', audioStub.__state().src, ladder(2))

  audioStub.__emit('onerror') // ① 换候选（额度用尽）
  await until(() => audioStub.__state().src === ladder(3))
  eq('直链失败换第 3 条候选', audioStub.__state().src, ladder(3))

  audioStub.__emit('onerror') // 额度用尽 → ② 落盘
  await until(
    () => errVm.getSnapshot().state === 'playing' && /^internal:\/\//.test(audioStub.__state().src),
    3000
  )
  ok(
    '★ 直链额度用尽后落到「带 Referer 落盘」，而不是报「直链播放失败」',
    errVm.getSnapshot().error === '' && /^internal:\/\//.test(audioStub.__state().src),
    `state=${errVm.getSnapshot().state} src=${audioStub.__state().src} error=${errVm.getSnapshot().error}`
  )
  ok(
    '落盘确实是逐条候选试出来的（不是只认第一条）',
    dlCount() > 0,
    'arraybuffer 分块请求数=' + dlCount()
  )
  errVm.setUrlResolver(fakeResolver)
}

// 6) ★ 过期地址绝不重用。曲目对象上的 `track.streams` 会活一整个会话（预取还更早把
//    地址取回来放着），而 CDN 地址的 deadline 实测只有 120 分钟 —— 拿一个过期地址去
//    请求，CDN 回的正是 403，与「防盗链拒绝」长得一模一样，排查时最容易被带偏。
{
  const expired = 'https://upos-sz-mirror08c.bilivideo.com/old.m4s?deadline=1000000000&upsig=x'
  const freshUrl = 'https://xy.mcdn.bilivideo.cn:8082/new.m4s'
  let resolveCalls = 0
  errVm.setUrlResolver(async () => {
    resolveCalls++
    return [freshUrl]
  })
  await errVm.setQueue(
    [{ bvid: 'BVO1', title: 'O1', artist: 'u', duration: 60, streams: [expired] }],
    0
  )
  await until(() => errVm.getSnapshot().state === 'playing')
  eq('★ 曲目上缓存的过期地址不被采用（改为重新取流）', audioStub.__state().src, freshUrl)
  ok('确实重新调用了取流解析器', resolveCalls > 0, '解析次数=' + resolveCalls)
  errVm.setUrlResolver(fakeResolver)
}

fetchStub.__setFailAlways(null)
fetchStub.__reset()
PLAY.PREFETCH = prefetchWasOn
errFileStub.__reset() // 9d 种的缓存文件清掉，别污染第 18 节的目录断言
errVm.stopTicking()

/* ------------- 10. manifest 后台运行声明（真机「回主页就停播」的根因） ------------- */

// 真机现场：起播后回到设备主页（表盘），播放立刻中断，日志 `app not support background running`。
//
// 官方机制见 https://iot.mi.com/vela/quickapp/zh/guide/framework/other/background-running.html ——
// 切后台时系统检查两个条件，缺一即停：
//   1. manifest.json 的 config.background.features 里声明了后台运行接口；
//   2. 该接口此刻确实在跑（音频场景 = 正在播）。
// 后台运行接口只有 system.audio / system.request / system.geolocation，
// 且「config.background 里声明的，最外层 features 也必须声明」。
//
// 这一节就是防回归：谁把 config.background 删了，`npm run verify` 立刻变红，
// 不要再花时间刷机复现一次「回主页就静音」。

console.log('\n[10] manifest 后台运行声明')

const manifest = JSON.parse(readFileSync(new URL('../src/manifest.json', import.meta.url), 'utf8'))
const backgroundFeatures =
  (manifest.config && manifest.config.background && manifest.config.background.features) || []
const topFeatures = (manifest.features || []).map((f) => f && f.name)
const BACKGROUND_CAPABLE = ['system.audio', 'system.request', 'system.geolocation']

ok(
  'config.background.features 已声明 system.audio（音乐类应用的后台运行凭据）',
  backgroundFeatures.indexOf('system.audio') >= 0,
  `实际：${JSON.stringify(backgroundFeatures)}`
)
ok(
  '后台运行接口在声明范围内（system.audio / system.request / system.geolocation）',
  backgroundFeatures.every((name) => BACKGROUND_CAPABLE.indexOf(name) >= 0),
  `越界项：${JSON.stringify(backgroundFeatures.filter((n) => BACKGROUND_CAPABLE.indexOf(n) < 0))}`
)
ok(
  '后台接口同时出现在最外层 features（两处都要写）',
  backgroundFeatures.every((name) => topFeatures.indexOf(name) >= 0),
  `最外层 features：${JSON.stringify(topFeatures)}`
)
// app.ux 自己不 import 也算数：它 bootstrap 里 init 播放服务，音频模块由本 VM 的
// playerService 引入。所以检查的是「app 启动链路里有人把 @system.audio 用起来」。
const appUxSource = readFileSync(new URL('../src/app.ux', import.meta.url), 'utf8')
const playerServiceSource = readFileSync(
  new URL('../src/services/playerService.js', import.meta.url),
  'utf8'
)
ok(
  'app 启动链路里 import 了 @system.audio（后台接口要在 app VM 用起来，页面 VM 会被销毁）',
  appUxSource.indexOf('@system.audio') >= 0 || playerServiceSource.indexOf('@system.audio') >= 0,
  'app.ux 与 playerService 都没有 import @system.audio'
)

// 10b. 路由接线：旧「播放列表页」已被「更多」页取代（收藏夹与播放列表解耦）
const ROUTER_PAGES = Object.keys((manifest.router && manifest.router.pages) || [])
ok('入口仍是播放页', manifest.router.entry === 'pages/player', manifest.router.entry)
;[
  'pages/more',
  'pages/recommend',
  'pages/fav',
  'pages/favDetail',
  'pages/login',
  'pages/volume',
  'pages/about',
].forEach((p) => ok('路由已声明 ' + p, ROUTER_PAGES.indexOf(p) >= 0))
ok(
  '旧播放列表页已从路由移除（pages/list → pages/more，收藏夹不再兼任播放列表）',
  ROUTER_PAGES.indexOf('pages/list') < 0
)
;['more', 'recommend', 'fav', 'favDetail'].forEach((name) => {
  const src = readFileSync(new URL(`../src/pages/${name}/${name}.ux`, import.meta.url), 'utf8')
  ok(
    name + '.ux 不直接碰 @system.audio（临时页面不绑音频事件）',
    src.indexOf('@system.audio') < 0
  )
  // fav 页只列收藏夹文件夹，不碰播放；其余三页经 playerService 消费播放能力
  if (name !== 'fav') {
    ok(name + '.ux 走 playerService 消费播放能力', src.indexOf('services/playerService') >= 0)
    ok(
      name + '.ux 不调用 playerService.init（事件绑定纪律：app VM 控制 / 主页展示）',
      src.indexOf('playerService.init') < 0
    )
  }
})

// 10c. 登录页：底部只有一个居中「返回」，刷新走二维码本身
//
// 登录页在栈里永远是被 push 上来的（更多页用户卡片 / 更多页收藏夹入口 / 收藏夹空态入口），
// 「回哪去」只有一个答案。旧版登录成功后 `router.replace({uri:'/pages/more'})`：
// 从更多页进来的话，那跟按返回是同一个去处（用户感知就是按钮白给），
// 还会在栈里多压一层「更多」（player → more → more），把 recommend 的 back(2) /
// favDetail 的 back(3) 依赖的「固定入口链」深度整体带偏。
// 操作区收敛成一个居中「返回」后，「刷新二维码」按钮也去掉了：重新出码 = 点二维码本身
// （失效、加载失败同样点它重试），页面底部不再并排两个按钮。
const loginUxSource = readFileSync(new URL('../src/pages/login/login.ux', import.meta.url), 'utf8')
// 扫码登录只剩 TV 一条路（Web 端已移除，见第 6b 节），登录页不该再留模式相关的文案与分支
ok(
  'login.ux 不再区分扫码方式（没有 Web 端 / 模式切换残留）',
  loginUxSource.indexOf('Web 端') < 0 &&
    loginUxSource.indexOf('扫码方式') < 0 &&
    loginUxSource.indexOf('.mode') < 0,
  '登录页仍有扫码方式相关的残留'
)
ok(
  'login.ux 里没有「更多」页跳转（登录页不自己决定去哪）',
  loginUxSource.indexOf('/pages/more') < 0,
  '登录页里仍有 /pages/more'
)
ok(
  'login.ux 只 back，不 push / replace（登录页不改变入口链深度）',
  loginUxSource.indexOf('router.back()') >= 0 &&
    loginUxSource.indexOf('router.replace') < 0 &&
    loginUxSource.indexOf('router.push') < 0
)
ok(
  'login.ux 底部只有一个按钮，且是「返回」（不再是「刷新二维码」+「返回」两个）',
  (loginUxSource.match(/class="btn"/g) || []).length === 1 &&
    /<div class="btn" onclick="goBack">/.test(loginUxSource) &&
    loginUxSource.indexOf('刷新二维码') < 0,
  `btn 数量：${(loginUxSource.match(/class="btn"/g) || []).length}`
)
ok(
  'login.ux 操作区居中排布（justify-content: center）',
  /\.actions\s*\{[^}]*justify-content:\s*center/.test(loginUxSource),
  '操作区不再是居中排布'
)
ok(
  'login.ux 点二维码重新出码（qr-box 与 <qrcode> 都绑 onQrTap，onQrTap 调 startLogin）',
  /<div class="qr-box" onclick="onQrTap">/.test(loginUxSource) &&
    /<qrcode[^>]*onclick="onQrTap"/.test(loginUxSource) &&
    /onQrTap\(\)\s*\{[\s\S]*?startLogin\(\)/.test(loginUxSource),
  '二维码区域没绑重取逻辑'
)
ok(
  'login.ux 已登录时不重取、出码在飞时吞掉连点（busy 守卫）',
  /onQrTap\(\)\s*\{[\s\S]*?loggedIn[\s\S]*?busy[\s\S]*?return/.test(loginUxSource) &&
    /if \(this\.busy\) return;/.test(loginUxSource) &&
    /this\.busy = true;/.test(loginUxSource),
  '缺少 loggedIn / busy 守卫'
)
// 登录页永远是被 push 上来的：每个入口都必须是 push，back 才有上一页可回
;['more', 'fav'].forEach((name) => {
  const src = readFileSync(new URL(`../src/pages/${name}/${name}.ux`, import.meta.url), 'utf8')
  const mentions = (src.match(/\/pages\/login/g) || []).length
  const pushes = (src.match(/router\.push\(\{\s*uri:\s*"\/pages\/login"\s*\}\)/g) || []).length
  ok(
    name + '.ux 进登录页只走 router.push（登录页 back 必有上一页可回）',
    mentions > 0 && mentions === pushes,
    `提及 ${mentions} 次，push ${pushes} 次`
  )
})
// 从登录页 back 回收藏夹时，收藏夹要自己重试，否则停在「未登录」空态
const favUxSource = readFileSync(new URL('../src/pages/fav/fav.ux', import.meta.url), 'utf8')
const favOnShow = /onShow\(\)\s*\{[\s\S]*?\n {2}\},/.exec(favUxSource)
ok(
  'fav.ux 从登录页 back 回来会自愈（onShow 里带 needLogin 守卫再 reload）',
  !!favOnShow && /needLogin/.test(favOnShow[0]) && /reload\(\)/.test(favOnShow[0]),
  favOnShow ? favOnShow[0].replace(/\s+/g, ' ') : '找不到 onShow'
)

/* ------------- 11. 系统音量：@system.volume 是唯一真相 ------------- */

// 这一节防的是「应用自己又攒了一份音量」的回归：
//   - 音量必须读写 @system.volume（setMediaValue / getMediaValue），
//     这样用户在实体键、系统设置里改的音量与应用显示的是同一个数；
//   - 不能写 audio.volume 当常规路径（它的默认值就是系统媒体音量，
//     写它等于把音量变成「播放器 × 系统」两级串联，两边再也不一致）；
//   - 不再有应用侧的持久化音量（共享态 volume 字段 / settings_volume 老键）。
//
// 文档：https://iot.mi.com/vela/quickapp/zh/features/system/volume.html

console.log('\n[11] 系统音量（@system.volume）')

// 11a. 换算与步进（纯函数，volume.ux 直接用，见 common/volume.js）
eq(
  'clampVolume 归一与兜底',
  [clampVolume(2), clampVolume(-1), clampVolume('0.5'), clampVolume(NaN, 0.3), clampVolume(0)],
  [1, 0, 0.5, 0.3, 0]
)
eq('toPercent', [toPercent(0), toPercent(0.255), toPercent(1), toPercent(NaN)], [0, 26, 100, 0])
eq('stepPercent 减到 0 吸附', [stepPercent(10, -1), stepPercent(9, -1), stepPercent(0, -1)], [0, 0, 0])
eq('stepPercent 加到满吸附', [stepPercent(90, 1), stepPercent(91, 1), stepPercent(100, 1)], [100, 100, 100])
eq('stepPercent 常规步进', [stepPercent(50, 1), stepPercent(50, -1)], [60, 40])

// 11b. 桩的语义（与真机对齐）：系统音量全进程一份，回调槽后设置者覆盖
volumeStub.__reset()
// 先排空上一节遗留的异步原生回调：不然上一节 setMediaValue 派发的事件
// 会落到这一节刚绑上的回调上，看上去像「凭空多来了一次」
await wait(20)
eq('系统音量初始值', volumeStub.__state().value, 1)

const volumeEvents = []
volumeStub.default.onMediaValueChanged = (res) => volumeEvents.push(res.value)
volumeStub.__setMediaValue(0.3)
await until(() => volumeEvents.length === 1)
eq('外部改音量派发 onMediaValueChanged', volumeEvents, [0.3])
await wait(20)
eq('值没有变化时不重复派发', volumeEvents, [0.3])
volumeStub.__setMediaValue(5)
eq('音量越界时被夹到 1.0', volumeStub.__state().value, 1)
volumeStub.default.onMediaValueChanged = null
eq('回调槽可被清空（页面销毁时解绑）', volumeStub.__handler(), null)
volumeStub.__reset()

// 11c. manifest 与分层
const volumeUxSource = readFileSync(new URL('../src/pages/volume/volume.ux', import.meta.url), 'utf8')
ok(
  'manifest 声明了 system.volume（不声明则接口不可用）',
  topFeatures.indexOf('system.volume') >= 0,
  `实际：${JSON.stringify(topFeatures)}`
)
ok(
  'system.volume 不写进后台运行凭据（后台只认 audio/request/geolocation）',
  backgroundFeatures.indexOf('system.volume') < 0,
  `实际：${JSON.stringify(backgroundFeatures)}`
)
ok(
  '播放服务走 @system.volume 读写音量',
  playerServiceSource.indexOf('setMediaValue') >= 0 &&
    playerServiceSource.indexOf('getMediaValue') >= 0,
  'playerService 里找不到 setMediaValue / getMediaValue'
)
ok(
  '播放服务不再把音量发布进共享态',
  playerServiceSource.indexOf('publishShareState({ volume') < 0,
  'playerService 里仍有 publishShareState({ volume ... })'
)
ok(
  '音量页通过 playerService + 纯函数改音量，不直接 import @system',
  !/from\s+['"]@system\.volume['"]/.test(volumeUxSource) &&
    volumeUxSource.indexOf('playerService') >= 0 &&
    volumeUxSource.indexOf('common/volume') >= 0,
  '音量页里出现了 @system.volume 的 import，或没走 playerService / common/volume'
)

// 11d. 音量页布局：官方音量示例的样式（音量条吃满屏宽 + 贴底圆形关闭钮）。
// 防两类回归：一是页面又被套回 .safe / safeInsetPx 体系（音量条垂直居中，
// 圆屏中线就是整屏最宽处，收进内接正方形纯属浪费）；二是返回钮被改回
// 「‹ 标题」头部（本页与其它页不同，官方示例就是贴底圆形关闭钮）。
ok(
  '音量页不做安全区（无 .safe 容器，也不算 safeInsetPx / 不碰 deviceService）',
  volumeUxSource.indexOf('class="safe"') < 0 &&
    volumeUxSource.indexOf('safeInsetPx') < 0 &&
    volumeUxSource.indexOf('services/deviceService') < 0,
  '音量页里出现了安全区容器 / safeInsetPx / deviceService'
)
ok(
  '音量条容器吃满屏宽（垂直居中 ⇒ 圆屏中线放得下，不再左右内缩）',
  /volume-bar-container\s*\{[^}]*width:\s*100%/.test(volumeUxSource)
)
ok(
  '音量页返回走贴底圆形关闭钮（官方示例：cancel.png → goBack，无「‹ 标题」头部）',
  volumeUxSource.indexOf('cancel.png') >= 0 &&
    volumeUxSource.indexOf('goBack') >= 0 &&
    /cancel-container\s*\{[^}]*border-radius:\s*50%/.test(volumeUxSource) &&
    volumeUxSource.indexOf('header-back') < 0,
  '音量页缺少贴底关闭钮，或又出现了头部返回'
)

/* ------------- 12. 设备能力：封面背景图白名单 + 圆屏安全区 ------------- */

// 这一节防两类回归：
//
// 1) 白名单被放宽成「默认允许」。官方《背景图样式》支持明细里，
//    小米 S1 Pro / 手环 8 Pro / 手环 9 / 9 Pro / Watch S3 / Redmi Watch 4
//    都是「不支持」—— 在这些机型上铺背景图就是糊一屏。所以语义必须是
//    **白名单**：没命中就不渲染（fail-closed），连 getInfo 失败也一样。
//
// 2) 圆屏安全区被改回「百分比宽盒子 + 交叉轴居中」。那条链路在真机上会**左锚定**：
//    右边组件被收进 71% 处（视觉上挤到中间），左边却贴着屏幕边缘（用户实测）。
//    现在安全区 = 全宽容器 + 左右各内缩**同一个 px 值**（数值来自
//    common/device.js 的 safeHorizontalInsetPx，按 getInfo 的屏宽算出，
//    designWidth=device-width 故 px 即物理像素），对称由构造保证。
//    这一节钉住「页面绑定内联 padding」与「.safe 全宽、形状 class 无宽度」
//    这两件事不被改回去。
//
// 为什么走 @system.device 而不是 @media：见 common/device.js 顶部注释
// （媒体查询对 S1 Pro / Redmi Watch 4 / 手环 8 Pro 机型不支持，而 S1 Pro 是圆屏）。
//
// 文档：
//   设备信息      https://iot.mi.com/vela/quickapp/zh/features/basic/device.html
//   多屏设计      https://iot.mi.com/vela/quickapp/zh/guide/design/multi-screens.html
//   背景图样式    https://iot.mi.com/vela/quickapp/zh/components/general/background-img-styles.html
//   媒体查询      https://iot.mi.com/vela/quickapp/zh/guide/framework/style/media-query.html

console.log('\n[12] 设备能力（背景图白名单 + 圆屏安全区）')

// 12a. 白名单语义：官方支持明细逐条对照
const whitelistHit = [
  ['Xiaomi Watch S4', { brand: 'Xiaomi', manufacturer: 'Xiaomi', model: 'Xiaomi Watch S4', product: 's4' }],
  ['Xiaomi Watch S4 Sport（同代同平台）', { brand: 'Xiaomi', model: 'Watch S4 Sport' }],
  ['Xiaomi Watch S5', { brand: 'Xiaomi', model: 'Watch S5' }],
  ['REDMI Watch 5（品牌与型号分列）', { brand: 'Redmi', model: 'Watch 5' }],
  ['REDMI Watch 5（品牌写在型号里）', { model: 'REDMI Watch 5' }],
  ['REDMI Watch 6', { brand: 'Redmi', model: 'REDMI Watch 6' }],
  ['小米手环 10', { brand: 'Xiaomi', model: '小米手环 10' }],
  ['小米手环 10（产品代号）', { product: 'smartband10' }],
]
whitelistHit.forEach(([name, info]) => {
  ok('白名单命中：' + name, supportsCoverBackground(normalizeDeviceInfo(info)))
})

const whitelistMiss = [
  ['小米 S1 Pro（圆屏但不支持背景图）', { brand: 'Xiaomi', model: 'Xiaomi Watch S1 Pro' }],
  ['小米手环 8 Pro', { brand: 'Xiaomi', model: '小米手环 8 Pro' }],
  ['小米手环 9', { brand: 'Xiaomi', model: '小米手环 9' }],
  ['小米手环 9 Pro', { brand: 'Xiaomi', model: '小米手环 9 Pro' }],
  ['Xiaomi Watch S3', { brand: 'Xiaomi', model: 'Xiaomi Watch S3' }],
  ['Redmi Watch 4', { brand: 'Redmi', model: 'Redmi Watch 4' }],
  ['腕部心电血压记录仪', { brand: 'Xiaomi', model: '小米腕部心电血压记录仪' }],
  ['未知机型', { brand: 'Xiaomi', model: 'Xiaomi Watch X' }],
  ['空信息（fail-closed）', null],
]
whitelistMiss.forEach(([name, info]) => {
  ok('白名单拒绝：' + name, !supportsCoverBackground(normalizeDeviceInfo(info)))
})

eq(
  '归一化会容忍字段缺失与类型不对',
  normalizeDeviceInfo({ model: 'X', screenWidth: '466', screenHeight: null }),
  {
    available: true,
    brand: '',
    manufacturer: '',
    model: 'X',
    product: '',
    deviceType: '',
    screenShape: '',
    screenWidth: 466,
    screenHeight: 0,
    screenDensity: 0,
    apiLevel: 0,
  }
)
eq('getInfo 整个失败（传 null）-> available=false', normalizeDeviceInfo(null).available, false)

// 12b. 屏幕形状：原生 screenShape 优先，缺失时按宽高比兜底
eq('screenShape 原样透传（circle）', resolveScreenShape({ screenShape: 'circle' }), 'circle')
eq('screenShape 原样透传（pill-shaped）', resolveScreenShape({ screenShape: 'pill-shaped' }), 'pill-shaped')
eq('screenShape 大小写不敏感', resolveScreenShape({ screenShape: 'CIRCLE' }), 'circle')
// 下面这些期望值取自官方《多屏设计》的设备数据表
eq('兜底 466x466 -> 圆屏（Watch S4/S5）', resolveScreenShape({ screenWidth: 466, screenHeight: 466 }), 'circle')
eq('兜底 480x480 -> 圆屏（S1 Pro）', resolveScreenShape({ screenWidth: 480, screenHeight: 480 }), 'circle')
eq('兜底 432x514 -> 矩形屏（REDMI Watch 5）', resolveScreenShape({ screenWidth: 432, screenHeight: 514 }), 'rect')
eq('兜底 336x480 -> 矩形屏（手环 8 Pro / 9 Pro）', resolveScreenShape({ screenWidth: 336, screenHeight: 480 }), 'rect')
eq('兜底 212x520 -> 胶囊屏（手环 10）', resolveScreenShape({ screenWidth: 212, screenHeight: 520 }), 'pill-shaped')
eq('兜底 192x490 -> 胶囊屏（手环 9）', resolveScreenShape({ screenWidth: 192, screenHeight: 490 }), 'pill-shaped')
eq('什么都没给 -> 矩形屏（保守）', resolveScreenShape(null), 'rect')
eq('尺寸非法 -> 矩形屏（保守）', resolveScreenShape({ screenWidth: 0, screenHeight: 'x' }), 'rect')

// 12c. 安全区左右内缩（px，按屏宽 × 内缩比例取整）
ok(
  '圆屏安全宽 = 内接正方形（1/√2 ≈ 70.7%）',
  CIRCLE_SAFE_WIDTH_PERCENT === Math.round(100 / Math.SQRT2),
  `实际 ${CIRCLE_SAFE_WIDTH_PERCENT}`
)
eq('圆屏 466 -> 左右各 68px', safeHorizontalInsetPx({ screenShape: 'circle', screenWidth: 466, screenHeight: 466 }), 68)
eq('圆屏 480 -> 左右各 70px', safeHorizontalInsetPx({ screenShape: 'circle', screenWidth: 480, screenHeight: 480 }), 70)
eq('圆屏内缩后内容宽回到 CIRCLE_SAFE_WIDTH_PERCENT', Math.round(((466 - 2 * 68) / 466) * 100), CIRCLE_SAFE_WIDTH_PERCENT)
eq('矩形屏 466x514 -> 左右各 28px', safeHorizontalInsetPx({ screenShape: 'rect', screenWidth: 466, screenHeight: 514 }), 28)
eq('胶囊屏 -> 0（维持全宽）', safeHorizontalInsetPx({ screenShape: 'pill-shaped', screenWidth: 212, screenHeight: 520 }), 0)
eq('拿不到设备信息 -> 480 宽矩形屏兜底', safeHorizontalInsetPx(normalizeDeviceInfo(null)), 29)
eq(
  '屏宽非法 -> 按兜底基准宽 480 计算',
  safeHorizontalInsetPx({ screenShape: 'circle', screenWidth: 0 }),
  Math.round(480 * SAFE_HORIZONTAL_INSET.circle)
)
eq(
  '形状 -> 根节点 class',
  [
    shapeClassOf({ screenShape: 'circle' }),
    shapeClassOf({ screenShape: 'rect' }),
    shapeClassOf({ screenShape: 'pill-shaped' }),
  ],
  ['shape-circle', 'shape-rect', 'shape-pill']
)

// 12d. 封面地址归一化
eq(
  '协议相对地址补 https 并追加缩略参数',
  normalizeCoverUrl('//i2.hdslb.com/bfs/archive/abc.jpg'),
  'https://i2.hdslb.com/bfs/archive/abc.jpg' + COVER_THUMB_SUFFIX
)
eq(
  'http 升 https',
  normalizeCoverUrl('http://i0.hdslb.com/bfs/archive/abc.jpg'),
  'https://i0.hdslb.com/bfs/archive/abc.jpg' + COVER_THUMB_SUFFIX
)
eq(
  '已带处理参数不重复追加',
  normalizeCoverUrl('https://i0.hdslb.com/x.jpg@320w_320h_1c.jpg'),
  'https://i0.hdslb.com/x.jpg@320w_320h_1c.jpg'
)
eq(
  '只认 png/jpg（webp 不在 image 组件支持列表里，别自己换后缀）',
  COVER_THUMB_SUFFIX.indexOf('.jpg') > 0 && COVER_THUMB_SUFFIX.indexOf('webp') < 0,
  true
)
eq(
  '空 / 非法地址 -> 空串（调用方据此不渲染背景层）',
  [normalizeCoverUrl(''), normalizeCoverUrl(null), normalizeCoverUrl('ftp://x/y.jpg')],
  ['', '', '']
)

// 12e. deviceService 端到端（走 @system.device 桩）
const deviceStub = await import('../scripts/stubs/system.device.mjs')
deviceStub.__reset()

const deviceService = await import('../src/services/deviceService.js?vm=device')

// 未就绪时必须已经是保守结论：矩形屏 + 不渲染背景图 + 页高兜底 0。
// 页面拿这些值渲染首帧，所以「先松后紧」会比「先紧后松」安全。
eq('未就绪 -> 形状 class', deviceService.capabilities().shapeClass, 'shape-rect')
eq('未就绪 -> 不渲染背景图', deviceService.capabilities().coverBackground, false)
eq('未就绪 -> 页高兜底 0（页面自行取 480）', deviceService.capabilities().pageHeightPx, 0)
eq('未就绪 -> 页宽兜底 0（页面自行取 480）', deviceService.capabilities().pageWidthPx, 0)

// 桩默认 = Xiaomi Watch S4（圆屏 + 白名单内）
const devInfo = await deviceService.whenReady()
eq('设备信息归一化', [devInfo.available, devInfo.brand, devInfo.model], [true, 'Xiaomi', 'Xiaomi Watch S4'])
eq(
  '就绪后 -> 圆屏 + 安全内缩 + 允许背景图',
  [
    deviceService.capabilities().shape,
    deviceService.capabilities().safeInsetPx,
    deviceService.capabilities().coverBackground,
  ],
  ['circle', 68, true]
)
eq('原生接口只问一次', deviceStub.__calls(), 1)
await deviceService.whenReady()
eq('whenReady 幂等（不会每次都打原生）', deviceStub.__calls(), 1)

// 换一台不在白名单的圆屏机（S1 Pro）：安全区照做，但背景图必须关掉
deviceStub.__setInfo({ model: 'Xiaomi Watch S1 Pro', product: 's1pro', screenWidth: 480, screenHeight: 480 })
deviceService.reset()
await deviceService.whenReady()
eq('S1 Pro -> 圆屏安全区仍然生效', deviceService.capabilities().safeInsetPx, 70)
eq('S1 Pro -> 背景图关掉', deviceService.capabilities().coverBackground, false)
eq('S1 Pro -> 页高 px = 屏高（scroll 两屏成页用）', deviceService.capabilities().pageHeightPx, 480)
eq('S1 Pro -> 页宽 px = 屏宽（scroll 横向两屏成页用）', deviceService.capabilities().pageWidthPx, 480)

// getInfo 失败 / 同步抛错（老 runtime 没有 system.device）：绝不能把页面拖挂
deviceStub.__setMode('fail')
deviceService.reset()
const failInfo = await deviceService.whenReady()
eq(
  'getInfo 走 fail 回调 -> 不 reject，退化成保守值',
  [failInfo.available, deviceService.capabilities().shapeClass, deviceService.capabilities().coverBackground],
  [false, 'shape-rect', false]
)

deviceStub.__setMode('throw')
deviceService.reset()
const throwInfo = await deviceService.whenReady()
eq(
  'getInfo 同步抛错 -> 同样兜住',
  [throwInfo.available, deviceService.capabilities().shapeClass],
  [false, 'shape-rect']
)
deviceStub.__reset()

// 12f. manifest 声明与页面接线
ok(
  'manifest 声明了 system.device（不声明则接口不可用）',
  topFeatures.indexOf('system.device') >= 0,
  `实际：${JSON.stringify(topFeatures)}`
)
ok(
  'system.device 不写进后台运行凭据（后台只认 audio/request/geolocation）',
  backgroundFeatures.indexOf('system.device') < 0,
  `实际：${JSON.stringify(backgroundFeatures)}`
)

// 音量页不在此列：它整体走官方音量示例的布局 —— 音量条垂直居中，圆屏中线就是
// 整屏最宽处，吃满屏宽也不出圆弧，不需要安全区；下面只有贴底圆形关闭钮
// （断言见第 11d 节）。
const SAFE_WIRED_PAGES = [
  'player/player',
  'more/more',
  'recommend/recommend',
  'fav/fav',
  'favDetail/favDetail',
  'login/login',
  'about/about',
]
const SAFE_STYLE_BINDING =
  'style="padding-left: {{ safeInsetPx }}px; padding-right: {{ safeInsetPx }}px"'
SAFE_WIRED_PAGES.forEach((page) => {
  const src = readFileSync(new URL(`../src/pages/${page}.ux`, import.meta.url), 'utf8')

  ok(`${page}.ux 挂了安全区容器`, src.indexOf('class="safe"') >= 0)
  ok(
    `${page}.ux 左右内缩绑同一个 px 值（对称由构造保证）`,
    src.indexOf(SAFE_STYLE_BINDING) >= 0
  )
  ok(
    `${page}.ux 用 deviceService 算安全区`,
    src.indexOf('services/deviceService') >= 0 && src.indexOf('safeInsetPx') >= 0
  )

  // 安全区不许退回「百分比宽盒子 + 交叉轴居中」：真机上会左锚定（见 device.js）。
  // .safe 必须是全宽容器，形状 class 不得再携带 width。
  const safeBlock = /\.safe\s*\{[^}]*\}/.exec(src)
  ok(`${page}.ux .safe 是全宽容器`, !!safeBlock && /width:\s*100%/.test(safeBlock[0]))
  ok(
    `${page}.ux 形状 class 不再携带宽度`,
    !/\.shape-(circle|rect|pill)\s*\{[^}]*width/.test(src)
  )
  ok(
    `${page}.ux 不再用 @media 判圆屏（媒体查询对 S1 Pro / Redmi Watch 4 不支持）`,
    !/shape:\s*circle/.test(src),
    '出现了 @media (shape: circle)'
  )
})

const playerUxSource = readFileSync(new URL('../src/pages/player/player.ux', import.meta.url), 'utf8')
ok(
  'player.ux 背景层按白名单门控（showCoverBg）',
  playerUxSource.indexOf('if="{{ showCoverBg }}"') >= 0
)
ok(
  'player.ux 背景层走 <image> 组件而不是 CSS background-image',
  playerUxSource.indexOf('class="cover-bg"') >= 0 &&
    !/(^|[\s;{])background-image\s*:/.test(playerUxSource),
  '出现了 background-image 声明（说明又改回靠 CSS 背景图，机型覆盖面更差）'
)
ok(
  'player.ux 有压暗层（Vela 没有 filter: blur，只能靠半透明压暗）',
  playerUxSource.indexOf('class="cover-mask"') >= 0
)
ok(
  'player.ux 背景层显式 object-fit: cover（不赌组件默认值，方形封面铺非方形屏不留边）',
  /object-fit:\s*cover/.test(playerUxSource)
)

/* --------- 12g. 表冠旋转焦点管理（表冠只作用于获焦组件，见 watchdoc《表冠旋转》） --------- */

// 主页整页表冠失灵的根因：本页有多个「可响应表冠」组件（封面 <image>、外层
// 滚动容器、第 2 屏 list）且异步挂载，默认焦点落点不可预测。约定：落定在哪屏
// 就把焦点显式交给谁（onReady/onShow/settlePagerPage/syncCoverBg/syncQueue/
// collapseQueue 落位）。
ok(
  'player.ux 翻页容器用 scroll 而不是 swiper，且为横向翻页（scroll-x；横向是故意的 feature，见 player.ux 顶部注释）',
  playerUxSource.indexOf('<scroll') >= 0 &&
    playerUxSource.indexOf('id="pager"') >= 0 &&
    playerUxSource.indexOf('scroll-x="{{ true }}"') >= 0 &&
    playerUxSource.indexOf('scroll-y="{{ true }}"') < 0 &&
    playerUxSource.indexOf('<swiper') < 0
)
ok(
  'player.ux 表冠焦点显式管理：落定信号汇入 settlePagerPage、队列 list 挂 id 供抢焦点',
  playerUxSource.indexOf('settlePagerPage') >= 0 &&
    playerUxSource.indexOf('id="qList"') >= 0 &&
    playerUxSource.indexOf('focusCrownTarget') >= 0
)
// 抢焦点先走 Vela《通用方法》的 focus({focus:true})（iot.mi.com），
// requestFocus 是手表联盟《表冠旋转》文档的 API，只做老 runtime 兜底。
ok(
  'player.ux 抢焦点先走 Vela 通用方法 focus({focus:true})，requestFocus 只做兜底',
  /el\.focus\(\{\s*focus:\s*true\s*\}\)/.test(playerUxSource) &&
    playerUxSource.indexOf('requestFocus') >= 0
)

// 真机复测结论：本机 runtime 连 list 都不派发 crownrotationchanged，swiper 更是
// 无表冠、无翻页手势 —— 翻页不依赖任何回调事件，靠「scroll 原生滚动 + 落定
// 信号」。横向翻页后官方 scroll 只收录 scrolltop / scrollbottom（纵向边界），
// 没有 scrollleft / scrollright，落定只剩 onscroll 一路：scrollX 贴边带
// （≤8px / ≥pageW-8px）汇入 settlePagerPage，变屏时把表冠焦点挪到新屏的滚动
// 容器上。scrolltop / scrollbottom 绑定属纵向时代遗留，出现即说明方向被改回去了。
ok(
  'player.ux 落定信号汇入 settlePagerPage（scrollX 贴边带；无 scrollleft/scrollright 事件可用）',
  playerUxSource.indexOf('onscroll="onPagerScroll"') >= 0 &&
    playerUxSource.indexOf('ev.scrollX') >= 0 &&
    playerUxSource.indexOf('settlePagerPage(0)') >= 0 &&
    playerUxSource.indexOf('settlePagerPage(1)') >= 0 &&
    playerUxSource.indexOf('onscrolltop') < 0 &&
    playerUxSource.indexOf('onscrollbottom') < 0
)
// scroll 的子项必须有确定尺寸才能成页（官方：竖向定高、水平定宽）：两屏宽高
// 内联绑定 pageW / pageH，数值来自 deviceService 按 getInfo 的 screenWidth /
// screenHeight 算出的 pageWidthPx / pageHeightPx。
ok(
  'player.ux 两屏宽高内联绑定 pageW/pageH，来自 deviceService 的 pageWidthPx/pageHeightPx',
  playerUxSource.indexOf('style="width: {{ pageW }}px; height: {{ pageH }}px"') >= 0 &&
    playerUxSource.indexOf('pageWidthPx') >= 0 &&
    playerUxSource.indexOf('pageHeightPx') >= 0
)
// scroll-snap 吸附是 APILevel 3+ / toolkit 1.1.4+ 的增强：支持就整页吸附，
// 不支持的机型忽略样式自由滚动，JS 侧落定逻辑不依赖吸附。
ok(
  'player.ux scroll-snap 吸附样式在位（APILevel 3+ 增强，不支持则自由滚动）',
  playerUxSource.indexOf('scroll-snap-type') >= 0 &&
    playerUxSource.indexOf('scroll-snap-align') >= 0
)
// 旧的表冠事件接线整体移除：oncrownrotationchanged 在本机不派发，绑着只会
// 触发 aiot build 的 unsupport event 告警。
ok(
  'player.ux 不再绑定 crownrotationchanged（本机不派发，纯编译告警噪音）',
  playerUxSource.indexOf('oncrownrotationchanged') < 0
)

/* --------- 12h. 头部统一样式（官方手表小程序：贴顶居中「‹ 标题」红色返回） --------- */

// 官方小程序不做上下安全区（会进一步压缩可用空间），头部一律贴顶居中标题；
// 带返回的页面整块「‹ 标题」标红、点击返回。各机型上都能完整显示。
// 音量页是唯一例外：官方音量示例没有头部，返回走贴底圆形关闭钮（第 11d 节）。
const HEADER_BACK_PAGES = [
  'more/more',
  'recommend/recommend',
  'fav/fav',
  'favDetail/favDetail',
  'login/login',
  'about/about',
]
HEADER_BACK_PAGES.forEach((page) => {
  const src = readFileSync(new URL(`../src/pages/${page}.ux`, import.meta.url), 'utf8')
  ok(
    `${page}.ux 头部走官方样式：贴顶居中「‹ 标题」红色返回`,
    src.indexOf('header-back') >= 0 && src.indexOf('‹') >= 0
  )
})
ok(
  'player.ux 队列屏头部同款（‹ 播放队列，翻回第 1 屏）且不再留顶部空隙',
  playerUxSource.indexOf('q-back') >= 0 &&
    playerUxSource.indexOf('‹ 播放队列') >= 0 &&
    playerUxSource.indexOf('margin-top: 20px') < 0
)
ok(
  'player.ux 头部「‹ 播放队列」走 scrollTo({left:0}) 横向兜底返回（不依赖手势）',
  playerUxSource.indexOf('scrollTo({ left: 0') >= 0
)

/* --------- 12i. 主页小字时间（标题上方的排版行） --------- */

// 标题之上本来是整块空白死区，加一行「HH:MM」的小字把视觉重心提上去。
// 时间本身零原生依赖（Vela 没有时间接口，就是 JS 的 Date），拼串逻辑落在
// common/clock.js 的纯函数里，页面只负责定时对账与绑定。
console.log('\n[12i] 主页小字时间')

// 纯函数：合法时刻 → 补零的时间串 + 年月日星期（月份不补零：`9月5日` 比 `09月05日` 好读；
// 星期用中文，0=周日与 Date#getDay() 对齐）
const clockSample = new Date(2026, 0, 5, 9, 7, 3)
eq(
  'formatClockParts 补零到 HH:MM 并拼出日期星期',
  formatClockParts(clockSample),
  {
    valid: true,
    time: '09:07',
    date: '2026年1月5日 周一',
    weekday: '周一',
    text: '09:07 2026年1月5日 周一',
  }
)
eq('formatClock 给页面用的一行展示串', formatClock(clockSample), '09:07 2026年1月5日 周一')
eq('formatClock 与 formatClockParts().text 同源', formatClock(clockSample), formatClockParts(clockSample).text)
eq('零点整不塌成 0:0', formatClockParts(new Date(2026, 0, 5, 0, 0, 0)).time, '00:00')
eq('23:59 不回绕', formatClockParts(new Date(2026, 0, 5, 23, 59, 59)).time, '23:59')
// 星期是本地时区无关的（Date#getDay()），固定日期断言最稳：2026-01-04 是周日
eq('周日 = 周日（下标 0 不对齐周一）', formatClockParts(new Date(2026, 0, 4, 12, 0, 0)).weekday, '周日')
eq('星期表 7 项且首项是周日', WEEKDAY_LABELS.length === 7 && WEEKDAY_LABELS[0], '周日')
// 拿不到合法时刻 → 全空串，页面据此整行不渲染（不显示 NaN:NaN，也不留空行）
const CLOCK_INVALID = [undefined, null, 0, '2026-01-05', {}, new Date('x')]
eq(
  '非法时刻一律退化成空串（不显示 NaN:NaN）',
  CLOCK_INVALID.map((bad) => formatClockParts(bad).text),
  ['', '', '', '', '', '']
)
eq('非法时刻 valid=false', CLOCK_INVALID.map((bad) => formatClockParts(bad).valid), [
  false,
  false,
  false,
  false,
  false,
  false,
])
eq('formatClock(null) 返回空串', formatClock(null), '')

// 页面接线：小字行必须在歌曲信息**上方**（模板里的先后顺序 = flex 排版顺序），
// 且要有一行等高样式（高度写死，定时器只改文字不改排版）。
ok(
  'player.ux 时间行在歌曲信息上方（模板顺序）',
  playerUxSource.indexOf('class="clock-row"') >= 0 &&
    playerUxSource.indexOf('class="clock-row"') < playerUxSource.indexOf('class="song"'),
  '时间行不在 .song 之前'
)
const clockRowBlock = /\.clock-row\s*\{[^}]*\}/.exec(playerUxSource)
const clockTextBlock = /\.clock-text\s*\{[^}]*\}/.exec(playerUxSource)
ok(
  'player.ux 时间行是全宽居中、高度写死一行',
  !!clockRowBlock &&
    /width:\s*100%/.test(clockRowBlock[0]) &&
    /height:\s*\d+px/.test(clockRowBlock[0]),
  'clock-row 样式缺失或没写死高度'
)
const clockAlphaMatch = clockTextBlock
  ? /rgba\(255,\s*255,\s*255,\s*([0-9.]+)\)/.exec(clockTextBlock[0])
  : null
const clockAlpha = clockAlphaMatch ? Number(clockAlphaMatch[1]) : NaN
ok(
  'player.ux 时间小字不抢戏（字号小于歌名 42px，透明度低于歌手行 0.8）',
  !!clockTextBlock &&
    Number(/font-size:\s*(\d+)px/.exec(clockTextBlock[0])[1]) < 42 &&
    clockAlpha < 0.8,
  `clock-text 字号/透明度越界：alpha=${clockAlpha}`
)
ok(
  'player.ux 用小字时间走 common/clock 的纯函数（不自己拼时间串）',
  playerUxSource.indexOf('common/clock') >= 0 &&
    playerUxSource.indexOf('formatClockParts') >= 0
)
// 定时器卫生：起表前先停旧表（onInit / onShow 都会起，重复起不能累积定时器），
// 且 onHide / onDestroy 都要停表 —— 看不见的页面不必每秒醒，销毁后更不能留着跑。
ok(
  'player.ux 起表幂等（先 stopClock 再 setInterval，不累积定时器）',
  /startClock\(\)\s*\{[^}]*stopClock\(\)[\s\S]*?setInterval/.test(playerUxSource),
  'startClock 没有先停旧表'
)
ok(
  'player.ux onInit / onShow 起表（onShow 补一次跨页对账）',
  /onInit\(\)\s*\{[\s\S]*?startClock\(\)/.test(playerUxSource) &&
    /onShow\(\)\s*\{[\s\S]*?startClock\(\)/.test(playerUxSource)
)
ok(
  'player.ux onHide / onDestroy 停表（定时器不留常驻开销）',
  /onHide\(\)\s*\{[\s\S]*?stopClock\(\)/.test(playerUxSource) &&
    /onDestroy\(\)\s*\{[\s\S]*?stopClock\(\)/.test(playerUxSource),
  'onHide 或 onDestroy 没停表'
)
ok(
  'player.ux 时间行拿不到合法时刻时整行不渲染',
  playerUxSource.indexOf('if="{{ clockText }}"') >= 0
)

// 报错行：真机上被截断过。屏幕只有 4xx px 宽，而诊断类报错有 60-120 字
// （`直链与落盘均失败：CDN 拒绝（HTTP 403，节点 upos，Referer 已带，直链余 118 分钟）`），
// `text` 的 lines:2 + ellipsis 正好把「为什么失败」那半句切掉 —— 而那半句才是排查要看的。
// 所以长提示必须走 marquee（官方组件，歌名行一直在用），短提示保持居中静态。
ok(
  'player.ux 长报错走 <marquee>（避免 60+ 字诊断信息被 lines:2 截断）',
  /<marquee[\s\S]{0,240}?\{\{ notice \}\}<\/marquee>/.test(playerUxSource),
  'notice 没接跑马灯'
)
ok(
  'player.ux 短提示仍旧是 <text>（不无谓滚动）',
  /<text class="notice" else>\{\{ notice \}\}<\/text>/.test(playerUxSource),
  '缺少静态分支'
)
ok(
  'player.ux 跑马灯按长度切换（setNotice 判定 18 字）',
  /noticeScroll:\s*false/.test(playerUxSource) &&
    /setNotice\(text\)\s*\{[\s\S]*?noticeScroll[\s\S]*?length > 18/.test(playerUxSource),
  'setNotice 的长度判定缺失'
)
ok(
  'player.ux notice 只经 setNotice 写入（两处分支不会只改一半）',
  (playerUxSource.match(/setField\("notice"/g) || []).length === 1,
  '除 setNotice 外还有直接写 notice 的地方'
)

/* --------- 13. 更多页数据链路：推荐流/热门解析 + 曲目匹配（点播解耦的底座） --------- */

// 官方推荐页与收藏夹页共用两条纯函数链路：
//   1. parseRecommendItem / parsePopularItem —— 把 B 站推荐流/热门条目归一成播放曲目，
//      广告、直播、番剧（PGC）等播不了的条目在这一层就地丢弃；
//   2. trackKey / sameTrack / findTrackIndex —— 「怎么算同一首歌」。
// 队列与来源解耦后，列表页的高亮和 playTrackNow 的去重都靠它。

console.log('\n[13] 推荐流解析与曲目匹配')

// 13a. 推荐流条目（rcmd：goto !== 'av' 的一律丢弃）
const rcmdAv = {
  id: 117284383229787,
  bvid: 'BV1UWeM6tEoK',
  cid: 41962899058,
  goto: 'av',
  pic: 'http://i2.hdslb.com/bfs/archive/a.jpg',
  title: '推荐曲目',
  duration: 485,
  owner: { mid: 2233213, name: 'UP 主' },
}
eq(
  'rcmd av 条目 → 曲目',
  parseRecommendItem(rcmdAv),
  {
    id: 117284383229787,
    bvid: 'BV1UWeM6tEoK',
    cid: 41962899058,
    title: '推荐曲目',
    artist: 'UP 主',
    cover: 'http://i2.hdslb.com/bfs/archive/a.jpg',
    duration: 485,
  }
)
eq('rcmd 广告条目丢弃', parseRecommendItem({ ...rcmdAv, goto: 'ad' }), null)
eq('rcmd 缺 bvid 丢弃', parseRecommendItem({ ...rcmdAv, bvid: '' }), null)
eq('rcmd 非对象输入', parseRecommendItem(null), null)
eq(
  'rcmd cid 缺失时归零（取流时再解析）',
  parseRecommendItem({ ...rcmdAv, cid: undefined }).cid,
  0
)

// 13b. 热门条目（popular：带 redirect_url 的 PGC 播不了，丢弃）
const popArc = {
  aid: 117280105045764,
  bvid: 'BV1cSec6tEux',
  cid: 41969257534,
  pic: 'http://i1.hdslb.com/bfs/archive/b.jpg',
  title: '热门曲目',
  duration: 1632,
  owner: { mid: 946974, name: '影视飓风' },
}
eq('popular 普通条目 → 曲目', parsePopularItem(popArc).bvid, 'BV1cSec6tEux')
eq('popular artist 取 owner.name', parsePopularItem(popArc).artist, '影视飓风')
eq(
  'popular 番剧（redirect_url）丢弃',
  parsePopularItem({ ...popArc, redirect_url: 'https://www.bilibili.com/bangumi/play/ep1' }),
  null
)
eq('popular 缺 bvid 丢弃', parsePopularItem({ ...popArc, bvid: null }), null)

// 13c. 曲目匹配：bvid 优先、avid 兜底（点播去重与列表高亮的判据）
eq('trackKey：bvid 优先', trackKey({ bvid: 'BV1', id: 9 }), 'bv:BV1')
eq('trackKey：无 bvid 退化到 avid', trackKey({ id: 9 }), 'av:9')
eq('trackKey：aid 兜底', trackKey({ aid: 9 }), 'av:9')
eq('trackKey：什么都没有', trackKey({}), '')
eq('trackKey：非对象', trackKey(null), '')
ok('sameTrack：同 bvid 视为同一首', sameTrack({ bvid: 'BV1', id: 1 }, { bvid: 'BV1' }))
ok('sameTrack：都无 bvid 时按 avid 匹配', sameTrack({ id: 9 }, { aid: 9 }))
ok(
  'sameTrack：一方带 bvid 一方没有 → 不算同一首（宁可重复入队也不错判）',
  !sameTrack({ bvid: 'BV1', id: 9 }, { id: 9 })
)
ok('sameTrack：空对象不算同一首', !sameTrack({}, {}))
const matchList = [{ bvid: 'BVA' }, { bvid: 'BVB', cid: 2 }, { id: 33 }]
eq('findTrackIndex：命中', findTrackIndex(matchList, { bvid: 'BVB' }), 1)
eq('findTrackIndex：avid 兜底命中', findTrackIndex(matchList, { aid: 33 }), 2)
eq('findTrackIndex：未命中', findTrackIndex(matchList, { bvid: 'BVX' }), -1)
eq('findTrackIndex：空列表', findTrackIndex([], { bvid: 'BVA' }), -1)
eq('findTrackIndex：目标取不到键', findTrackIndex(matchList, {}), -1)

/* --------- 14. 关于页：@system.app 应用信息（值全部来自原生，不硬编码） --------- */

// 更多页的「关于」入口落到 pages/about，该页显示的应用信息全部来自
// `@system.app` 的 getInfo()：
//   { packageName, icon, name, versionName, versionCode, logLevel,
//     source: { packageName, type } }
// 文档：https://iot.mi.com/vela/quickapp/zh/features/basic/app.html
//   官方写「接口声明：无需声明」（运行时确实不声明也能调），但 **aiot build 会拦**：
//   源码里 import 了 @system.app 而 manifest.features 里没有它，构建直接报
//   `missing feature: [{"name":"system.app"}]`（本轮实测）。所以 manifest 里
//   声明了 system.app —— 声明是给构建看的，不是给运行时看的，删了就没法打包。
//
// 这一节钉两件事：
//   1) 归一化层要兜住字段缺失 / 类型不对 / 整个接口不可用（老 runtime），
//      拿不到信息时 available=false，页面走「读取失败」分支；
//   2) 关于页里**不许出现包名、版本号、图标路径的字面量** —— 改了 manifest 的
//      versionName / versionCode，页面显示的必须跟着变（防「抄一份然后忘了改」）。

console.log('\n[14] 关于页（@system.app 应用信息）')

// 14a. 归一化与展示值（纯函数，见 common/appinfo.js）
eq(
  'getInfo 返回值归一化',
  normalizeAppInfo({
    packageName: 'github.naivg.bilimusic',
    name: 'bilimusic',
    versionName: '1.0.0',
    versionCode: 1,
    icon: '/common/logo.png',
    logLevel: 'log',
    source: { packageName: '', type: 'ShortCut' },
  }),
  {
    available: true,
    packageName: 'github.naivg.bilimusic',
    name: 'bilimusic',
    versionName: '1.0.0',
    versionCode: 1,
    icon: '/common/logo.png',
    logLevel: 'log',
    sourcePackage: '',
    sourceType: 'shortcut',
  }
)
eq('字段缺失 / 类型不对也容忍', normalizeAppInfo({ name: 42, versionCode: '7', source: null }), {
  available: true,
  packageName: '',
  name: '42',
  versionName: '',
  versionCode: 7,
  icon: '',
  logLevel: '',
  sourcePackage: '',
  sourceType: '',
})
eq('getInfo 整个失败（传 null）-> available=false', normalizeAppInfo(null).available, false)
eq('非对象输入（传字符串）-> available=false', normalizeAppInfo('bilimusic').available, false)
eq('空对象 -> available=false（没有可显示的值，不渲染一屏空白）', normalizeAppInfo({}).available, false)
eq(
  '只要有一个可显示字段就算读到（老 runtime 只给 icon）',
  [normalizeAppInfo({ icon: '/common/logo.png' }).available, normalizeAppInfo({ name: 'x' }).available],
  [true, true]
)
eq('versionCode 非法 -> 0（不显示成 NaN）', normalizeAppInfo({ versionCode: 'x' }).versionCode, 0)
eq(
  'source 缺失时二级字段为空串',
  [normalizeAppInfo({}).sourcePackage, normalizeAppInfo({}).sourceType],
  ['', '']
)

// 版本展示串：两个字段都在才带括号，缺一个就只说有的那个
eq('版本串：名称 + 构建号', formatAppVersion({ versionName: '1.0.0', versionCode: 1 }), '1.0.0 (1)')
eq('版本串：只有名称', formatAppVersion({ versionName: '1.0.0' }), '1.0.0')
eq('版本串：只有构建号', formatAppVersion({ versionCode: 7 }), '7')
eq('版本串：都没有 -> 空串（页面不渲染这一行）', formatAppVersion({}), '')
eq(
  '版本串：versionCode 0 视为没给（不显示成 1.0.0 (0)）',
  formatAppVersion({ versionName: '1.0.0', versionCode: 0 }),
  '1.0.0'
)
eq('版本串：非对象输入', formatAppVersion(null), '')

// 启动来源：官方枚举全覆盖 + 未知取值原样透传
eq(
  '启动来源枚举全覆盖',
  ['shortcut', 'push', 'url', 'barcode', 'nfc', 'bluetooth', 'other'].map(describeAppSource),
  ['桌面快捷方式', '推送唤起', '链接唤起', '扫码唤起', 'NFC 唤起', '蓝牙唤起', '其它入口']
)
eq('启动来源大小写不敏感', describeAppSource('PUSH'), '推送唤起')
eq('启动来源未知取值原样透传（不吞信息）', describeAppSource('beacon'), 'beacon')
eq('启动来源为空 -> 空串（页面不渲染这一行）', describeAppSource(''), '')
ok(
  '来源字典与官方枚举一一对应',
  Object.keys(APP_SOURCE_LABELS).sort().join(',') === 'barcode,bluetooth,nfc,other,push,shortcut,url',
  Object.keys(APP_SOURCE_LABELS).sort().join(',')
)

// 14b. appService 端到端（走 @system.app 桩）
const appStub = await import('../scripts/stubs/system.app.mjs')
appStub.__reset()

const appService = await import('../src/services/appService.js?vm=about')

// 未读之前必须 fail-closed：不猜包名、不猜版本
eq('未读 -> available=false', appService.getCached().available, false)
eq('未读 -> 包名为空串', appService.getCached().packageName, '')

const appInfo = appService.info()
eq(
  '读到应用信息',
  [appInfo.available, appInfo.packageName, appInfo.name, appInfo.versionName, appInfo.versionCode],
  [true, 'github.naivg.bilimusic', 'bilimusic', '1.0.0', 1]
)
eq('图标路径原样透传（页面直接当 <image> 的 src）', appInfo.icon, '/common/logo.png')
eq('原生接口只问一次', appStub.__calls(), 1)
appService.info()
eq('info() 幂等（同一个 VM 内不重复打原生）', appStub.__calls(), 1)

// 换一份原生值：读到的必须跟着变 —— 这就是「不硬编码」的机器判据
appStub.__setInfo({ name: 'bilimusic-next', versionName: '9.9.9', versionCode: 42 })
appService.reset()
const changed = appService.info()
eq(
  '换了原生值，读到的就变（不是写死的常量）',
  [changed.name, formatAppVersion(changed), appStub.__calls()],
  ['bilimusic-next', '9.9.9 (42)', 2]
)

// 老 runtime：字段全缺 / 直接抛错，都不能把关于页拖挂
appStub.__setMode('empty')
appService.reset()
eq('getInfo 返回空对象 -> available=false', appService.info().available, false)

appStub.__setMode('throw')
appService.reset()
const thrown = appService.info()
eq(
  'getInfo 同步抛错 -> 兜住，退化成读取失败',
  [thrown.available, formatAppVersion(thrown)],
  [false, '']
)
appStub.__reset()

// 14c. 页面接线：关于页只消费服务，且不写死任何值
const aboutUxSource = readFileSync(new URL('../src/pages/about/about.ux', import.meta.url), 'utf8')
const moreUxSource = readFileSync(new URL('../src/pages/more/more.ux', import.meta.url), 'utf8')

// manifest 必须声明 system.app：官方写「无需声明」，但 aiot build 会因为
// `import app from '@system.app'` 没有对应声明直接 fail（missing feature）。
ok(
  'manifest 声明了 system.app（官方说无需声明，但 aiot build 认它，少了打不出包）',
  topFeatures.indexOf('system.app') >= 0,
  `实际：${JSON.stringify(topFeatures)}`
)
ok(
  'system.app 不写进后台运行凭据（后台只认 audio/request/geolocation）',
  backgroundFeatures.indexOf('system.app') < 0,
  `实际：${JSON.stringify(backgroundFeatures)}`
)

ok(
  'about.ux 走 appService 读应用信息，不直接 import @system.app（页面里只留 router）',
  aboutUxSource.indexOf('services/appService') >= 0 &&
    !/from\s+['"]@system\.app['"]/.test(aboutUxSource),
  '页面里出现了 @system.app 的 import，或没走 appService'
)
ok(
  'about.ux 不碰音频接口、不 init 播放服务（临时页面不绑音频事件）',
  aboutUxSource.indexOf('@system.audio') < 0 && aboutUxSource.indexOf('playerService.init') < 0
)
ok(
  'about.ux 用 common/appinfo 的纯函数拼展示值（版本串 / 来源说明）',
  aboutUxSource.indexOf('common/appinfo') >= 0 &&
    aboutUxSource.indexOf('formatAppVersion') >= 0 &&
    aboutUxSource.indexOf('describeAppSource') >= 0
)
// 「不硬编码」的源码判据：页面里不许出现版本号 / 包名 / 应用名 / 图标路径
const HARDCODED_IN_ABOUT = [
  ['版本号字面量', /\d+\.\d+\.\d+/],
  ['manifest 里的包名', /github\.naivg/],
  ['manifest 里的应用名', /['"]bilimusic['"]/],
  ['图标路径字面量', /\/common\/logo\.png/],
].filter(([, re]) => re.test(aboutUxSource))
ok(
  'about.ux 不硬编码包名 / 版本 / 图标路径（全部来自 getInfo）',
  HARDCODED_IN_ABOUT.length === 0,
  HARDCODED_IN_ABOUT.map(([name]) => name).join('、')
)
ok(
  'about.ux 每一项都绑在 data 上（模板里是 {{ }} 而不是字面量）',
  [
    '{{ appName }}',
    '{{ versionText }}',
    '{{ packageName }}',
    '{{ versionCodeText }}',
    '{{ logLevel }}',
    '{{ sourceText }}',
  ].every((token) => aboutUxSource.indexOf(token) >= 0)
)
ok(
  'about.ux 取不到的字段整行不渲染（老 runtime 不留空行）',
  aboutUxSource.indexOf('if="{{ packageName }}"') >= 0 &&
    aboutUxSource.indexOf('if="{{ logLevel }}"') >= 0 &&
    aboutUxSource.indexOf('if="{{ sourceText }}"') >= 0
)
ok(
  'about.ux 图标走 <image>，取不到路径时退化成文字块',
  aboutUxSource.indexOf('if="{{ icon }}"') >= 0 &&
    aboutUxSource.indexOf('app-icon-fallback') >= 0
)
ok(
  '更多页有「关于」入口并指向 pages/about',
  moreUxSource.indexOf('goAbout') >= 0 && moreUxSource.indexOf('uri: "/pages/about"') >= 0
)

// 14d. 更多页条目密度：与播放队列同尺度（偏紧凑，但条目之间留空余）
//
// 队列条目（player.ux 的 .q-item）是 84px + 14px —— 这是「紧凑但不挤」的基准线。
// 更多页条目从 104px 收到同一尺度，别让谁又调回宽松版。
const menuItemBlock = /\.menu-item\s*\{[^}]*\}/.exec(moreUxSource)
const queueItemBlock = /\.q-item\s*\{[^}]*\}/.exec(playerUxSource)
const menuItemHeight = menuItemBlock ? Number(/height:\s*(\d+)px/.exec(menuItemBlock[0])[1]) : 0
const queueItemHeight = queueItemBlock ? Number(/height:\s*(\d+)px/.exec(queueItemBlock[0])[1]) : 0
const menuItemGap = menuItemBlock ? Number(/margin-bottom:\s*(\d+)px/.exec(menuItemBlock[0])[1]) : 0
ok(
  '更多页条目高度与播放队列同尺度（差值 ≤ 8px）',
  menuItemHeight > 0 && queueItemHeight > 0 && Math.abs(menuItemHeight - queueItemHeight) <= 8,
  `menu-item=${menuItemHeight}px, q-item=${queueItemHeight}px`
)
ok(
  '更多页条目之间仍留空余（≥12px，不挤成一片）',
  menuItemGap >= 12,
  `menu-item margin-bottom=${menuItemGap}px`
)

/* --------- 15. 网桥：本机没有 @system.fetch 时的联网通道（interconnect → FetchBridge） --------- */

console.log('\n[15] 网桥（interconnect → 手机端 FetchBridge）')

// 背景：Redmi Watch 4 / Xiaomi Watch H1 E 有扬声器，但**官方支持明细里就没有 @system.fetch**；
// 手环那档更彻底（一体机身没扬声器）直接不适配。这些机型的联网由手机/PC 端的 AstroBox
// 「网桥 FetchBridge」插件代发 HTTP，协议见
// AstroBox-NG-Plugin-MiWear-InterconnectFetch/PROTOCOL.md（v4 插件，向下兼容 v1-v3）。
//
// 本节用 scripts/stubs/system.interconnect.mjs 同时扮演"原生接口"和"那个插件"，
// 跑的是**真实协议往返**（握手协商 → 单消息/分片 → 累计 ACK），不是对着假数据断言：
// 客户端不回 ACK，桩就会像真插件一样把窗口停住，用例会直接失败。

const b64 = (s) => Buffer.from(s, 'utf8').toString('base64')
const tick = () => new Promise((r) => setTimeout(r, 0))
const throwsCode = (fn, code) => {
  try {
    fn()
  } catch (e) {
    return !!e && e.code === code
  }
  return false
}

// 15a. 解码（Vela 的 JS VM 不保证有 atob/TextDecoder，全部自实现）
eq('base64 解码（ASCII）', base64Decode('aGVsbG8='), 'hello')
eq('base64 解码（无填充）', base64Decode('aGVsbG8'), 'hello')
eq('base64 → UTF-8（中文）', utf8Decode(base64Decode(b64('中文测试'))), '中文测试')
ok('base64 遇到非法字符明确报错（不静默解出乱码）', throwsCode(() => base64Decode('!!!!'), BRIDGE_ERRORS.PROTOCOL))
eq('hex → UTF-8（中文）', utf8Decode(hexDecode('e4b8ade69687')), '中文')
eq('UTF-8 四字节（emoji / 代理对）', utf8Decode(hexDecode('f09f9880')), '😀')
ok('hex 长度为奇数时明确报错', throwsCode(() => hexDecode('abc'), BRIDGE_ERRORS.PROTOCOL))
ok(
  '对端擅自压缩时明确报错（绝不当没压缩接着解）',
  throwsCode(
    () => decodeSingleBody({ ok: true, status: 200, body: 'x', raw: false, compression: 'deflate' }),
    BRIDGE_ERRORS.PROTOCOL
  )
)

// 15b. caps 协商（PROTOCOL.md §3.4 逐条对照）
const localCaps = buildLocalCaps(CONFIG.BRIDGE)
const negCaps = negotiateCaps(
  {
    version: 4,
    chunk: true,
    maxChunkSize: 8192,
    encodings: ['base64', 'hex', 'text'],
    compressions: ['none', 'deflate'],
    ack: true,
    ackWindow: 8,
  },
  localCaps
)
eq('版本取 min（本端已升到 v4，插件也是 v4）', negCaps.version, 4)
ok('对端没声明 stream ⇒ 不开流（stream 是 caps 里的独立开关）', negCaps.stream === false)
eq('分片大小取对端声明值', negCaps.chunkSize, 8192)
eq('ACK 窗口取对端声明值', negCaps.ackWindow, 8)
eq('encodings 交集保留对端顺序', negCaps.encodings.join(','), 'base64,text')
eq('compressions 交集只剩 none（省掉 JS 侧解压依赖）', negCaps.compressions.join(','), 'none')

const legacyCaps = negotiateCaps(null, localCaps)
ok(
  '对端没声明 caps ⇒ 整会话退回 v1（单消息 / 不分片 / 不 ACK）',
  legacyCaps.version === 1 &&
    legacyCaps.chunked === false &&
    legacyCaps.ackWindow === 0 &&
    legacyCaps.legacy === true
)
const v2Caps = negotiateCaps({ version: 2, chunk: true, maxChunkSize: 4096 }, localCaps)
ok('v2 对端能分片但不启用 ACK 窗口（退回 v2 无流控路径）', v2Caps.chunked === true && v2Caps.ackWindow === 0)
const clampedCaps = negotiateCaps(
  { version: 4, chunk: true, maxChunkSize: 1, ack: true, ackWindow: 999 },
  localCaps
)
ok(
  'maxChunkSize / ackWindow 越界时夹到协议范围',
  clampedCaps.chunkSize === 256 && clampedCaps.ackWindow === 64,
  `chunkSize=${clampedCaps.chunkSize} ackWindow=${clampedCaps.ackWindow}`
)

// v4 流的硬门控（PROTOCOL.md §6.5）：version>=4 + 双端 stream + 分片 + ACK 全齐才开流
const v4Peer = {
  version: 4,
  chunk: true,
  maxChunkSize: 4096,
  encodings: ['base64', 'hex', 'text'],
  compressions: ['none', 'deflate', 'lz4'],
  ack: true,
  ackWindow: 4,
  stream: true,
}
ok('★ 双端 v4 + stream + 分片 + ACK 全齐 ⇒ 协商出流', negotiateCaps(v4Peer, localCaps).stream === true)
ok('对端退到 v3 ⇒ 不开流（版本被压到 3）', negotiateCaps({ ...v4Peer, version: 3 }, localCaps).stream === false)
ok(
  '对端没开 ACK 窗口 ⇒ 不开流（v4 不允许无 ACK 流式发送）',
  negotiateCaps({ ...v4Peer, ack: false }, localCaps).stream === false
)
ok(
  '本端关掉 STREAM ⇒ 不开流（CONFIG.BRIDGE.STREAM=false 时整端回 v3 行为）',
  negotiateCaps(v4Peer, buildLocalCaps({ ...CONFIG.BRIDGE, STREAM: false })).stream === false
)
ok('legacy 会话（对端无 caps）也不含流', negotiateCaps(null, localCaps).stream === false)

// 15c. 分片重组 + 累计 ACK（PROTOCOL.md §5.2.1）
const asm = new ChunkAssembler({ id: 'x', chunkCount: 5, totalBytes: 5, bodyEncoding: 'base64', ack: true })
ok('未收齐时不算完成', asm.isComplete === false)
;[0, 1, 3, 4].forEach((seq) => asm.push(seq, b64('abcde'.charAt(seq))))
eq('乱序到达：累计 ACK 停在缺口处', asm.ackValue, 2)
ok('重复分片被忽略、也不重复计 ACK', asm.push(0, b64('a')).accepted === false && asm.ackValue === 2)
asm.push(2, b64('c'))
eq('缺口补齐后 ACK 一次跳到片数', asm.ackValue, 5)
eq('正文按 seq 排序拼装（不是到达顺序）', asm.assemble(), 'abcde')

// ★ 关键回归：一个中文字符被切在两个分片里。每片只能解到字节，
// 必须整段拼完再 UTF-8 解码 —— 逐片解码会把中文切成两半（真机上表现为乱码 JSON）
const cnBytes = Buffer.from('中文测试', 'utf8')
const splitAsm = new ChunkAssembler({
  id: 'y',
  chunkCount: 2,
  totalBytes: cnBytes.length,
  bodyEncoding: 'base64',
})
splitAsm.push(0, cnBytes.slice(0, 4).toString('base64'))
ok('分片没到齐时不解码（半个字符不落地）', splitAsm.isComplete === false)
splitAsm.push(1, cnBytes.slice(4).toString('base64'))
eq('★ 跨分片的多字节字符整段解码不坏', splitAsm.assemble(), '中文测试')

const badAsm = new ChunkAssembler({ id: 'z', chunkCount: 2, totalBytes: 999, bodyEncoding: 'base64' })
badAsm.push(0, b64('a'))
badAsm.push(1, b64('b'))
ok(
  '分片总长与 totalBytes 不符时明确报错（不把半截 JSON 交出去）',
  throwsCode(() => badAsm.assemble(), BRIDGE_ERRORS.PROTOCOL)
)

// 15d. 端到端：这台机型没有 @system.fetch ⇒ api.js 自动改走网桥
interconnectStub.__reset()
interconnectStub.__setRoute('https://api.bilibili.com/x/bridge/demo', {
  body: JSON.stringify({ code: 0, data: { hello: '网桥' } }),
})
fetchFeatureAvailable = false
const bridgeApiVm = await import('../src/services/api.js?vm=bridge-nofetch')
eq('★ 没有 @system.fetch 的机型自动选网桥（provider=bridge）', bridgeApiVm.resolveProvider(), 'bridge')
const bridgeRes = await bridgeApiVm.request({
  url: 'https://api.bilibili.com/x/bridge/demo',
  responseType: 'json',
})
eq('httpCode 来自响应 status', bridgeRes.httpCode, 200)
eq(
  '★ json 由请求层自己 parse（body 是对象，与原生路径形态完全一致）',
  bridgeRes.body && bridgeRes.body.data && bridgeRes.body.data.hello,
  '网桥'
)
ok(
  'describeNetwork() 能一眼看出当前通道（排查用）',
  bridgeApiVm.describeNetwork().provider === 'bridge' && bridgeApiVm.describeNetwork().mode === 'auto'
)

// 15e. 分片响应端到端：窗口小于片数也不能死锁（增量 ACK 的回归）
const bigBody = JSON.stringify({
  code: 0,
  data: { list: Array.from({ length: 60 }, (_, i) => 'item-' + i + '-' + 'x'.repeat(30)) },
})
const bridgeChunkSize = 200
CONFIG.BRIDGE.ACK_WINDOW = 2 // 故意把窗口调到远小于片数：攒着回 ACK 的实现会在这里死锁
interconnectStub.__reset()
interconnectStub.__setRoute('https://api.bilibili.com/x/bridge/big', {
  body: bigBody,
  chunked: true,
  chunkSize: bridgeChunkSize,
})
const chunkedVm = await import('../src/services/interconnBridge.js?vm=chunked')
const bigRes = await chunkedVm.request({ url: 'https://api.bilibili.com/x/bridge/big' })
eq('★ 分片响应重组后 JSON 完整', JSON.parse(bigRes.data).data.list.length, 60)
const expectedChunks = Math.ceil(Buffer.byteLength(bigBody, 'utf8') / bridgeChunkSize)
const ackSeq = interconnectStub.__acks(interconnectStub.__lastSent('fetch').id)
eq('★ 每片回一次增量 ACK（窗口 2 < 片数也不死锁）', ackSeq.length, expectedChunks)
ok(
  '累计 ACK 单调不减、收齐时等于片数',
  ackSeq[ackSeq.length - 1] === expectedChunks && ackSeq.every((v, i, a) => i === 0 || v >= a[i - 1]),
  JSON.stringify(ackSeq)
)
CONFIG.BRIDGE.ACK_WINDOW = 4

// 15f. 两个 page VM（同一条 app 单例连接）先后发请求：各自独立握手、都能完成
interconnectStub.__reset()
interconnectStub.__setRoute('https://api.bilibili.com/x/bridge/a', {
  body: JSON.stringify({ code: 0, data: { who: 'A' } }),
})
interconnectStub.__setRoute('https://api.bilibili.com/x/bridge/b', {
  body: JSON.stringify({ code: 0, data: { who: 'B' } }),
})
const pageBridgeA = await import('../src/services/interconnBridge.js?vm=pageA')
const pageBridgeB = await import('../src/services/interconnBridge.js?vm=pageB')
const bindsBefore = interconnectStub.__bindCount()
const resA = await pageBridgeA.request({ url: 'https://api.bilibili.com/x/bridge/a' })
const resB = await pageBridgeB.request({ url: 'https://api.bilibili.com/x/bridge/b' })
eq('VM A 拿到自己的响应', JSON.parse(resA.data).data.who, 'A')
eq('VM B 在同一条连接上也能完成（各自独立握手）', JSON.parse(resB.data).data.who, 'B')
ok('每次发送前重绑 onmessage（单例连接只有一个槽位）', interconnectStub.__bindCount() > bindsBefore)

// 15g. 不是本 VM 的 id / 还没处理的 tag：一律忽略（协议要求：不得报错断开会话）
const inflightBefore = pageBridgeA.describeState().inflight
interconnectStub.__emitRaw({ tag: 'fetch', id: 'someone-else-1', resp: { ok: true, status: 200, body: 'x', raw: false } })
interconnectStub.__emitRaw({ tag: 'fetch-chunk', id: 'someone-else-1', seq: 0, data: b64('x') })
interconnectStub.__emitRaw({ tag: 'fetch-stream', id: 'someone-else-1', seq: 0, data: b64('x') })
ok('别的 VM 的帧与未处理的 tag 被忽略，既不串台也不打断会话', pageBridgeA.describeState().inflight === inflightBefore)

// 15h. 手机端没在听（AstroBox 里没给本应用打开「监听」）：报错必须说人话
const savedHandshakeTimeout = CONFIG.BRIDGE.HANDSHAKE_TIMEOUT
CONFIG.BRIDGE.HANDSHAKE_TIMEOUT = 150
interconnectStub.__reset()
interconnectStub.__setHandshake(false)
const noHostVm = await import('../src/services/interconnBridge.js?vm=nohost')
let noHostErr = null
try {
  await noHostVm.request({ url: 'https://api.bilibili.com/x/bridge/whatever' })
} catch (e) {
  noHostErr = e
}
ok(
  '★ 握手无回音时报 E_BRIDGE_NO_HOST，并直接说清去 AstroBox 点什么',
  !!noHostErr && noHostErr.code === BRIDGE_ERRORS.NO_HOST && noHostErr.message.indexOf('监听') >= 0,
  noHostErr && noHostErr.message
)
interconnectStub.__setHandshake(true)
CONFIG.BRIDGE.HANDSHAKE_TIMEOUT = savedHandshakeTimeout

// 15i. 响应一直不来 → 超时；连接断开 → 在途请求立刻失败（都不能让页面干等）
const savedRequestTimeout = CONFIG.BRIDGE.REQUEST_TIMEOUT
CONFIG.BRIDGE.REQUEST_TIMEOUT = 150
interconnectStub.__reset()
interconnectStub.__setRoute('https://api.bilibili.com/x/bridge/silent', { silent: true })
const timeoutVm = await import('../src/services/interconnBridge.js?vm=timeout')
let timeoutErr = null
try {
  await timeoutVm.request({ url: 'https://api.bilibili.com/x/bridge/silent' })
} catch (e) {
  timeoutErr = e
}
ok(
  '响应一直不来时报 E_BRIDGE_TIMEOUT（不无限挂住页面）',
  !!timeoutErr && timeoutErr.code === BRIDGE_ERRORS.TIMEOUT,
  timeoutErr && timeoutErr.code
)
CONFIG.BRIDGE.REQUEST_TIMEOUT = savedRequestTimeout

interconnectStub.__reset()
interconnectStub.__setRoute('https://api.bilibili.com/x/bridge/silent2', { silent: true })
const closeVm = await import('../src/services/interconnBridge.js?vm=close')
const pendingClose = closeVm.request({ url: 'https://api.bilibili.com/x/bridge/silent2', timeout: 5000 })
for (let i = 0; i < 20 && closeVm.describeState().inflight === 0; i++) await tick()
eq('前置条件：请求已发出并在途', closeVm.describeState().inflight, 1)
interconnectStub.__emitClose(1006)
let closeErr = null
try {
  await pendingClose
} catch (e) {
  closeErr = e
}
ok(
  '连接断开时在途请求立刻失败（不让页面各自干等到超时）',
  !!closeErr && closeErr.code === BRIDGE_ERRORS.CLOSED,
  closeErr && closeErr.code
)

// 握手途中就断开：request() 是"先 await 握手、再建请求超时定时器"，
// 握手那个 Promise 若不失败，请求会永远不 settle（连超时都还没开始计）→ 页面卡死
interconnectStub.__reset()
interconnectStub.__setHandshake(false)
const handshakeVm = await import('../src/services/interconnBridge.js?vm=handshake-close')
const pendingHandshake = handshakeVm.request({ url: 'https://api.bilibili.com/x/bridge/x' })
await tick()
await tick()
interconnectStub.__emitClose(1006)
let handshakeErr = null
try {
  await pendingHandshake
} catch (e) {
  handshakeErr = e
}
ok(
  '握手途中断开也要立刻失败（否则这个 Promise 永远不 settle）',
  !!handshakeErr && handshakeErr.code === BRIDGE_ERRORS.CLOSED,
  handshakeErr && handshakeErr.code
)
interconnectStub.__setHandshake(true)

// 15j. 接线与声明（aiot build 缺声明会直接拦下来，见 README 第七节）
ok(
  'manifest 声明了 system.interconnect',
  manifest.features.some((f) => f.name === 'system.interconnect')
)
ok(
  'system.interconnect 没写进 config.background（后台接口只有 audio / request / geolocation）',
  (manifest.config.background.features || []).indexOf('system.interconnect') < 0
)
ok(
  'manifest 仍声明 system.fetch（有这条能力的机型照旧走原生）',
  manifest.features.some((f) => f.name === 'system.fetch')
)
ok(
  'api.js 不再静态 import @system.fetch（没有这条能力的机型上，静态 import 可能把整包模块图带崩）',
  !/^\s*import\s+\w+\s+from\s+'@system\.fetch'/m.test(apiSource)
)
ok('api.js 把 provider 打进日志（网桥机型排查第一眼就是它）', apiSource.indexOf('provider=') >= 0)
ok(
  'api.js 对网桥不支持的 responseType 明确报错（不是静默卡到超时）',
  apiSource.indexOf('BRIDGE_UNSUPPORTED_TYPES') >= 0
)

/* --------- 16. B 档纯逻辑：CRC32 / StreamAssembler / 请求帧的 stream 保护 --------- */

console.log('\n[16] B 档纯逻辑（CRC32 / StreamAssembler）')

// 16a. CRC32：IEEE/zlib 同款实现，标准测试向量打底
eq('crc32("123456789")（标准测试向量）', crc32('123456789'), 'cbf43926')
eq('crc32 空串 = 00000000（结束帧的 CRC 就长这样）', crc32(''), '00000000')
ok('内容变一个字节 CRC 就变（不是恒等函数）', crc32('abcdefgh') !== crc32('abcdefgi'))

// 16b. binaryToUint8：流帧字节 → @system.file 要的 Uint8Array
const binU8 = binaryToUint8(hexDecode('e4b8ade69687'))
eq('binaryToUint8 长度', binU8.length, 6)
eq('binaryToUint8 内容', Array.from(binU8), [0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87])

// 16c. StreamAssembler：顺序帧立即消费（落盘不攒堆）、结束帧收尾、重传帧忽略
const sAsm = new StreamAssembler({
  id: 's1',
  bodyEncoding: 'base64',
  chunkSize: 4,
  ack: true,
  checksum: 'crc32',
  contentLength: 10,
})
const sR1 = sAsm.push({ seq: 0, offset: 0, data: b64('abcd'), crc32: crc32('abcd') })
eq('顺序帧立即消费（不等收齐）', sR1.delivered.map((d) => utf8Decode(d.bytes)).join(''), 'abcd')
eq('ACK = 下一个仍缺失的连续序号', sR1.ack, 1)
const sR2 = sAsm.push({ seq: 1, offset: 4, data: b64('efgh'), crc32: crc32('efgh') })
eq('连续消费第二帧', utf8Decode(sR2.delivered[0].bytes), 'efgh')
ok('结束帧未到不算完', sR2.ended === false)
const sR2b = sAsm.push({ seq: 2, offset: 8, data: b64('ij'), crc32: crc32('ij') })
eq('尾数据帧照常消费', utf8Decode(sR2b.delivered[0].bytes), 'ij')
const sR3 = sAsm.push({ seq: 3, offset: 10, data: '', crc32: '00000000', final: true, totalBytes: 10 })
ok('结束帧触发 ended（自身不产出字节）', sR3.ended === true && sR3.delivered.length === 0)
eq('totalBytes 记录自结束帧', sAsm.totalBytes, 10)
const sDup = sAsm.push({ seq: 0, offset: 0, data: b64('abcd'), crc32: crc32('abcd') })
ok('重传已消费的帧被忽略、ACK 停在新前沿', sDup.accepted === false && sDup.ack === 4)

// 16d. 乱序缓存 / CRC 拒收 / 长度对账
const oAsm = new StreamAssembler({ id: 's2', bodyEncoding: 'base64', ack: true, checksum: 'crc32' })
const oR1 = oAsm.push({ seq: 1, offset: 4, data: b64('bbbb'), crc32: crc32('bbbb') })
eq('乱序帧先缓存（ACK 停在 0、什么都不消费）', [oR1.ack, oR1.delivered.length], [0, 0])
const oR2 = oAsm.push({ seq: 0, offset: 0, data: b64('aaaa'), crc32: crc32('aaaa') })
eq('★ 缺口补齐后按序一次吐出两帧（不是到达顺序）', oR2.delivered.map((d) => utf8Decode(d.bytes)).join(''), 'aaaabbbb')
const oR3 = oAsm.push({ seq: 2, offset: 8, data: b64('cc'), crc32: crc32('cc') })
eq('后续帧继续连续消费', oR3.delivered.map((d) => utf8Decode(d.bytes)).join(''), 'cc')
ok(
  'CRC 不过的帧整笔抛错（不推进 ACK、不落盘）',
  throwsCode(() => oAsm.push({ seq: 3, offset: 10, data: b64('xx'), crc32: 'deadbeef' }), BRIDGE_ERRORS.PROTOCOL)
)
const tAsm = new StreamAssembler({ id: 's3', bodyEncoding: 'base64', ack: true, checksum: 'crc32' })
tAsm.push({ seq: 0, offset: 0, data: b64('aaa'), crc32: crc32('aaa') })
ok(
  '结束帧 totalBytes 与实际不符时抛错（不把截断的音频交出去）',
  throwsCode(
    () => tAsm.push({ seq: 1, offset: 3, data: '', crc32: '00000000', final: true, totalBytes: 9 }),
    BRIDGE_ERRORS.PROTOCOL
  )
)
ok(
  '头部缺 ack:true 视为协议错（v4 不允许无 ACK 流式发送）',
  throwsCode(() => new StreamAssembler({ id: 's4', bodyEncoding: 'base64' }), BRIDGE_ERRORS.PROTOCOL)
)
ok(
  '偏移不连续时抛错（offset 双保险，漏帧在这里现形）',
  throwsCode(
    () =>
      new StreamAssembler({ id: 's5', bodyEncoding: 'base64', ack: true, checksum: 'crc32' }).push({
        seq: 0,
        offset: 4096,
        data: b64('x'),
        crc32: crc32('x'),
      }),
    BRIDGE_ERRORS.PROTOCOL
  )
)

// 16e. 请求帧的 stream 字段：普通请求必须显式关流（防 v4 自动流式吃掉大 JSON）
eq(
  '普通请求显式 stream:false（Content-Length >= 64KiB 的 JSON 才不会被自动流式）',
  buildFetchRequest({ id: 'q1', url: 'https://x' }).options.stream,
  false
)
const streamReq = buildFetchRequest({ id: 'q2', url: 'https://x', stream: true, fixedChunks: true })
eq('流式请求带 stream:true + fixedChunks:true', [streamReq.options.stream, streamReq.options.fixedChunks], [true, true])

/* --------- 17. v4 流端到端（桩扮演 v4 插件：CRC / 累计 ACK / go-back-N / 取消 / 超时） --------- */

console.log('\n[17] 网桥 v4 流端到端')

// 17a. 快乐路径：10 KB 响应 → 3 个数据帧 + 结束帧，字节按 offset 拼回原文
interconnectStub.__reset()
interconnectStub.__setRoute('https://cdn.example/stream-ok', { stream: true, body: 'x'.repeat(10000) })
const streamVm = await import('../src/services/interconnBridge.js?vm=stream-ok')
const okChunks = []
let okHeader = null
const okCtrl = streamVm.requestStream({
  url: 'https://cdn.example/stream-ok',
  headers: { Referer: 'https://www.bilibili.com' },
  onHeader: (info) => {
    okHeader = info
  },
  onChunk: (bin, off) => okChunks.push([off, bin]),
})
const okRes = await okCtrl.promise
eq('status 透传', okRes.status, 200)
eq('totalBytes 来自结束帧', okRes.totalBytes, 10000)
eq('★ 字节按 offset 连续拼回原文（分块落盘的数据正确性）', okChunks.map((c) => c[1]).join(''), 'x'.repeat(10000))
eq('首个 offset = 0', okChunks[0][0], 0)
eq('fixedChunks：非尾帧严格等于协商 chunkSize', okChunks[0][1].length, CONFIG.BRIDGE.CHUNK_SIZE)
ok('onHeader 拿到 contentLength（进度条的依据）', !!okHeader && okHeader.contentLength === 10000)
const okAckId = interconnectStub.__lastSent('fetch').id
const okAcks = interconnectStub.__acks(okAckId)
ok(
  '★ 流 ACK 每帧一报、单调不减、收齐时 = 数据帧数 + 1（结束帧也占序号）',
  okAcks.length === 4 &&
    okAcks.every((v, i, a) => i === 0 || v >= a[i - 1]) &&
    okAcks[okAcks.length - 1] === 4,
  JSON.stringify(okAcks)
)

// 17b. CRC 损坏帧：整笔拒绝 + 向插件发取消帧（关掉 HTTP source，不再白耗带宽）
interconnectStub.__reset()
interconnectStub.__setRoute('https://cdn.example/stream-crc', { stream: true, body: 'y'.repeat(9000), corruptSeq: 1 })
const crcVm = await import('../src/services/interconnBridge.js?vm=stream-crc')
let crcErr = null
try {
  await crcVm.requestStream({ url: 'https://cdn.example/stream-crc', onChunk: () => {} }).promise
} catch (e) {
  crcErr = e
}
ok(
  '★ CRC 坏帧整笔拒绝（绝不让坏文件落盘）',
  !!crcErr && crcErr.code === BRIDGE_ERRORS.PROTOCOL && /CRC/.test(crcErr.message),
  crcErr && crcErr.message
)
eq('并且发了 fetch-stream-cancel', interconnectStub.__streamCancels().length, 1)

// 17c. 插件侧读流中断（fetch-stream-error）→ 归类为网络错误
interconnectStub.__reset()
interconnectStub.__setRoute('https://cdn.example/stream-err', { stream: true, body: 'z'.repeat(9000), streamError: 2 })
const serrVm = await import('../src/services/interconnBridge.js?vm=stream-err')
let serr = null
try {
  await serrVm.requestStream({ url: 'https://cdn.example/stream-err', onChunk: () => {} }).promise
} catch (e) {
  serr = e
}
ok('读流中断报 E_BRIDGE_NETWORK', !!serr && serr.code === BRIDGE_ERRORS.NETWORK, serr && serr.code)

// 17d. 丢帧 → ACK 停滞 → 插件 go-back-N 重传补齐，数据一字不差
interconnectStub.__reset()
interconnectStub.__setRoute('https://cdn.example/stream-drop', { stream: true, body: 'w'.repeat(9000), dropSeq: [1] })
const dropVm = await import('../src/services/interconnBridge.js?vm=stream-drop')
const dropChunks = []
const dropRes = await dropVm
  .requestStream({ url: 'https://cdn.example/stream-drop', onChunk: (bin) => dropChunks.push(bin) })
  .promise
eq('★ 首传丢帧后靠 go-back-N 补齐，内容不变', dropChunks.join(''), 'w'.repeat(9000))
const dropAcks = interconnectStub.__acks(interconnectStub.__lastSent('fetch').id)
ok(
  'ACK 序列里存在停滞（证明重传路径真的被走到，不是巧合通过）',
  dropAcks.some((v, i) => i > 0 && v === dropAcks[i - 1]),
  JSON.stringify(dropAcks)
)

// 17e. 主动取消：CANCELLED 拒绝 + 桩侧传输状态立刻释放
interconnectStub.__reset()
interconnectStub.__setRoute('https://cdn.example/stream-cancel', { stream: true, body: 'c'.repeat(50000) })
const cancelVm = await import('../src/services/interconnBridge.js?vm=stream-cancel')
const cancelCtrl = cancelVm.requestStream({ url: 'https://cdn.example/stream-cancel', onChunk: () => {} })
for (let i = 0; i < 50 && cancelVm.describeState().streams === 0; i++) await tick()
eq('前置条件：流已在途', cancelVm.describeState().streams, 1)
cancelCtrl.cancel('测试取消') // 传输中途掐断（切歌场景）
let cancelErr = null
try {
  await cancelCtrl.promise
} catch (e) {
  cancelErr = e
}
ok(
  '主动取消报 E_BRIDGE_CANCELLED（切歌掐断下载的依据）',
  !!cancelErr && cancelErr.code === BRIDGE_ERRORS.CANCELLED,
  cancelErr && cancelErr.code
)
ok('取消帧已发给插件', interconnectStub.__streamCancels().length >= 1)
await tick()
await tick()
eq('桩侧传输状态已释放', interconnectStub.__inflightTransfers().length, 0)

// 17f. 宿主只有 v3 ⇒ 请求流明确报 UNSUPPORTED（不是静默走错路径）
interconnectStub.__reset()
interconnectStub.__setHostCaps({
  version: 3,
  chunk: true,
  maxChunkSize: 4096,
  encodings: ['base64', 'hex', 'text'],
  compressions: ['none', 'deflate', 'lz4'],
  ack: true,
  ackWindow: 4,
})
interconnectStub.__setRoute('https://cdn.example/stream-v3host', { stream: true, body: 'v3' })
const v3Vm = await import('../src/services/interconnBridge.js?vm=stream-v3host')
let v3Err = null
try {
  await v3Vm.requestStream({ url: 'https://cdn.example/stream-v3host', onChunk: () => {} }).promise
} catch (e) {
  v3Err = e
}
ok(
  '宿主只有 v3 时明确说「需要 v4 插件」',
  !!v3Err && v3Err.code === BRIDGE_ERRORS.UNSUPPORTED && /v4/.test(v3Err.message),
  v3Err && v3Err.message
)

// 17g. 流空闲超时：头部之后桩装死 → 空闲计时器判死并发取消
const savedIdle = CONFIG.BRIDGE.STREAM_IDLE_TIMEOUT
CONFIG.BRIDGE.STREAM_IDLE_TIMEOUT = 150
interconnectStub.__reset()
interconnectStub.__setRoute('https://cdn.example/stream-stall', { stream: true, body: 'x', streamStall: true })
const stallVm = await import('../src/services/interconnBridge.js?vm=stream-stall')
let stallErr = null
try {
  await stallVm.requestStream({ url: 'https://cdn.example/stream-stall', onChunk: () => {} }).promise
} catch (e) {
  stallErr = e
}
ok(
  '流空闲超时报 E_BRIDGE_TIMEOUT 并已发取消（不无限挂住）',
  !!stallErr && stallErr.code === BRIDGE_ERRORS.TIMEOUT && interconnectStub.__streamCancels().length === 1,
  stallErr && stallErr.code
)
CONFIG.BRIDGE.STREAM_IDLE_TIMEOUT = savedIdle
interconnectStub.__reset()

/* --------- 18. 音频缓存管理（audioCache：复用 / .part 转正 / 清理 / 预取 / 取消） --------- */

console.log('\n[18] 音频缓存管理（audioCache）')

const fileStub = await import('../scripts/stubs/system.file.mjs')
fileStub.__reset()
// 这台「机型」没有 @system.fetch（第 15 节已把它关掉）⇒ 本节的 cacheVm 走网桥 v4 流通道。
const cacheVm = await import('../src/services/audioCache.js?vm=cache')
const AUDIO_DIR = CONFIG.AUDIO_CACHE.DIR
const cacheNameOf = (key) => CONFIG.AUDIO_CACHE.PREFIX + key + CONFIG.AUDIO_CACHE.EXT
const cacheUriOf = (key) => AUDIO_DIR + cacheNameOf(key)

const cacheBody1 = 'AUDIO-1-' + 'a'.repeat(5000)
const cacheBody2 = 'AUDIO-2-' + 'b'.repeat(3000)
interconnectStub.__setRoute('https://cdn.example/BVC1.m4s', { stream: true, body: cacheBody1 })
interconnectStub.__setRoute('https://cdn.example/BVC2.m4s', { stream: true, body: cacheBody2 })
const cacheResolver = async (track) => 'https://cdn.example/' + track.bvid + '.m4s'

// 18a. 首播：落盘 → .part 转正 → 内容与源一致
const trackC1 = { bvid: 'BVC1' }
const got1 = await cacheVm.ensureTrackFile(trackC1, {
  resolveUrl: cacheResolver,
  keepKeys: [cacheVm.buildCacheKey(trackC1)],
})
ok('返回 internal://cache 下的本地 uri（无 .part）', got1.uri.indexOf('internal://cache/') === 0 && got1.uri.indexOf('.part') < 0, got1.uri)
ok('完成态文件存在、目录里没有 .part 残片', fileStub.__exists(got1.uri) && !Object.keys(fileStub.__files()).some((k) => /\.part$/.test(k)))
eq('★ 落盘字节与源一致（CRC 逐帧兜底）', Buffer.from(fileStub.__bytes(got1.uri)).toString('utf8'), cacheBody1)

// 18a-2. ★ 攒批落盘：v4 是 4 KB 一帧，逐帧一次 writeArrayBuffer 就是每首几百上千次原生 IPC。
// 攒到 WRITE_BATCH（默认 32 KB）才写一次 —— 本用例 80 KB = 20 帧：
//   逐帧写 → 20 次；攒批后 → 3 次（32K + 32K + 收尾 16K）。
// 断言「写次数」与「每笔长度」两个维度：只看次数的话，一次写坏、后面全靠重试也能凑出来。
// 最后一笔（16 KB < 批次）由 settleWrites 的收尾 flush 冲出 —— 漏了它文件就短一截，
// 而下一句「落盘字节与源一致」正是那个漏写的照妖镜。
{
  const batchBody = 'BATCH-' + 'B'.repeat(80 * 1024 - 6)
  const batchUrl = 'https://cdn.example/BVBATCH.m4s'
  interconnectStub.__setRoute(batchUrl, { stream: true, body: batchBody })
  const trackB = { bvid: 'BVBATCH' }
  const bFrom = fileStub.__writes().length // 只数本用例这几笔（__reset 会清掉 18a 留下的缓存，18b 还要用它验复用）
  const bGot = await cacheVm.ensureTrackFile(trackB, {
    resolveUrl: async () => batchUrl,
    // 保留名单带上 C1：落盘后 prune 会删名单外的文件，真机上这一栏本来就是
    // 「当前 + 前后曲目」，而 18b 还要拿 C1 的缓存验复用
    keepKeys: [cacheVm.buildCacheKey(trackC1), cacheVm.buildCacheKey(trackB)],
  })
  const bWrites = fileStub.__writes().slice(bFrom).filter((w) => w.uri.indexOf('BVBATCH') >= 0)
  ok(
    '★ 攒批落盘：20 帧只写 3 次（不再每帧一次原生 IPC）',
    bWrites.length === 3,
    '实际 ' + bWrites.length + ' 次：' + JSON.stringify(bWrites.map((w) => w.length))
  )
  eq('每笔都是攒满的一批（32 KB + 32 KB + 收尾 16 KB）', bWrites.map((w) => w.length), [32768, 32768, 16384])
  eq('★ 攒批后字节一字不差', Buffer.from(fileStub.__bytes(bGot.uri)).toString('utf8'), batchBody)
}

// 18b. 复用：第二次 ensure 零网络请求
const cacheFetchCount = () => interconnectStub.__sent().filter((f) => f.tag === 'fetch').length
const cBefore = cacheFetchCount()
const got1b = await cacheVm.ensureTrackFile(trackC1, { resolveUrl: cacheResolver })
eq('第二次命中缓存（cached 标记）', got1b.cached, true)
eq('★ 命中缓存零网络请求（复用的大头是音频流，不是 playurl）', cacheFetchCount() - cBefore, 0)

// 18c. 清理：名单外的完整文件、无人认领的 .part 都要被擦掉；名单内的不动
fileStub.__seed(AUDIO_DIR + cacheNameOf('bv_BVOLD'), 'old-cache')
fileStub.__seed(AUDIO_DIR + cacheNameOf('bv_BVORPHAN') + '.part', 'half-done')
const pruned = await cacheVm.pruneCache([cacheVm.buildCacheKey(trackC1)])
eq('清理了 2 个文件（1 个过期缓存 + 1 个孤儿残片）', pruned, 2)
ok('名单外的完整文件被删', !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVOLD')))
ok('孤儿 .part 被删', !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVORPHAN') + '.part'))
ok('保留名单内的缓存还在', fileStub.__exists(got1.uri))

// 18d. 预取：后台落盘下一首
const trackC2 = { bvid: 'BVC2' }
const pf2 = cacheVm.prefetchTrack(trackC2, {
  resolveUrl: cacheResolver,
  keepKeys: [cacheVm.buildCacheKey(trackC1), cacheVm.buildCacheKey(trackC2)],
})
const pf2Res = await pf2.promise
ok('预取完成后文件就位（可被正式播放直接命中）', !!pf2Res.uri && fileStub.__exists(pf2Res.uri))

// 18e. 预取取消：CANCELLED + 不留残片（取消发生在传输注册前也不能漏）
interconnectStub.__setRoute('https://cdn.example/BVC3.m4s', { stream: true, body: 'c'.repeat(20000) })
const trackC3 = { bvid: 'BVC3' }
const pf3 = cacheVm.prefetchTrack(trackC3, { resolveUrl: cacheResolver })
pf3.cancel('测试取消')
let pf3Err = null
try {
  await pf3.promise
} catch (e) {
  pf3Err = e
}
ok(
  '★ 预取被取消时以 CANCELLED 拒绝',
  !!pf3Err && pf3Err.code === BRIDGE_ERRORS.CANCELLED,
  `code=${pf3Err && pf3Err.code} msg=${pf3Err && pf3Err.message} files=${JSON.stringify(Object.keys(fileStub.__files()))}`
)
ok('取消后不留 BVC3 的任何文件（残片当场擦掉）', !Object.keys(fileStub.__files()).some((k) => k.indexOf('BVC3') >= 0))

// 18f. 启动清理：只删残片，完整缓存保留（跨次启动仍可秒开）
fileStub.__seed(AUDIO_DIR + cacheNameOf('bv_BVCRASH') + '.part', 'crash')
const orphans = await cacheVm.cleanupOrphans()
ok('启动清理删掉 .part 残片', orphans >= 1 && !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVCRASH') + '.part'))
ok('启动清理不动完整缓存', fileStub.__exists(got1.uri))

// 18g. 概况与清空（更多页「清理音频缓存」入口的后端）
const cacheInfo = await cacheVm.describeCache()
eq('概况只统计完成态文件', cacheInfo.count, 2)
ok('概况带字节数', cacheInfo.bytes > 0)
const cleared = await cacheVm.clearAudioCache()
eq('清空删除 2 个文件', cleared, 2)
eq('清空后目录里没有本服务文件', Object.keys(fileStub.__files()).length, 0)

// 18h. 缓存键：跨「解析取流前后」稳定，且是安全的文件名
eq('缓存键（bvid 优先）', cacheVm.buildCacheKey({ bvid: 'BV1xx411c7mD' }), 'bv_BV1xx411c7mD')
eq('缓存键（avid 兜底）', cacheVm.buildCacheKey({ id: 42 }), 'av_42')
eq('缓存键（多 P 不含 cid，键要跨解析前后稳定）', cacheVm.buildCacheKey({ bvid: 'BV1', cid: 99 }), 'bv_BV1')
eq('没有标识 → 空串（网桥机型播不了，报错说人话）', cacheVm.buildCacheKey({ title: 'x' }), '')

// 18i. **原生机型**的落盘链路（Range 分块 + 断点续传）—— 蓝牙机型 60-70 KiB/s 的解法
//
// 背景（真机实证）：走蓝牙那类慢链路上整文件下载只有 60-70 KiB/s，一首 2.5 MB 的歌
// 要 37 秒 → 单次 fetch 必超时（curl 28），而一次超时什么都没留下，同一首永远播不了。
// 所以原生机型改成「Range 取 256 KB → 追加写 → 记 written」：单块几秒跑完，
// 断了从断点续，第二次播直接命中缓存。
{
  fetchFeatureAvailable = true // 这台「机型」有 @system.fetch ⇒ 走原生分块通道
  const nativeBody = 'NATIVE-' + 'n'.repeat(900)
  const nativeUrl = 'https://cdn.example/BVN1.m4s'
  // api.js 的 nativeBroken 是**模块级单向锁存**（真机上一台设备只有一个事实），
  // 第 15 节验「没有 fetch 的机型」时已经把它置位。这里显式复位，模拟「换一台有 fetch 的机器」。
  const nativeApiVm = await import('../src/services/api.js') // 与 audioCache 共享同一实例
  nativeApiVm.__resetNativeProbe()
  const nativeCacheVm = await import('../src/services/audioCache.js?vm=cache-native')
  fetchStub.__setFile(nativeUrl, nativeBody)
  fetchStub.__setChunkBytes(400) // 服务器一次只给 400 字节：逼出多次 Range 请求
  const nativeTrack = { bvid: 'BVN1' }
  const nativeRes = await nativeCacheVm.ensureTrackFile(nativeTrack, {
    resolveUrl: async () => nativeUrl,
    keepKeys: [nativeCacheVm.buildCacheKey(nativeTrack)],
  })
  eq(
    '★ 原生机型也能落盘（Range 分块拼出完整文件）',
    Buffer.from(fileStub.__bytes(nativeRes.uri)).toString('utf8'),
    nativeBody
  )
  const ranged = fetchStub.__requests().filter((r) => r.responseType === 'arraybuffer')
  ok(
    '★ 确实分批取的（每笔都带 Range，不是一次整份）',
    ranged.length > 1 && ranged.every((r) => /^bytes=\d+-/.test(r.header.Range || '')),
    `range 请求 ${ranged.length} 笔`
  )
  // ★ 分块请求的头一个都不能少。真机现场：改成 Range 分块时漏了 UA，而 Vela 的 fetch
  //   底层是 libcurl，默认 UA 形如 `curl/8.x` —— B 站 upos 节点对 UA 有过滤：
  //   空 UA / curl UA 即使 Referer 正确也一律 403（mcdn 节点则完全不挑）。
  //   实测五种组合：Chrome UA 206、无 UA(undici) 206、空 UA 403、curl UA 403、不带 Referer 403。
  ok(
    '★ 每笔分块请求都带 UA + Referer（upos 按 UA 过滤：空/curl 一律 403）',
    ranged.every(
      (r) =>
        typeof r.header['User-Agent'] === 'string' &&
        r.header['User-Agent'].length > 10 &&
        r.header.Referer === CONFIG.BILI_REFERER
    ),
    '缺 UA 或 Referer：' + JSON.stringify(ranged[0] && ranged[0].header)
  )
  eq('分块写满总长即收工（Content-Range 报的总长 = 文件长度）', fileStub.__bytes(nativeRes.uri).length, nativeBody.length)

  // 断点续传：第二块被超时打断 → 重试时从断点继续，不从头再来
  const resumeBody = 'RESUME-' + 'r'.repeat(1200)
  const resumeUrl = 'https://cdn.example/BVN2.m4s'
  fetchStub.__setFile(resumeUrl, resumeBody)
  fetchStub.__setChunkFails(2) // 头两笔请求直接超时（code=28）
  const resumeTrack = { bvid: 'BVN2' }
  const resumeRes = await nativeCacheVm.ensureTrackFile(resumeTrack, { resolveUrl: async () => resumeUrl })
  eq(
    '★ 分块超时后重试并续传（内容仍然完整）',
    Buffer.from(fileStub.__bytes(resumeRes.uri)).toString('utf8'),
    resumeBody
  )
  const resumeRanges = fetchStub.__requests().filter((r) => r.responseType === 'arraybuffer')
  ok(
    '★ 头两块失败后不是整首重来（续传的 Range 起点 > 0）',
    resumeRanges.some((r) => /^bytes=[1-9]/.test(r.header.Range || '')),
    '所有 Range 都从 0 开始 = 没有续传'
  )

  // 候选地址：主地址整份失败 → 自动换下一条（B 站的 backupUrl 就是为这个给的）
  const goodUrl = 'https://cdn.example/BVN3-backup.m4s'
  const backupBody = 'BACKUP-' + 'b'.repeat(700)
  fetchStub.__setFile(goodUrl, backupBody)
  const backupTrack = { bvid: 'BVN3' }
  const backupRes = await nativeCacheVm.ensureTrackFile(backupTrack, {
    resolveUrl: async () => ['https://cdn.example/BVN3-主.m4s', goodUrl],
  })
  eq(
    '★ 主地址取不到时自动换候选地址（backupUrl 不是摆设）',
    Buffer.from(fileStub.__bytes(backupRes.uri)).toString('utf8'),
    backupBody
  )

  /* --- 真机现场（2026-09-18）：状态码、Content-Range、请求头全对，就是没有字节 ---
   *
   * `responseType:'arraybuffer'` 在这台机型上拿不到字节 —— 这不是网络错（重试同一读法
   * 不会变），也不是防盗链（403 才算），而是**读法不适用**。处置：换
   * `responseType:'file'`，让框架原生把这一段落到临时文件，我们分片读回再追加。
   * 屏幕上报的是「分块响应体为空」——这一节就是那句话的回归。 */
  nativeCacheVm.__resetBodyMode()
  const abBefore = fetchStub.__requests().length
  const abBody = 'AB-BROKEN-' + 'x'.repeat(1500)
  const abUrl = 'https://cdn.example/BVN4.m4s'
  fetchStub.__setFile(abUrl, abBody)
  fetchStub.__setArrayBufferBroken(true)
  const abRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN4' }, { resolveUrl: async () => abUrl })
  fetchStub.__setArrayBufferBroken(false)
  eq(
    '★ arraybuffer 拿不到字节时自动换 file 读法（落盘内容仍然完整）',
    Buffer.from(fileStub.__bytes(abRes.uri)).toString('utf8'),
    abBody
  )
  const abReqs = fetchStub.__requests().slice(abBefore)
  const abTried = abReqs.filter((r) => r.responseType === 'arraybuffer')
  const abFiles = abReqs.filter((r) => r.responseType === 'file')
  eq('★ 读法只探一次（整份下载里 arraybuffer 只试了第一笔，慢链路上试错很贵）', abTried.length, 1)
  ok(
    '★ 探明后每笔都走 file 读法（不是每块都先撞一次墙）',
    abFiles.length > 1 && abFiles.every((r) => /^bytes=\d+-/.test(r.header.Range || '')),
    `arraybuffer ${abTried.length} 笔 / file ${abFiles.length} 笔`
  )

  /* --- 瞬时空响应体：**不该一次就判死**（缩段重探/换通道接得住） ---
   * 这正是这次事故的第二个成因：原先的「为空就 throw」写在重试层之外，
   * 于是偶发的空响应体 = 整首永久失败。空响应体本身是确定性失败（不同段重试），
   * 但它还有缩段与换通道两级兜底 —— 恢复能力不减，白下的整块没了。 */
  nativeCacheVm.__resetBodyMode()
  const flakyBody = 'FLAKY-' + 'f'.repeat(1200)
  const flakyUrl = 'https://cdn.example/BVN5.m4s'
  fetchStub.__setFile(flakyUrl, flakyBody)
  fetchStub.__setEmptyBodyTimes(2) // 第一轮的两种读法都空，第二轮正常
  const flakyRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN5' }, { resolveUrl: async () => flakyUrl })
  eq(
    '★ 偶发空响应体会重试（不是一次就判死整首）',
    Buffer.from(fileStub.__bytes(flakyRes.uri)).toString('utf8'),
    flakyBody
  )

  /* --- 持续空响应体：必须把**现场**写进报错（真机上屏幕那行字就是全部线索） ---
   * 这几条验的是**报错本身**，所以把 request 通道关掉，让 fetch 分块的失败原样冒出来
   * （有 request 通道时会被它救走 —— 那是下面「换通道」那几条测试的事）。 */
  requestFeatureAvailable = false
  nativeCacheVm.__resetBodyMode()
  const deadReqBase = fetchStub.__requests().length
  const deadUrl = 'https://cdn.example/BVN6.m4s'
  fetchStub.__setFile(deadUrl, 'DEAD-' + 'd'.repeat(500))
  fetchStub.__setEmptyBodyTimes(40) // 一直空：Range 档位降到最后一档还是空，耗尽重试
  let deadErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN6' }, { resolveUrl: async () => deadUrl })
  } catch (e) {
    deadErr = (e && e.message) || String(e)
  }
  fetchStub.__setEmptyBodyTimes(0)
  ok(
    '★ 空响应体的报错带现场（状态码/声明长度/本机形态/试过的读法都在里头）',
    deadErr.indexOf('分块响应体为空') >= 0 &&
      deadErr.indexOf('HTTP 206') >= 0 &&
      deadErr.indexOf('本机 data undefined') >= 0 &&
      deadErr.indexOf('试过 arraybuffer') >= 0,
    '实际报错：' + deadErr
  )
  eq(
    '★ 空响应体不同段重试（4 档 × 2 读法 = 8 笔；同段重试 4 次是白下 24 笔整块，蓝牙上就是纯浪费）',
    fetchStub.__requests().slice(deadReqBase).length,
    8
  )

  /* --- file 读法给了 uri 但临时文件读不回来：报错要说清是「读回」失败 ⭐ ---
   * 这条能区分两种完全不同的故障：框架根本没落盘 vs 落了盘但读不出来。 */
  nativeCacheVm.__resetBodyMode()
  const tmpDeadUrl = 'https://cdn.example/BVN7.m4s'
  fetchStub.__setFile(tmpDeadUrl, 'TMPDEAD-' + 't'.repeat(400))
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  let tmpErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN7' }, { resolveUrl: async () => tmpDeadUrl })
  } catch (e) {
    tmpErr = (e && e.message) || String(e)
  }
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  ok(
    '★ 临时文件读不回来时报错说清是「读回」失败（不是含混的「播放失败」）',
    tmpErr.indexOf('临时文件读回失败') >= 0,
    '实际报错：' + tmpErr
  )

  /* --- 真机现场（2026-09-18 第二批）：`responseType:'file'` 给的 **tmp 分区** uri 读不回来 ---
   *
   * 屏幕上报的是「临时文件读回失败 code=202 invalid arguments」——不是 301 不存在，
   * 是「这个 uri 不该这么用」。官方「文件存储」章把 Temp 写成「只读，只能通过特定 API
   * 获取」；而参数表里 `file.copy` **只禁止 dstUri 是 tmp**（srcUri 不限，与 move 的
   * 双向禁止形成刻意的不对称）—— 所以路子是「原生整份拷进缓存目录，再分片读回」。
   * 这一节就是那句话的回归。 */
  nativeCacheVm.__resetBodyMode()
  const tmpReadBase = fileStub.__reads().length
  const copyBase = fileStub.__copies().length
  const tmpFixBody = 'TMPCOPY-' + 'c'.repeat(2000)
  const tmpFixUrl = 'https://cdn.example/BVN8.m4s'
  fetchStub.__setFile(tmpFixUrl, tmpFixBody)
  fetchStub.__setArrayBufferBroken(true)
  const tmpFixRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN8' }, { resolveUrl: async () => tmpFixUrl })
  fetchStub.__setArrayBufferBroken(false)
  eq(
    '★ tmp 分区读不回来时自动改走「原生拷出再读」（落盘内容完整）',
    Buffer.from(fileStub.__bytes(tmpFixRes.uri)).toString('utf8'),
    tmpFixBody
  )
  const tmpReadsOnTmp = fileStub.__reads().slice(tmpReadBase).filter((r) => r.uri.indexOf('internal://tmp/') === 0)
  eq('★ 直读 tmp 只撞一次墙就锁存（不是每块都白扔一次 IPC）', tmpReadsOnTmp.length, 1)
  const tmpCopies = fileStub.__copies().slice(copyBase)
  ok(
    '★ 每块都用 file.copy 从 tmp 拷出（copy 的 srcUri 允许 tmp，move 不允许）',
    tmpCopies.length > 1 && tmpCopies.every((c) => c.srcUri.indexOf('internal://tmp/') === 0),
    `copy ${tmpCopies.length} 次：` + JSON.stringify(tmpCopies.slice(0, 2))
  )
  ok(
    '★ 中转文件用完即删（缓存目录里不留 .part.tmp*）',
    !Object.keys(fileStub.__files()).some((k) => k.indexOf('.part.tmp') >= 0),
    JSON.stringify(Object.keys(fileStub.__files()))
  )

  // 另一类机型：tmp 分区**直接可读** → 不该白做一次原生拷贝（读法仍旧先探明再锁存）
  nativeCacheVm.__resetBodyMode()
  const directCopyBase = fileStub.__copies().length
  const directBody = 'TMPDIRECT-' + 'd'.repeat(1200)
  const directUrl = 'https://cdn.example/BVN9.m4s'
  fetchStub.__setFile(directUrl, directBody)
  fetchStub.__setArrayBufferBroken(true)
  fileStub.__setTmpReadAllowed(true)
  const directRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN9' }, { resolveUrl: async () => directUrl })
  fileStub.__setTmpReadAllowed(false)
  fetchStub.__setArrayBufferBroken(false)
  eq(
    '★ tmp 可直读的机型不多做拷贝（落盘内容一样完整）',
    Buffer.from(fileStub.__bytes(directRes.uri)).toString('utf8'),
    directBody
  )
  eq('★ 直读可用时一次 file.copy 都没有', fileStub.__copies().length - directCopyBase, 0)

  // 最坏情况：连 file.copy 都不许以 tmp 为源 —— 报错要把几条读法的结论都摆出来
  nativeCacheVm.__resetBodyMode()
  const noWayUrl = 'https://cdn.example/BVN10.m4s'
  fetchStub.__setFile(noWayUrl, 'NOWAY-' + 'n'.repeat(400))
  fetchStub.__setArrayBufferBroken(true)
  fileStub.__setCopyFromTmpDenied(true)
  let noWayErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN10' }, { resolveUrl: async () => noWayUrl })
  } catch (e) {
    noWayErr = (e && e.message) || String(e)
  }
  fileStub.__setCopyFromTmpDenied(false)
  fetchStub.__setArrayBufferBroken(false)
  ok(
    '★ 三条临时文件读法都不行时，报错同时给出每条读法的结论 + tmp uri 形态 + 只读探针',
    noWayErr.indexOf('临时文件读回失败') >= 0 &&
      noWayErr.indexOf('direct→') >= 0 &&
      noWayErr.indexOf('readtext→') >= 0 &&
      noWayErr.indexOf('copy→') >= 0 &&
      noWayErr.indexOf('tmp uri「internal://tmp/') >= 0 &&
      noWayErr.indexOf('access=') >= 0 &&
      noWayErr.indexOf('get=') >= 0,
    '实际报错：' + noWayErr
  )

  requestFeatureAvailable = true

  /* ============ 真机现场（2026-09-18 第三批）：fetch 这条路根本取不到字节 ============
   *
   * 屏幕上是「临时文件读回失败 code=202 invalid arguments」—— 直读 tmp、readText、
   * 拷出 tmp 三条都不通（这台机型对 tmp 分区完全封闭）。但**网络是通的**：206、
   * Content-Range、请求头全对。所以处置不是换地址，而是**换数据通道**：
   * `@system.request.download` 是原生下载管理器，它自己把字节写进应用缓存目录
   * （不是 tmp），既不占 JS 堆也不受 fetch 单次操作超时约束。
   */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const chBody = 'CHANNEL-' + 'z'.repeat(2200)
  const chUrl = 'https://cdn.example/BVN11.m4s'
  fetchStub.__setFile(chUrl, chBody)
  const chFetchBase = fetchStub.__requests().length
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  const chRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN11' }, { resolveUrl: async () => chUrl })
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  eq(
    '★ fetch 分块取不到字节时自动换 @system.request 整份原生下载（落盘内容完整）',
    Buffer.from(fileStub.__bytes(chRes.uri)).toString('utf8'),
    chBody
  )
  const chCalls = requestStub.__calls()
  eq('★ 下载任务只发一次（整份下载，不重复建任务）', chCalls.length, 1)
  // 真机现场（2026-09-19）：header 给对象回的是
  // `code=202 args type error, feature system.request, method: download` —— 任务根本建不起来。
  // 官方参数表里 download 的 header 是 **String**（`@system.fetch` 的才是 Object）。
  // 桩现在也照样拒绝非字符串：这条真机事故之前在 600+ 项断言里是隐身的。
  ok(
    '★ request.download 的 header 是**字符串**（给对象真机回 202 args type error，一个字节都不会下）',
    chCalls[0] && typeof chCalls[0].header === 'string',
    '实际 header：' + JSON.stringify(chCalls[0] && chCalls[0].header)
  )
  ok(
    '★ 首档打平成单行 `User-Agent: …`（upos 真正卡的就是 UA；单行不需要分行，CRLF/LF 两种解析器都吃）',
    chCalls[0] && chCalls[0].header === 'User-Agent: ' + CONFIG.USER_AGENT,
    '实际 header：' + JSON.stringify(chCalls[0] && chCalls[0].header)
  )
  ok(
    '★ 下载器侧解析出来的 UA 与分块同源（不是下载器自己编的 UA）',
    chCalls[0] && chCalls[0].parsed && chCalls[0].parsed['User-Agent'] === CONFIG.USER_AGENT,
    '解析结果：' + JSON.stringify(chCalls[0] && chCalls[0].parsed)
  )
  ok(
    '★ 换通道前先探过总长（1 字节 Range 只认响应头，用于长度对账）',
    fetchStub.__requests().slice(chFetchBase).some((r) => /^bytes=0-0$/.test(r.header.Range || '')),
    '没有看到 bytes=0-0 的探长请求'
  )

  // 通道锁存：第二首不再先撞一次 fetch 分块（一台设备的运行时问题不会因为换首歌而变）
  const chFetchBase2 = fetchStub.__requests().length
  const ch2Body = 'CHANNEL2-' + 'y'.repeat(900)
  const ch2Url = 'https://cdn.example/BVN12.m4s'
  fetchStub.__setFile(ch2Url, ch2Body)
  const ch2Res = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN12' }, { resolveUrl: async () => ch2Url })
  eq(
    '★ 通道锁存后第二首直接走 request（内容完整）',
    Buffer.from(fileStub.__bytes(ch2Res.uri)).toString('utf8'),
    ch2Body
  )
  // 只算**分块**请求：探总长那笔 bytes=0-0 是 request 通道自己要发的（长度对账）
  const ch2Chunks = fetchStub
    .__requests()
    .slice(chFetchBase2)
    .filter((r) => r.responseType !== 'arraybuffer' || !/^bytes=0-0$/.test(r.header.Range || ''))
  eq('★ 锁存后一笔 fetch 分块请求都不再发（不每首撞墙）', ch2Chunks.length, 0)

  // 长度对账：下载器不认请求头时（upos 按 UA 过滤）落下来的是 403 错误页，
  // **绝不能**把它当音频存成"完整缓存"（那样之后每次播都是没头没尾的播放失败）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  requestStub.__setIgnoreHeader(true)
  const denyUrl = 'https://cdn.example/BVN13.m4s'
  fetchStub.__setFile(denyUrl, 'REAL-AUDIO-' + 'q'.repeat(3000))
  fetchStub.__setArrayBufferBroken(true) // fetch 分块仍然取不到字节 ⇒ 才会走到 request 通道
  fetchStub.__setTmpFileMissing(true)
  let denyErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN13' }, { resolveUrl: async () => denyUrl })
  } catch (e) {
    denyErr = (e && e.message) || String(e)
  }
  requestStub.__setIgnoreHeader(false)
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  ok(
    '★ 下载器被 CDN 拒（403 错误页）时长度对账拦住它，不把错误页当缓存',
    denyErr.indexOf('整份下载长度不符') >= 0,
    '实际报错：' + denyErr
  )
  ok(
    '★ 被拒的那次没留下"完整缓存"文件',
    !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN13'))
  )
  eq(
    '★ 错误页不算「下到了东西」：HEADER_SHAPES 四档全试过（形态不对与设备不认头，在界面上长得一样）',
    requestStub.__calls().length,
    4
  )
  ok(
    '★ 错误页从没写进 .part（对账在搬进 .part 之前做，结构上留不下幽灵缓存）',
    !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN13') + '.part')
  )
  ok(
    '★ 四档都不成时也说得清（报错点明「N 档都一样」，不是一句没头没尾的失败）',
    denyErr.indexOf('4 档 header 形态都一样') >= 0,
    '实际报错：' + denyErr
  )

  /* --- header 形态阶梯：官方只写了类型（String），没写这串字符串怎么打包 ---
   * 所以形态要**逐档试**，唯一判据是长度对账。这台「设备」只认 JSON 串：
   * 前三档解析不出来 ⇒ 请求头等于没带 ⇒ 落下来是 403 错误页（几百字节，长度对账当场识破）⇒ 换档。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  requestStub.__setHeaderFormat('json')
  const jsBody = 'JSONHDR-' + 'm'.repeat(2600)
  const jsUrl = 'https://cdn.example/BVN21.m4s'
  fetchStub.__setFile(jsUrl, jsBody)
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  const jsRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN21' }, { resolveUrl: async () => jsUrl })
  const jsCalls = requestStub.__calls()
  eq(
    '★ 前几档被错误页打回后自己换到 JSON 档，内容完整落盘',
    Buffer.from(fileStub.__bytes(jsRes.uri)).toString('utf8'),
    jsBody
  )
  eq('★ 逐档试到第四档才成（line→crlf→lf→json）', jsCalls.length, 4)
  ok(
    '★ 每一档都是字符串，成功的第四档带上了整套头（Referer 也在）',
    jsCalls.every((c) => typeof c.header === 'string') &&
      jsCalls[3].parsed &&
      jsCalls[3].parsed.Referer === CONFIG.BILI_REFERER,
    '各档开头：' + JSON.stringify(jsCalls.map((c) => String(c.header).slice(0, 22)))
  )
  // 锁存：下一首第一档就是探明的 JSON，不再从 line 重撞
  const js2Body = 'JSONHDR2-' + 'n'.repeat(900)
  const js2Url = 'https://cdn.example/BVN22.m4s'
  fetchStub.__setFile(js2Url, js2Body)
  const js2Res = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN22' }, { resolveUrl: async () => js2Url })
  eq('★ 形态锁存后第二首一次就成（不再从第一档撞起）', requestStub.__calls().length - jsCalls.length, 1)
  eq(
    '★ 锁存后的内容同样完整',
    Buffer.from(fileStub.__bytes(js2Res.uri)).toString('utf8'),
    js2Body
  )
  requestStub.__setHeaderFormat('lines')
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)

  /* --- 真机现状（2026-09-19）：这台设备对**任何**字符串形态都回 202 args type error ---
   * 期望：四档都试（都不落地任何字节）、报错带上设备原话、并且不留下任何文件。
   * 这条断言是「下次真机又看到 202」时唯一能自证的东西。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  requestStub.__setHeaderFormat('reject')
  const rejUrl = 'https://cdn.example/BVN23.m4s'
  fetchStub.__setFile(rejUrl, 'REJECT-' + 'o'.repeat(1200))
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  let rejErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN23' }, { resolveUrl: async () => rejUrl })
  } catch (e) {
    rejErr = (e && e.message) || String(e)
  }
  requestStub.__setHeaderFormat('lines')
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  eq('★ 创建被拒时四档都试过（换的是形态，不是拿同一个对象反复撞）', requestStub.__calls().length, 4)
  ok(
    '★ 报错带上设备原话（args type error + feature/method），一眼能对上真机',
    rejErr.indexOf('args type error, feature system.request, method: download') >= 0,
    '实际报错：' + rejErr
  )
  ok(
    '★ 两条通道的现场都在（分块为什么不行 + 整份为什么不行），不是只剩半句话',
    rejErr.indexOf('分块：') >= 0 && rejErr.indexOf('整份：') >= 0,
    '实际报错：' + rejErr
  )
  ok(
    '★ 创建失败没留下任何文件（.part 与缓存名都不存在）',
    !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN23') + '.part') &&
      !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN23'))
  )

  /* --- 截断不换档：像音频但长度对不上（链路断在中途）是**网络**的事 ---
   * 换 header 形态既救不了、又要再下一遍整份 —— 所以这里必须只发一次任务。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const trBody = 'TRUNC-' + 't'.repeat(60 * 1024)
  const trUrl = 'https://cdn.example/BVN24.m4s'
  fetchStub.__setFile(trUrl, trBody)
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  requestStub.__setTruncate(20 * 1024) // 20 KB：远大于错误页，但短于总长
  let trErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN24' }, { resolveUrl: async () => trUrl })
  } catch (e) {
    trErr = (e && e.message) || String(e)
  }
  requestStub.__setTruncate(0)
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  eq('★ 截断不换 header 形态（不重复下一遍整份，慢链路上这是几 MB 的差别）', requestStub.__calls().length, 1)
  ok(
    '★ 截断报的是长度不符，且没写进 .part',
    trErr.indexOf('整份下载长度不符') >= 0 && !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN24') + '.part'),
    '实际报错：' + trErr
  )

  /* --- 进度盯的是下载管理器自己的落点（.part 在它搬过去之前根本不存在）---
   * 盯错位置的话进度永远是 0、空闲闸也永远不生效（`seen > 0` 才算数），只剩总超时一个闸门。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const savedPollMs = CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL = 20
  const pgBody = 'PROGRESS-' + 'p'.repeat(3000)
  const pgUrl = 'https://cdn.example/BVN25.m4s'
  fetchStub.__setFile(pgUrl, pgBody)
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  requestStub.__setSeedPartialBytes(1000) // 先只落 1000 字节，400ms 后才落完整份
  requestStub.__setCompleteDelay(400)
  const pgSeen = []
  const pgRes = await nativeCacheVm.ensureTrackFile(
    { bvid: 'BVN25' },
    { resolveUrl: async () => pgUrl, onProgress: (done) => pgSeen.push(done) }
  )
  requestStub.__setSeedPartialBytes(0)
  requestStub.__setCompleteDelay(0)
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL = savedPollMs
  ok(
    '★ 整份下载也有进度（轮询盯的是下载器的落点，不是还不存在的 .part）',
    pgSeen.length > 0 && pgSeen[pgSeen.length - 1] >= 1000,
    '进度回调：' + JSON.stringify(pgSeen)
  )
  eq(
    '★ 进度不影响落盘（内容仍然完整）',
    Buffer.from(fileStub.__bytes(pgRes.uri)).toString('utf8'),
    pgBody
  )

  /* --- responseType:'arraybuffer' 被运行时无视、直接给临时文件 uri ---
   * 官方 responseType 表里就是这个形态（不指定 responseType 且内容不是文本）。
   * 认不出来的失败方式是**静默**的：那串 uri 是字符串，而 bytesOfBody 认字符串为二进制串
   * —— uri 文本会被当成音频写进 .part，长度不对却看着像下好了。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const uriModeBody = 'URIMODE-' + 'u'.repeat(1500)
  const uriModeUrl = 'https://cdn.example/BVN26.m4s'
  fetchStub.__setFile(uriModeUrl, uriModeBody)
  fetchStub.__setArrayBufferAsUri(true)
  fileStub.__setTmpReadText('byte') // tmp 读得回来（这台「设备」tmp 是开的）
  const uriModeRes = await nativeCacheVm.ensureTrackFile(
    { bvid: 'BVN26' },
    { resolveUrl: async () => uriModeUrl }
  )
  fetchStub.__setArrayBufferAsUri(false)
  fileStub.__setTmpReadText('denied')
  eq(
    '★ arraybuffer 回的是临时文件 uri 时按文件处理（落盘的是音频，不是那串 uri 文本）',
    Buffer.from(fileStub.__bytes(uriModeRes.uri)).toString('utf8'),
    uriModeBody
  )
  eq('★ uri 文本不算「取不到字节」：一次 request 都没用上', requestStub.__calls().length, 0)

  /* --- 建任务无响应也要有闸门：运行时静默吞掉 download 调用（既不 success 也不 fail）时，
   * 页面不能一直挂着 —— 而且拿不到 token 就还轮不到下载过程那两道闸门。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const savedCreateGate = CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_CREATE
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_CREATE = 40
  requestStub.__setCreateSilent(true)
  const silentUrl = 'https://cdn.example/BVN27.m4s'
  fetchStub.__setFile(silentUrl, 'SILENT-' + 's'.repeat(800))
  fetchStub.__setArrayBufferBroken(true)
  fetchStub.__setTmpFileMissing(true)
  let silentErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN27' }, { resolveUrl: async () => silentUrl })
  } catch (e) {
    silentErr = (e && e.message) || String(e)
  }
  requestStub.__setCreateSilent(false)
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_CREATE = savedCreateGate
  ok(
    '★ 建任务无响应也有闸门（没有 token 就还轮不到下载过程的闸门）',
    silentErr.indexOf('下载任务创建无响应') >= 0,
    '实际报错：' + silentErr
  )

  /* --- 边下边播（progressive）⭐：request.download 没有 Range/分片参数，但落点是边下边长的 ---
   * waitDownloadComplete 每秒都在轮询落点大小 —— 落够 PROGRESSIVE_MIN 就把落点直接交给
   * 播放器开播，剩余字节在播放的同时继续落。蓝牙总时长不变，出声时间从几十秒缩到几秒。
   * 铁律不变：没转正的文件绝不冒充完整缓存（改名是完成态的唯一标志，延后不豁免）。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const savedProgPoll = CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL = 20
  fetchStub.__setArrayBufferBroken(true) // 这台「设备」fetch 分块取不到字节 ⇒ 走 request 通道（真机现状）
  fetchStub.__setTmpFileMissing(true)
  const progBody = 'PROG-' + 'g'.repeat(1200 * 1024) // 总长 ≥ 阈值(512K)×2 才值得边播边下
  const progUrl = 'https://cdn.example/BVN28.m4s'
  fetchStub.__setFile(progUrl, progBody)
  requestStub.__setTrickle({ chunk: 256 * 1024, tickMs: 10 }) // 每 10ms 长 256KB：两次 tick 就够到阈值
  requestStub.__setCompleteDelay(300) // 完成回调晚点来：留出「提前交付」的窗口
  const progTrack = { bvid: 'BVN28' }
  const progRes = await nativeCacheVm.ensureTrackFile(progTrack, { resolveUrl: async () => progUrl })
  eq('★ 落够阈值就提前交付（不等整份下完）', progRes.progressive, true)
  eq(
    '★ 交付的 uri 就是下载管理器的落点（缓存分区根上的 .part）',
    progRes.uri,
    'internal://cache/' + cacheNameOf('bv_BVN28') + '.part'
  )
  ok('★ 交付时只落了一部分（不是整份）', progRes.bytes > 0 && progRes.bytes < progBody.length)
  ok(
    '★ 此时正式缓存还不存在（没转正的文件绝不能冒充完整缓存）',
    !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN28'))
  )
  await progRes.done // 剩余字节下完（失败会在这里拒绝）
  eq(
    '★ 剩余下载完成后根上落点是完整的（长度对账仍通过）',
    fileStub.__bytes('internal://cache/' + cacheNameOf('bv_BVN28') + '.part').length,
    progBody.length
  )
  const progCached = await nativeCacheVm.getCachedFile(progTrack)
  ok('★ 下一次查询会先做收尾（转正后可被复用）', !!progCached && fileStub.__exists(progCached))
  eq('★ 转正后的内容完整', Buffer.from(fileStub.__bytes(progCached)).toString('utf8'), progBody)
  ok('★ 根上的落点已搬走（不留双份）', !fileStub.__exists('internal://cache/' + cacheNameOf('bv_BVN28') + '.part'))
  ok('★ .part 也不存在（收尾一步搬进缓存名）', !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN28') + '.part'))

  // 断在中途（已开播）：done 拒绝、已落盘部分留给播放器、绝不转正半份
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const cutBody = 'CUT-' + 'c'.repeat(1200 * 1024) // 总长 ≥ 阈值×2（1MB）：够格边播边下
  const cutUrl = 'https://cdn.example/BVN29.m4s'
  fetchStub.__setFile(cutUrl, cutBody)
  requestStub.__setTruncate(700 * 1024) // 下到 700KB 断：早过了阈值，开播了
  requestStub.__setTrickle({ chunk: 256 * 1024, tickMs: 10 })
  requestStub.__setCompleteDelay(300)
  const cutTrack = { bvid: 'BVN29' }
  const cutRes = await nativeCacheVm.ensureTrackFile(cutTrack, { resolveUrl: async () => cutUrl })
  eq('★ 断在中途也已经开播（阈值一过就交付）', cutRes.progressive, true)
  let cutDoneErr = ''
  try {
    await cutRes.done
  } catch (e) {
    cutDoneErr = (e && e.message) || String(e)
  }
  ok(
    '★ 剩余下载的失败从 done 冒出来（长度对账原话保留）',
    cutDoneErr.indexOf('整份下载长度不符') >= 0,
    '实际报错：' + cutDoneErr
  )
  ok(
    '★ 已开播的落点不被删除（音频还在读它，残局交给启动清理/重下收编）',
    fileStub.__exists('internal://cache/' + cacheNameOf('bv_BVN29') + '.part')
  )
  ok('★ 断掉的那份绝不会被转正', !fileStub.__exists(AUDIO_DIR + cacheNameOf('bv_BVN29')))
  // 重试同一首：残份长度对不上 ⇒ 不收编、清掉重下
  requestStub.__setTruncate(0)
  requestStub.__setTrickle(null)
  requestStub.__setCompleteDelay(0)
  const cutRetry = await nativeCacheVm.ensureTrackFile(cutTrack, { resolveUrl: async () => cutUrl })
  eq(
    '★ 重试清掉残份重新下（收编只认长度对账通过的完整落点）',
    Buffer.from(fileStub.__bytes(cutRetry.uri)).toString('utf8'),
    cutBody
  )
  ok('★ 残份的落点已清干净', !fileStub.__exists('internal://cache/' + cacheNameOf('bv_BVN29') + '.part'))

  // 收编孤儿：上次运行/上个 VM 没来得及转正的完整落点（长度对账通过）直接捡回来，不再下一遍
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const orphanBody = 'ORPHAN-' + 'o'.repeat(700 * 1024)
  const orphanUrl = 'https://cdn.example/BVN30.m4s'
  fetchStub.__setFile(orphanUrl, orphanBody)
  fileStub.__seed('internal://cache/' + cacheNameOf('bv_BVN30') + '.part', orphanBody)
  const orphanRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN30' }, { resolveUrl: async () => orphanUrl })
  eq('★ 上次留下的完整落点直接收编（一个下载任务都不建）', requestStub.__calls().length, 0)
  ok('★ 收编不算边下边播（整份已在本地，正常交付）', !orphanRes.progressive && !!orphanRes.uri)
  eq('★ 收编后的内容完整', Buffer.from(fileStub.__bytes(orphanRes.uri)).toString('utf8'), orphanBody)
  ok('★ 根上的落点已收走', !fileStub.__exists('internal://cache/' + cacheNameOf('bv_BVN30') + '.part'))
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)

  // 小文件不启用（总长不足阈值两倍，几秒就下完，没必要赌 growing file 的兼容性）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const smallBody = 'SMALL-' + 's'.repeat(3000)
  const smallUrl = 'https://cdn.example/BVN31.m4s'
  fetchStub.__setFile(smallUrl, smallBody)
  const smallRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN31' }, { resolveUrl: async () => smallUrl })
  ok('★ 小文件走整份交付（没有 progressive/done 字样）', !smallRes.progressive && !smallRes.done && !!smallRes.uri)

  // fetch 分块通道同样支持（健康机型的主通道）：自家往 .part 追加，落够两块就交付
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  fetchStub.__setChunkBytes(256 * 1024)
  const fBody = 'FETCHPROG-' + 'f'.repeat(1200 * 1024)
  const fUrl = 'https://cdn.example/BVN32.m4s'
  fetchStub.__setFile(fUrl, fBody)
  const fTrack = { bvid: 'BVN32' }
  const fRes = await nativeCacheVm.ensureTrackFile(fTrack, { resolveUrl: async () => fUrl })
  eq('★ fetch 分块通道同样支持边下边播（落够两块就交付）', fRes.progressive, true)
  eq(
    '★ fetch 通道的交付落点就是 .part（它本来自家就在往里追加）',
    fRes.uri,
    AUDIO_DIR + cacheNameOf('bv_BVN32') + '.part'
  )
  await fRes.done
  const fCached = await nativeCacheVm.getCachedFile(fTrack)
  eq('★ fetch 通道收尾转正后内容完整', Buffer.from(fileStub.__bytes(fCached)).toString('utf8'), fBody)
  fetchStub.__setChunkBytes(400)

  // 预取不边下边播：没人急着出声，仍静默整份（kind 门）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  fetchStub.__setChunkBytes(256 * 1024)
  const pfBody = 'PREFETCH-' + 'p'.repeat(1200 * 1024)
  const pfUrl = 'https://cdn.example/BVN33.m4s'
  fetchStub.__setFile(pfUrl, pfBody)
  const pf33 = nativeCacheVm.prefetchTrack({ bvid: 'BVN33' }, { resolveUrl: async () => pfUrl })
  const pf33Res = await pf33.promise
  ok('★ 预取整份下完才交付（后台没人等着出声）', !pf33Res.progressive && !!pf33Res.uri)
  fetchStub.__setChunkBytes(400)

  /* --- 设备能力落盘（storage）：「fetch 判死 / header 形态」是这台机的运行时事实 ---
   * 202/空体这类**设备拒绝**写下来，以后每个页面 VM、每次启动都不再把整条探测阶梯
   * 撞一遍；网络超时（curl 28）不是设备事实，绝不写 —— 万一只是蓝牙抖了一下。 */
  const capsRaw = storageStub.__dump()[CONFIG.STORAGE_KEYS.DL_CAPS]
  ok(
    '★ 「fetch 判死 + header 形态」已写进 storage（探明即落盘）',
    !!capsRaw && JSON.parse(capsRaw).channel === 'request' && JSON.parse(capsRaw).headerShape === 'line',
    String(capsRaw)
  )

  // 新 VM 接力：storage 里探明过的东西直接认，fetch 分块一笔都不撞
  nativeApiVm.__resetNativeProbe()
  const capsCacheVm = await import('../src/services/audioCache.js?vm=cache-native2')
  requestStub.__reset()
  const capsBody = 'CAPS-' + 'x'.repeat(3000)
  const capsUrl = 'https://cdn.example/BVN34.m4s'
  fetchStub.__setFile(capsUrl, capsBody)
  const capsReqBase = fetchStub.__requests().length
  const capsRes = await capsCacheVm.ensureTrackFile({ bvid: 'BVN34' }, { resolveUrl: async () => capsUrl })
  const capsReqs = fetchStub.__requests().slice(capsReqBase)
  ok(
    '★ 新 VM 只发 1 字节探针，一条分块请求都不再发（上个 VM 探明的死讯直接认）',
    capsReqs.length > 0 && capsReqs.every((r) => (r.header.Range || '') === 'bytes=0-0'),
    JSON.stringify(capsReqs.map((r) => r.header.Range))
  )
  eq('★ header 形态直接用探明的档（第一笔就成了）', requestStub.__calls().length, 1)
  eq(
    '★ storage 接力的落盘内容完整',
    Buffer.from(fileStub.__bytes(capsRes.uri)).toString('utf8'),
    capsBody
  )

  // 反面：网络失败**不是**设备事实，不许写
  nativeCacheVm.__resetBodyMode() // 回 fetch 通道
  requestStub.__reset()
  storageStub.__seed({ [CONFIG.STORAGE_KEYS.DL_CAPS]: '' }) // 清空（空串 = 无记录）
  requestFeatureAvailable = false // 也关掉 request 通道，让 fetch 的网络失败原样冒出来
  fetchStub.__setChunkFails(50) // 全部 code=28（网络超时，不是空响应体）
  let netErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN35' }, { resolveUrl: async () => 'https://cdn.example/BVN35.m4s' })
  } catch (e) {
    netErr = (e && e.message) || String(e)
  }
  fetchStub.__setChunkFails(0)
  requestFeatureAvailable = true
  ok('★ 网络失败照样报错（没有通道可以救，也不该救）', netErr.length > 0, netErr)
  ok(
    '★ 网络失败不写设备能力（下次启动还要再试 fetch，万一这次只是蓝牙抖了）',
    !storageStub.__dump()[CONFIG.STORAGE_KEYS.DL_CAPS]
  )

  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL = savedProgPoll

  /* --- Range 档位阶梯：响应体太大被运行时丢掉时，先缩段而不是换通道 ---
   * 快应用规范里 fetch 写着「数据大小不能超过 100k」，而首档是 256 KB。
   * 缩段能救回来就说明：这台机型不需要走 tmp、也不需要换通道。 */
  fetchStub.__setChunkBytes(0) // 响应体 = 请求的跨度（不然 400 字节的响应永远不超限）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const capReqBase = fetchStub.__requests().length
  // 响应体必须真的**超过**上限，阶梯才会被触发：200 KB 的曲子 + 64 KB 的丢体线
  const capBody = 'CAP-' + 'k'.repeat(200 * 1024)
  const capUrl = 'https://cdn.example/BVN14.m4s'
  fetchStub.__setFile(capUrl, capBody)
  fetchStub.__setArrayBufferMaxBytes(64 * 1024) // >64 KB 的 arraybuffer 响应体一律丢
  fetchStub.__setTmpFileMissing(true) // 且 tmp 这条路也走不通（真机现场）⇒ 只剩缩段
  const capRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN14' }, { resolveUrl: async () => capUrl })
  fetchStub.__setArrayBufferMaxBytes(0)
  fetchStub.__setTmpFileMissing(false)
  eq(
    '★ 响应体超限时自动缩小 Range 档位（落盘内容完整）',
    Buffer.from(fileStub.__bytes(capRes.uri)).toString('utf8'),
    capBody
  )
  eq('★ 缩段救回来了：一次 request 都没用上', requestStub.__calls().length, 0)
  const capRanges = fetchStub.__requests().slice(capReqBase).filter((r) => r.responseType === 'arraybuffer')
  const capSpans = capRanges.map((r) => {
    const m = /bytes=(\d+)-(\d+)/.exec(r.header.Range || '')
    return m ? Number(m[2]) - Number(m[1]) + 1 : 0
  })
  ok(
    '★ 首档确实撞了墙（第一笔是 256 KB），之后每笔都 ≤64 KB',
    capSpans.length > 1 && capSpans[0] === 256 * 1024 && Math.max.apply(null, capSpans.slice(1)) <= 64 * 1024,
    '各笔跨度：' + JSON.stringify(capSpans.slice(0, 6))
  )

  // 档位一路降到最小还是空 → 才轮到换通道（阶梯与通道是两级兜底，顺序不能反）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const tinyUrl = 'https://cdn.example/BVN15.m4s'
  const tinyBody = 'TINY-' + 'j'.repeat(40 * 1024) // 比最小档（16 KB）还大
  fetchStub.__setFile(tinyUrl, tinyBody)
  fetchStub.__setArrayBufferMaxBytes(8 * 1024) // 最小档 16 KB 也超限 ⇒ 阶梯救不回来
  fetchStub.__setTmpFileMissing(true)
  const tinyRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN15' }, { resolveUrl: async () => tinyUrl })
  fetchStub.__setArrayBufferMaxBytes(0)
  fetchStub.__setTmpFileMissing(false)
  eq(
    '★ 阶梯走到底才换通道（两级兜底顺序：先缩段、再换通道）',
    Buffer.from(fileStub.__bytes(tinyRes.uri)).toString('utf8'),
    tinyBody
  )
  eq('★ 阶梯耗尽后才建了 1 个下载任务', requestStub.__calls().length, 1)

  /* --- readText 读法：官方唯一点了名的 tmp 读法 ---
   * 二进制经文本接口有一个前提：字符串与字节一一对应。三种映射都试、每一种都自证。 */
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const rtCopyBase = fileStub.__copies().length
  const rtBody = 'READTEXT-' + 'r'.repeat(1500)
  const rtUrl = 'https://cdn.example/BVN16.m4s'
  fetchStub.__setFile(rtUrl, rtBody)
  fetchStub.__setArrayBufferBroken(true)
  fileStub.__setTmpReadText('byte') // 一字节一字符：可无损取回
  const rtRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN16' }, { resolveUrl: async () => rtUrl })
  fileStub.__setTmpReadText('denied')
  fetchStub.__setArrayBufferBroken(false)
  eq(
    '★ readText 给的是一字节一字符时直接用它（落盘内容完整）',
    Buffer.from(fileStub.__bytes(rtRes.uri)).toString('utf8'),
    rtBody
  )
  eq('★ readText 这条读法能用就不做原生拷贝', fileStub.__copies().length - rtCopyBase, 0)
  ok('★ readText 确实被用上了', fileStub.__textReads().length > 0)

  // base64：无损但需要解码（官方 encoding 参数）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const b64Body = 'B64TEXT-' + 'b'.repeat(1700)
  const b64Url = 'https://cdn.example/BVN17.m4s'
  fetchStub.__setFile(b64Url, b64Body)
  fetchStub.__setArrayBufferBroken(true)
  fileStub.__setTmpReadText('base64')
  const b64Res = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN17' }, { resolveUrl: async () => b64Url })
  fileStub.__setTmpReadText('denied')
  fetchStub.__setArrayBufferBroken(false)
  eq(
    '★ readText 只给 base64 时解码取回（落盘内容完整）',
    Buffer.from(fileStub.__bytes(b64Res.uri)).toString('utf8'),
    b64Body
  )
  ok(
    '★ 试过显式 encoding:base64（不然拿到的只会是被解坏的文本）',
    fileStub.__textReads().some((r) => r.encoding === 'base64' && r.ok)
  )

  // 真按 UTF-8 解码（二进制被解坏）时必须**拒掉**，退到能拿到精确字节的读法 ——
  // 悄悄用坏字节会让那首歌变成"永久坏缓存"，比报错难查一百倍
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const lossyBody = 'LOSSY-' + '\u00ff\u00ee'.repeat(300)
  const lossyUrl = 'https://cdn.example/BVN18.m4s'
  fetchStub.__setFile(lossyUrl, lossyBody)
  fetchStub.__setArrayBufferBroken(true)
  fileStub.__setTmpReadText('utf8') // 文本解码：长度/码元都对不上
  const lossyRes = await nativeCacheVm.ensureTrackFile({ bvid: 'BVN18' }, { resolveUrl: async () => lossyUrl })
  fileStub.__setTmpReadText('denied')
  fetchStub.__setArrayBufferBroken(false)
  eq(
    '★ readText 解坏了字节时拒掉该读法，退到拷出再读（内容仍然完整）',
    Buffer.from(fileStub.__bytes(lossyRes.uri)).toString('utf8'),
    lossyBody
  )
  ok(
    '★ 坏字节没被写进 .part（是靠 file.copy 那条精确读法救回来的）',
    fileStub.__copies().length > rtCopyBase
  )

  // 超时闸门：下载任务迟迟不完成不能让页面挂着（总时长闸）
  nativeCacheVm.__resetBodyMode()
  requestStub.__reset()
  const savedWholeTimeout = CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_TIMEOUT
  const savedWholePoll = CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_TIMEOUT = 150
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL = 20
  requestStub.__setCompleteDelay(5000)
  const hangUrl = 'https://cdn.example/BVN19.m4s'
  fetchStub.__setFile(hangUrl, 'HANG-' + 'h'.repeat(400))
  fetchStub.__setArrayBufferBroken(true) // 逼进 request 通道
  fetchStub.__setTmpFileMissing(true)
  let hangErr = ''
  try {
    await nativeCacheVm.ensureTrackFile({ bvid: 'BVN19' }, { resolveUrl: async () => hangUrl })
  } catch (e) {
    hangErr = (e && e.message) || String(e)
  }
  requestStub.__setCompleteDelay(0)
  fetchStub.__setArrayBufferBroken(false)
  fetchStub.__setTmpFileMissing(false)
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_TIMEOUT = savedWholeTimeout
  CONFIG.AUDIO_CACHE.WHOLE_DOWNLOAD_POLL = savedWholePoll
  ok('★ 整份下载超时有闸门（不让页面无限等）', hangErr.indexOf('整份下载超时') >= 0, '实际报错：' + hangErr)

  /* --- tmp 读法的中转文件属于 .part 家族：不算「已缓存」，启动清理要能收干净 --- */
  const scratchUri = AUDIO_DIR + cacheNameOf('bv_BVSCRATCH') + '.part.tmp262144'
  const bytesBeforeScratch = (await nativeCacheVm.describeCache()).bytes
  fileStub.__seed(scratchUri, 'half-copied')
  eq(
    '★ 中转文件（.part.tmp*）不算「已缓存」（字节数不变）',
    (await nativeCacheVm.describeCache()).bytes,
    bytesBeforeScratch
  )
  const scratchRemoved = await nativeCacheVm.cleanupOrphans()
  ok(
    '★ 启动清理按 .part 家族把中转文件一起扫掉',
    scratchRemoved >= 1 && !fileStub.__exists(scratchUri),
    `清理 ${scratchRemoved} 个，仍存在=${fileStub.__exists(scratchUri)}`
  )
  // 下载管理器是先落在缓存分区**根**上的（默认名字给不了子目录），进程被杀就会留残片在根上
  const rootPart = 'internal://cache/' + cacheNameOf('bv_BVROOT') + '.part'
  const foreignPart = 'internal://cache/somebody-else.part'
  fileStub.__seed(rootPart, 'root-leftover')
  fileStub.__seed(foreignPart, 'not-ours')
  const rootRemoved = await nativeCacheVm.cleanupOrphans()
  ok(
    '★ 缓存分区根上的本服务残片也会被启动清理收掉',
    rootRemoved >= 1 && !fileStub.__exists(rootPart)
  )
  ok('★ 别人的 .part 文件一根手指都不碰（前缀 + .part 双条件）', fileStub.__exists(foreignPart))

  // 桩与真机必须同形：官方 success 形态是 { code, data, headers }，**没有 status**，
  // 且 `data` 的类型由 responseType 决定（官方表：arraybuffer→ArrayBuffer、file→临时文件 uri）。
  // 这条断言是防「离线自检自己骗自己」的闸门 —— 2026-01 真机翻车就是两边一起写错字段名，
  // 而这一次是桩把 arraybuffer 与 file 都回成了 Uint8Array，于是「真机 arraybuffer
  // 拿不到字节」这种读法问题在 500+ 项里完全看不出来。
  const probeShape = await new Promise((resolve) => {
    fetchStub.fetch({
      url: nativeUrl,
      method: 'GET',
      responseType: 'arraybuffer',
      header: { Range: 'bytes=0-9' },
      success: (res) => resolve(res),
      fail: () => resolve(null),
    })
  })
  ok(
    '★ 桩的 fetch 响应与真机同形（code/data/headers，不自创 status）',
    probeShape && typeof probeShape.code === 'number' && !('status' in probeShape),
    probeShape ? '字段：' + Object.keys(probeShape).join(',') : '没有响应'
  )
  ok(
    "★ responseType:'arraybuffer' 给的是 ArrayBuffer（官方表，不是 Uint8Array）",
    probeShape && probeShape.data instanceof ArrayBuffer,
    probeShape ? describeBodyShape(probeShape.data) : '没有响应'
  )
  const probeFileShape = await new Promise((resolve) => {
    fetchStub.fetch({
      url: nativeUrl,
      method: 'GET',
      responseType: 'file',
      header: { Range: 'bytes=0-9' },
      success: (res) => resolve(res),
      fail: () => resolve(null),
    })
  })
  ok(
    "★ responseType:'file' 给的是临时文件 uri（不是字节 —— 当成字节写进 .part 就是往音频里塞路径）",
    probeFileShape && typeof probeFileShape.data === 'string' && /^[a-z][a-z0-9+.-]*:\/\//i.test(probeFileShape.data),
    probeFileShape ? 'data 形态：' + describeBodyShape(probeFileShape.data) : '没有响应'
  )

  // 全 upos/edge 候选跳过直链（实测它们必 403）：不再白等一次往返 + 一次强制重取流
  storageStub.__seed({ [CONFIG.STORAGE_KEYS.DL_CAPS]: '' }) // 清掉设备能力：这个 VM 从 fetch 通道走（别让上面的判死记录把它推去 request）
  const skipVm = (await import('../src/services/playerService.js?vm=pskip')).default
  skipVm.init({ display: true, control: true })
  let skipFallback = false
  const unsubSkip = skipVm.subscribe((type) => {
    if (type === 'fallback') skipFallback = true
  })
  skipVm.setUrlResolver(async () => ['https://upos.example/BVUP1.m4s'])
  fetchStub.__setFile('https://upos.example/BVUP1.m4s', 'SKIP-' + 's'.repeat(2500))
  await skipVm.adopt()
  await skipVm.setQueue([{ bvid: 'BVUP1', title: '丙', artist: 'u', duration: 180 }], 0)
  await until(() => readShare().state === 'playing', 3000)
  const skipSrc = audioStub.__state().src
  ok(
    '★ 全 upos 候选没碰直链（src 直接是本地文件，不是 CDN 地址）',
    skipSrc.indexOf(CONFIG.AUDIO_CACHE.DIR) === 0,
    'src=' + skipSrc
  )
  ok('★ 一次 fallback 都没有（403 的抢救路径整个没进）', !skipFallback)
  unsubSkip()
  skipVm.stopTicking()

  fetchStub.__setChunkBytes(0)
  fetchStub.__reset()
  fileStub.__reset()
  fetchFeatureAvailable = false // 还原：第 19 节要的是「网桥机型」这个前提
}

interconnectStub.__reset()
fileStub.__reset()

console.log('\n[19] B 档端到端（网桥机型：落盘播放 + 预取）')

// 前提（15d 已证）：这台「机型」没有 @system.fetch ⇒ playerService 自动走 audioCache 链路。
const bbBody1 = 'SONG-1-' + 'a'.repeat(5000)
const bbBody2 = 'SONG-2-' + 'b'.repeat(3000)
interconnectStub.__setRoute('https://cdn.example/BV1.m4s', { stream: true, body: bbBody1 })
interconnectStub.__setRoute('https://cdn.example/BV2.m4s', { stream: true, body: bbBody2 })
fileStub.__reset()

const bbVm = (await import('../src/services/playerService.js?vm=bbridge')).default
const bbResolver = async (track) => 'https://cdn.example/' + track.bvid + '.m4s'
// 合成 VM：一个 VM 全绑（真机上 display/control 分属主页 VM 与 app VM，见第 9 节）
bbVm.init({ display: true, control: true })
bbVm.setUrlResolver(bbResolver)
await bbVm.adopt()

await bbVm.setQueue(
  [
    { bvid: 'BV1', title: '甲', artist: 'u', duration: 180 },
    { bvid: 'BV2', title: '乙', artist: 'u', duration: 200 },
  ],
  0
)
await until(() => readShare().state === 'playing')

const bbSrc1 = audioStub.__state().src
ok(
  '★ 播的是落盘文件（internal://cache 下，不是 CDN 直链）',
  bbSrc1.indexOf(CONFIG.AUDIO_CACHE.DIR) === 0 && bbSrc1.indexOf('.part') < 0,
  bbSrc1
)
eq('fromCache 标记', bbVm.getSnapshot().fromCache, true)
const bbFile1 = Object.keys(fileStub.__files()).find((k) => k.indexOf('bv_BV1') >= 0)
eq('★ 落盘字节与源一致', Buffer.from(fileStub.__bytes(bbFile1)).toString('utf8'), bbBody1)

// 起播后下一首已在后台预取落盘
await until(() => !!Object.keys(fileStub.__files()).find((k) => k.indexOf('bv_BV2') >= 0), 2000)
const bbFetchCount = () => interconnectStub.__sent().filter((f) => f.tag === 'fetch').length
eq('起播 + 预取正好两笔取流（没有多余请求）', bbFetchCount(), 2)

// 播完自动下一首：命中预取缓存，一笔网络都不用发
audioStub.__emit('onended')
// index 先行（playAt 开头就发布 loading），本地文件要等预取/落盘完成、onplay 之后才是乙的
await until(() => readShare().index === 1 && readShare().state === 'playing')
eq('切到第二首', (await bbVm.adopt()).track.title, '乙')
const bbSrc2 = audioStub.__state().src
ok(
  '★ 第二首直接播预取好的本地文件',
  bbSrc2.indexOf(CONFIG.AUDIO_CACHE.DIR) === 0 && bbSrc2.indexOf('bv_BV2') >= 0,
  bbSrc2
)
eq('★ 预取命中后零新增网络请求（切歌零等待的机制所在）', bbFetchCount(), 2)

// 更多页的清理入口接线（后端在 18g 验证过，这里钉页面接线）
const moreUxSrc = readFileSync(new URL('../src/pages/more/more.ux', import.meta.url), 'utf8')
ok(
  'more.ux 有「清理音频缓存」入口且走 audioCache（不在页面里裸调 @system.file）',
  moreUxSrc.indexOf('清理音频缓存') >= 0 &&
    moreUxSrc.indexOf('onClearCache') >= 0 &&
    moreUxSrc.indexOf('services/audioCache') >= 0
)
const playerUxSrc = readFileSync(new URL('../src/pages/player/player.ux', import.meta.url), 'utf8')
// 歌手行渲染必须是 `hint || artist`：播放态文案（缓冲中…/已暂停）要能覆盖歌手名，
// 正在播放时 hint 为空串才走回歌手名。钉住这个顺序，避免将来谁顺手改回去。
ok(
  'player.ux 歌手行渲染走 `hint || artist`（播放态文案优先于歌手名）',
  /\{\{\s*hint\s*\|\|\s*artist\s*\}\}/.test(playerUxSrc) &&
    /\{\{\s*artist\s*\|\|\s*hint\s*\}\}/.test(playerUxSrc) === false
)
ok(
  'more.ux 缓存概况经 describeCache 展示、清理后回收定时器',
  moreUxSrc.indexOf('describeCache') >= 0 && moreUxSrc.indexOf('onDestroy') >= 0
)
ok(
  'app.ux 启动时清理 .part 残片（audioCache.cleanupOrphans）',
  readFileSync(new URL('../src/app.ux', import.meta.url), 'utf8').indexOf('cleanupOrphans') >= 0
)
ok(
  'manifest 声明了 system.file（B 档落盘的凭据，aiot build 缺了会拦）',
  manifest.features.some((f) => f.name === 'system.file')
)
ok(
  'manifest 声明了 system.request（整份原生下载通道的凭据：源码 require 了它）',
  manifest.features.some((f) => f.name === 'system.request')
)

audioStub.__reset()
fetchFeatureAvailable = true // 还原：网桥窗口结束（B 档用例全部跑完）

/* ---------------------------- 汇总 ---------------------------- */

console.log(`\n${'='.repeat(40)}`)
console.log(`通过 ${passed} 项，失败 ${failed} 项`)
console.log('='.repeat(40))

process.exit(failed === 0 ? 0 : 1)
