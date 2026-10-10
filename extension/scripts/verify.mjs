/**
 * Chrome 扩展纯逻辑离线自检（纯 Node，无网络、无 chrome.*）
 *
 *   node extension/scripts/verify.mjs
 *
 * 覆盖 src/core/ 下所有纯函数，外加 store.js 的 displayPosition（纯逻辑、
 * chrome.* 只在函数体内出现，Node 可直接 import）。
 *
 */

import { readFileSync } from 'node:fs'
import { relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { md5, deriveMixinKey, filterWbiValue, signWbi, signApp } from '../src/core/crypto.js'
import { av2bv, extractBvid, extractAid } from '../src/core/av_bv.js'
import { urlDeadline, isUrlFresh, filterFreshUrls, uniq, collectCandidates, asStreamList } from '../src/core/cdn.js'
import {
  mapResultType,
  cleanTitle,
  buildSubtitle,
  normalizeCover,
  parseSearchItem,
  parseSearchResults,
  emptySearchResponse,
  classifyQuery,
  RESULT_TYPES,
} from '../src/core/search.js'
import { trackKey, sameTrack, findTrackIndex } from '../src/core/tracks.js'
import {
  normalizeFavTrack,
  normalizeFavList,
  capFavList,
  toggleInFavList,
} from '../src/core/fav_local.js'
import {
  buildCookieHeader,
  COOKIE_ORDER,
  pickBiliCookies,
  fromCookieInfo,
  isBiliDomain,
  filterBiliJarCookies,
  hostOnlyToRehome,
  BILI_COOKIE_URL,
  COOKIE_DOMAIN,
} from '../src/auth/cookies.js'
import { encode, toSvg } from '../src/qr/qr_encode.js'
import { displayPosition } from '../src/ui/shared/store.js'

let pass = 0
let fail = 0
const failures = []

function eq(actual, expected, label) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) {
    pass++
    return
  }
  fail++
  failures.push(`${label}\n    期望 ${e}\n    实际 ${a}`)
}

function ok(cond, label) {
  if (cond) {
    pass++
    return
  }
  fail++
  failures.push(label)
}

function section(name) {
  process.stdout.write(`\n${name}\n`)
}

/* ------------------------------------------------------------------ MD5 */

section('MD5')
eq(md5(''), 'd41d8cd98f00b204e9800998ecf8427e', 'md5 空串')
eq(md5('abc'), '900150983cd24fb0d6963f7d28e17f72', 'md5 "abc"')
eq(md5('message digest'), 'f96b697d7cb7938d525a2f31aaf161d0', 'md5 "message digest"')
// 中文走 UTF-8 编码路径（不是 UTF-16 码元）
eq(md5('测试'), md5('测试'), 'md5 中文自洽')
ok(/^[0-9a-f]{32}$/.test(md5('测试')), 'md5 中文结果是 32 位小写十六进制')

/* -------------------------------------------------- WBI 官方向量（三方对齐） */

section('WBI 签名（官方向量）')
const imgKey = '7cd084941338484aae1ad9425b84077c'
const subKey = '4932caff0ff746eab6f01bf08b70ac45'
eq(deriveMixinKey(imgKey, subKey), 'ea1db124af3c7062474693fa704f4ff8', 'mixin_key 派生')

const signed = signWbi({ foo: 114, bar: 514, zab: 1919810 }, 'ea1db124af3c7062474693fa704f4ff8', 1702204169)
eq(
  `bar=${signed.bar}&foo=${signed.foo}&wts=${signed.wts}&zab=${signed.zab}&w_rid=${signed.w_rid}`,
  'bar=514&foo=114&wts=1702204169&zab=1919810&w_rid=8f6f2b5b3d485fe1886cec6a0be8c5d4',
  'signWbi 复现官方 w_rid'
)

// 参数按键名升序，wts 参与排序
const ordered = signWbi({ b: '2', a: '1' }, 'ea1db124af3c7062474693fa704f4ff8', 1702204169)
ok(Object.keys(ordered).join(',') === 'b,a,wts,w_rid', '返回对象保留原键序 + 追加 wts/w_rid')

// 值里的 !'()* 在编码前剔除
eq(filterWbiValue("a!b(c)d*e"), 'abcde', "过滤 !'()*")

// 口令不足 64 位直接报错，不静默签出一个「格式对但内容错」的 w_rid
let threw = false
try {
  deriveMixinKey('short', 'alsoshort')
} catch {
  threw = true
}
ok(threw, '口令不足 64 位抛错（Dart 侧 WbiSigner.mixinKeyOf 同语义）')

/* ----------------------------------------------------------- APP 签名（TV 扫码） */

section('APP 签名')
const appSigned = signApp({ local_id: 0, ts: 1702204169 }, '4409e2ce8ffd12b8', '59b43e04ad6965f34319062b478f83dd')
ok(!!appSigned.sign, 'APP 签名产出 sign')
// signApp 先塞 appkey 再整体按 key 升序，所以 appkey 排在 local_id / ts 前面
eq(
  appSigned.sign,
  md5('appkey=4409e2ce8ffd12b8&local_id=0&ts=1702204169' + '59b43e04ad6965f34319062b478f83dd'),
  'APP 签名按 key 升序拼接'
)
ok(appSigned.appkey === '4409e2ce8ffd12b8', 'APP 签名带上 appkey')

/* ------------------------------------------------- AV/BV（对照 Dart 实测值） */

section('AV→BV（对照 lib/core/network/av_bv.dart 实测输出）')
eq(av2bv(1), 'BV1xx411c7mQ', 'av1')
eq(av2bv(2), 'BV1xx411c7mD', 'av2')
eq(av2bv(99), 'BV1xx411c7mj', 'av99')
eq(av2bv(170001), 'BV17x411w7KC', 'av170001')
eq(av2bv(1234567), 'BV1vx411T7HC', 'av1234567')
eq(av2bv(888888888), 'BV14K4y1g74T', 'av888888888')

ok(extractBvid('BV1xx411c7mD') === 'BV1xx411c7mD', 'extractBvid 裸 BV')
ok(extractBvid('  https://www.bilibili.com/video/BV1xx411c7mD?spm=') === 'BV1xx411c7mD', 'extractBvid 从 URL 抠')
ok(extractBvid('随便一首') === '', 'extractBvid 抠不到返回空串')
ok(extractAid('AV170001') === 170001, 'extractAid 大写')
ok(extractAid('av170001') === 170001, 'extractAid 小写')
ok(extractAid('170001') === 0, 'extractAid 没有 av 前缀返回 0')

/* --------------------------------------------------------- 搜索输入分派 */

section('搜索输入分派（对照 api_service.dart 的 search 三段分支）')
eq(classifyQuery('BV1xx411c7mD'), { kind: 'bvid', value: 'BV1xx411c7mD' }, 'BV 号直查稿件')
eq(classifyQuery('AV170001'), { kind: 'bvid', value: 'BV17x411w7KC' }, 'AV 号先转 BV')
eq(classifyQuery('周杰伦'), { kind: 'keyword', value: '周杰伦' }, '关键词')
eq(classifyQuery('   '), { kind: 'keyword', value: '' }, '纯空白视作空输入')
eq(classifyQuery('  BV1xx411c7mD  '), { kind: 'bvid', value: 'BV1xx411c7mD' }, '前后空白剔除')

/* ----------------------------------------------------------- 搜索结果解析 */

section('搜索结果解析（对照 SearchResult.fromJson / _parseSearchResults）')

eq(mapResultType('video'), 'video', 'result_type=video')
eq(mapResultType('media_bangumi'), 'bangumi', 'result_type=media_bangumi → bangumi')
eq(mapResultType('upuser'), 'upuser', 'result_type=upuser')
eq(mapResultType('bili_user'), null, '未知 result_type 返回 null（整组跳过）')

// 富文本标题：先剥 <em> 标签，再解实体（顺序不能反）
eq(cleanTitle('<em>周杰伦</em> - 晴天'), '周杰伦 - 晴天', '剥 em 标签')
eq(cleanTitle('&quot;晴天&quot;'), '"晴天"', '解 &quot;')
eq(cleanTitle('a &amp; b'), 'a & b', '解 &amp;')
eq(cleanTitle(null), '', '标题为 null 返回空串（不是字符串 "null"）')
eq(cleanTitle('<em>A</em> &lt;b&gt;'), 'A <b>', '先剥标签后解实体')

// 副标题六种类型
eq(buildSubtitle({ author: 'UP主A', tag: '音乐' }, 'video'), 'UP主A - 音乐', 'video 副标题')
eq(buildSubtitle({ fans: 1234 }, 'author'), '1234 粉丝', 'author 副标题')
eq(buildSubtitle({ desc: '简介' }, 'bangumi'), '简介', 'bangumi 副标题')
eq(buildSubtitle({ thread: 9 }, 'topic'), '9 讨论', 'topic 副标题')
eq(buildSubtitle({ uname: '某用户' }, 'upuser'), '某用户', 'upuser 副标题')
eq(buildSubtitle({}, 'video'), '未知作者 - ', 'video 缺字段兜底')

eq(normalizeCover('//i0.hdslb.com/abs.jpg'), 'https://i0.hdslb.com/abs.jpg', '协议相对地址补 https')
eq(normalizeCover('https://x/y.jpg'), 'https://x/y.jpg', '绝对地址原样')
eq(normalizeCover(''), '', '空封面')

const videoItem = parseSearchItem(
  { bvid: 'BV17x411w7KC', title: '<em>晴天</em>', author: '周杰伦', tag: '音乐', pic: '//i0.hdslb.com/a.jpg' },
  'video'
)
ok(videoItem.playable === true, 'video 且有 bvid → playable')
eq(videoItem.title, '晴天', '曲目标题已清洗')
eq(videoItem.bvid, 'BV17x411w7KC', '曲目 bvid 保留')

const userItem = parseSearchItem({ mid: 42, uname: '某UP', fans: 999, pic: '' }, 'upuser')
eq(userItem.id, '42', 'upuser 取 mid 当 id')
ok(userItem.playable === false, '非 video 类型不可播放')

// season_id 兜底：bvid/mid 都缺时才轮到（Dart 的 ?? 链语义）
const seasonItem = parseSearchItem({ season_id: 777, title: '某番剧' }, 'bangumi')
eq(seasonItem.id, '777', 'bvid/mid 缺失时落到 season_id')

const parsed = parseSearchResults(
  {
    result: [
      { result_type: 'video', data: [{ bvid: 'BV17x411w7KC', title: '晴天', author: '周杰伦' }] },
      { result_type: 'bili_user', data: [{ uname: '不该出现' }] },
      { result_type: 'video', data: [{ bvid: 'BV1xx411c7mD', title: '第二首', author: '某人' }] },
    ],
    page: 1,
    numPages: 3,
  },
  '周杰伦'
)
eq(parsed.results.length, 2, '未知 result_type 的整组被跳过')
eq(parsed.keyword, '周杰伦', 'keyword 透传')
ok(parsed.hasMore === true, 'page < numPages → hasMore')
// totalResults 只累加**被识别的组**：bili_user 那组在 _mapResultType 返回 null 时
// 已经 continue 掉了，它的条目不计入（与 api_service.dart 一致）
eq(parsed.totalResults, 2, 'totalResults 只数被识别组里的条目')

const lastPage = parseSearchResults({ result: [], page: 3, numPages: 3 }, 'x')
ok(lastPage.hasMore === false, '最后一页 hasMore=false')

// data 不是对象（接口异常形态）也不能抛
const garbage = parseSearchResults(null, 'x')
eq(garbage.results.length, 0, 'data 为 null 不抛错')

// 关键词缺失字段时 page/numPages 退化成 1
const noPaging = parseSearchResults({ result: [] }, 'x')
eq(noPaging.page, 1, '缺 page 退化为 1')
eq(noPaging.hasMore, false, '缺 numPages 时 hasMore=false')

const empty = emptySearchResponse('foo')
eq(empty.results, [], 'emptySearchResponse')
eq(empty.page, 0, 'emptySearchResponse.page=0')

ok(RESULT_TYPES.includes('bangumi') && RESULT_TYPES.length === 6, '六种结果类型齐全')

/* ----------------------------------------------------------- CDN 地址时效 */

section('CDN 地址时效（deadline 实测 120 分钟）')
const DEADLINE = 1700000000
const base = `https://upos.example.com/x.m4s?deadline=${DEADLINE}&foo=1`
eq(urlDeadline(base), DEADLINE, 'urlDeadline 解析')
eq(urlDeadline('https://x/y.m4s'), 0, '无 deadline 返回 0')
eq(urlDeadline('https://x/?deadline=123'), 0, '位数不足不认')

// 时间注入用「距 deadline 还剩多少秒」来表达，比算毫秒时间戳不容易写错
const atRemaining = (sec) => (DEADLINE - sec) * 1000

ok(isUrlFresh(base, atRemaining(3600), 300) === true, '剩余 1 小时（余量 5 分钟）→ 新鲜')
ok(isUrlFresh(base, atRemaining(60), 300) === false, '剩余 1 分钟 < 余量 → 过期')
ok(isUrlFresh(base, atRemaining(0), 300) === false, '已过 deadline → 过期')
ok(isUrlFresh('https://x/y.m4s', atRemaining(0), 300) === true, '无 deadline 一律当有效（不做无根据的猜测）')

const kept = filterFreshUrls([base, 'https://x/y.m4s'], atRemaining(60), 300)
eq(kept, ['https://x/y.m4s'], 'filterFreshUrls 滤掉过期地址')
// filterFreshUrls 只管过期、不去重（去重是 uniq 的职责），所以两份都新鲜就都留着
eq(filterFreshUrls([base, base], atRemaining(3600), 300), [base, base], '都新鲜时原样返回，不做去重')

eq(uniq(['a', 'b', 'a', '', null, 'c']), ['a', 'b', 'c'], 'uniq 去重且保持顺序')

eq(
  collectCandidates({ baseUrl: 'https://a', backup_url: ['https://b', 'https://a'] }),
  ['https://a', 'https://b'],
  'collectCandidates 主地址排第一 + 去重'
)
eq(collectCandidates({ base_url: 'https://c', backupUrl: ['https://d'] }), ['https://c', 'https://d'], '兼容 base_url/backupUrl 小写下划线')
eq(collectCandidates(null), [], 'collectCandidates(null)')

eq(asStreamList({ id: 30280 }), [{ id: 30280 }], '单对象包成数组')
eq(asStreamList([{ id: 30232 }, { id: 30216 }]).length, 2, '数组原样')
eq(asStreamList('nope'), [], '非法输入返回空数组')

/* ------------------------------------------------------------- 曲目同一性 */

section('曲目同一性（tracks）')
eq(trackKey({ bvid: 'BV1xx' }), 'bv:BV1xx', 'trackKey 优先 bvid')
eq(trackKey({ id: 123 }), 'av:123', 'trackKey 退化到 avid')
eq(trackKey({ aid: 456 }), 'av:456', 'trackKey 认 aid')
eq(trackKey({}), '', '无标识返回空串')
eq(trackKey(null), '', 'null 返回空串')

ok(sameTrack({ bvid: 'BV1' }, { bvid: 'BV1' }) === true, '同 bvid → 同一首')
ok(sameTrack({ bvid: 'BV1' }, { id: 1 }) === false, '一方有 bvid 一方只有 avid → 不同（宁可重复入队）')
ok(sameTrack({ id: 1 }, { id: 1 }) === true, '同 avid → 同一首')
ok(sameTrack({}, { id: 1 }) === false, '取不到键一律 false')

const list = [{ bvid: 'a' }, { bvid: 'b' }, { id: 9 }]
eq(findTrackIndex(list, { bvid: 'b' }), 1, 'findTrackIndex 命中')
eq(findTrackIndex(list, { bvid: 'zz' }), -1, 'findTrackIndex 未命中 -1')
eq(findTrackIndex(list, {}), -1, '无键返回 -1')

/* --------------------------------------------------------- 本地收藏（纯逻辑） */

section('本地收藏（fav_local）')

const vol = normalizeFavTrack({ bvid: 'BV1', title: 't', streams: ['https://过期'], playUrl: 'https://过期', url: 'https://过期' })
ok(!('streams' in vol) && !('playUrl' in vol) && !('url' in vol), '白名单重建剥掉易变取流字段（过期 CDN 直链绝不落盘）')
eq(vol.title, 't', '保留标题')
ok(vol.favTime > 0, '有 favTime')

ok(normalizeFavTrack({ title: '没有键' }) === null, '无键曲目返回 null（收藏了也找不回来）')
eq(normalizeFavTrack({ bvid: 'BV9' }, 1700000000000).favTime, 1700000000000, '缺 favTime 用注入值')

const dup = normalizeFavList([
  { bvid: 'BV1', title: '旧', favTime: 100 },
  { bvid: 'BV1', title: '新', favTime: 200 },
  { bvid: 'BV2', title: '另一首', favTime: 300 },
  { title: '垃圾' },
])
eq(dup.length, 2, '按 key 去重 + 垃圾条目丢弃')
eq(dup[0].bvid, 'BV2', '按 favTime 倒序（最新收藏的排最前）')
eq(dup[1].title, '新', '同 key 保留 favTime 新的那份')

const t1 = { bvid: 'BV1', title: '一' }
const t2 = { bvid: 'BV2', title: '二' }

const added = toggleInFavList([], t1, 1000)
ok(added.added === true && added.changed === true, '首次收藏 → added')
eq(added.list.length, 1, '收藏后表长 1')

const removed = toggleInFavList(added.list, t1, 2000)
ok(removed.added === false && removed.changed === true, '再次 toggle → 移除')
eq(removed.list.length, 0, '移除后表空')

// 重收藏要把条目提到最前
const reFav = toggleInFavList(
  [normalizeFavTrack(t2, 500)],
  t1,
  999
)
eq(reFav.list[0].bvid, 'BV1', '新收藏 unshift 到最前')

// 没键的曲目动不了表
const noop = toggleInFavList([{ bvid: 'BV1' }], { title: '无键' })
ok(noop.changed === false, '无键 toggle → changed=false（不必写盘）')
eq(noop.list.length, 1, '无键 toggle 不改表')

// capFavList 不排序，假定入参已按 favTime 倒序（normalizeFavList 的输出）
const big = Array.from({ length: 600 }, (_, i) => ({ bvid: 'BV' + i, favTime: 600 - i }))
eq(capFavList(big).length, 500, '满表截断到 500')
eq(capFavList(big)[0].bvid, 'BV0', '保留在表头的（最新收藏的）')
ok(!capFavList(big).some((t) => t.bvid === 'BV500'), '丢的是表尾的（最旧的）')
eq(capFavList([{ bvid: 'BV1' }]).length, 1, '未超限原样返回')
eq(capFavList(null).length, 0, 'null 当空数组')

/* --------------------------------------------------------- Cookie 头拼装 */

section('Cookie 头装配（session 同序）')
eq(
  buildCookieHeader({ SESSDATA: 'S', bili_jct: 'J', DedeUserID: '1', DedeUserID__ckMd5: 'M' }),
  'SESSDATA=S; bili_jct=J; DedeUserID=1; DedeUserID__ckMd5=M',
  '四项关键 Cookie 按固定顺序拼接'
)
eq(
  buildCookieHeader({ sid: 'x', SESSDATA: 'S' }),
  'SESSDATA=S; sid=x',
  '关键项在前，其余追加在后'
)
eq(buildCookieHeader(null), '', 'null 返回空串')
eq(buildCookieHeader({}), '', '空对象返回空串')
eq(buildCookieHeader({ SESSDATA: '' }), '', '空值项不拼进去')
eq(COOKIE_ORDER[0], 'SESSDATA', 'COOKIE_ORDER 首项是 SESSDATA')
ok(COOKIE_ORDER.includes('bili_jct'), 'COOKIE_ORDER 含 bili_jct（写接口的 csrf 来源）')

// chrome.cookies.getAll 的返回 → 键值对
const picked = pickBiliCookies([
  { name: 'SESSDATA', value: 'S', domain: '.bilibili.com' },
  { name: 'buvid3', value: 'B', domain: '.bilibili.com' },
  { name: 'unnecessary', value: 'x', domain: '.bilibili.com' },
  { name: 'bili_jct', value: '', domain: '.bilibili.com' },
])
eq(picked, { SESSDATA: 'S', buvid3: 'B' }, 'pickBiliCookies 只留白名单项且丢空值')
eq(pickBiliCookies(null), {}, 'pickBiliCookies(null)')

// TV 扫码响应体 cookie_info.cookies[] → 键值对
eq(
  fromCookieInfo([
    { name: 'SESSDATA', value: 'S' },
    { name: 'bili_jct', value: 'J' },
    { name: 'DedeUserID', value: '1' },
  ]),
  { SESSDATA: 'S', bili_jct: 'J', DedeUserID: '1' },
  'fromCookieInfo 摊平数组'
)
eq(fromCookieInfo(undefined), {}, 'fromCookieInfo(undefined)')

// 两条登录路径最终必须拼出同一个串，否则会出现「扫码能用、导入不能用」
const viaQr = buildCookieHeader(fromCookieInfo([{ name: 'SESSDATA', value: 'S' }, { name: 'bili_jct', value: 'J' }]))
const viaBrowser = buildCookieHeader(pickBiliCookies([
  { name: 'bili_jct', value: 'J' },
  { name: 'SESSDATA', value: 'S' },
]))
eq(viaQr, viaBrowser, '两条登录路径拼出的 Cookie 头一致（与输入顺序无关）')

// Cookie 域：读 jar 的过滤 + 写 jar 的落点。

// chrome.cookies.getAll({domain:'.bilibili.com'}) 在点边界上比字符串，
// www/api 子域与裸 bilibili.com 全部匹配不上——host-only 的 SESSDATA 会被漏掉。
// 判据：源码里不许出现带前导点的 domain 过滤（注释里提到这段是允许的，
// 所以只匹配真的当参数传的那一处写法 `getAll({domain:'.`）。
const authDir = new URL('../src/auth/', import.meta.url)
for (const f of ['session.js', 'qr_login.js']) {
  const src = readFileSync(new URL(f, authDir), 'utf8')
  ok(
    !/getAll\(\s*\{\s*domain:\s*'\./.test(src),
    `${f} 不用带前导点的 domain 过滤读 jar（改用 {url}）`
  )
}
ok(BILI_COOKIE_URL === 'https://www.bilibili.com/', 'BILI_COOKIE_URL 指向主站（覆盖 api/passport 子域）')
ok(COOKIE_DOMAIN === '.bilibili.com', 'COOKIE_DOMAIN 是带前导点的域 Cookie')

// chrome.cookies.set 省略 domain 即 host-only，api 子域收不到。
const sessionSrc = readFileSync(new URL('session.js', authDir), 'utf8')
ok(
  /domain:\s*c\.domain\s*\|\|\s*COOKIE_DOMAIN/.test(sessionSrc),
  '扫码写回 jar 时显式给 domain（服务端没给就兜底 COOKIE_DOMAIN），不落成 host-only'
)
// 读 jar 走的是「全量 + 域判据」，不给 getAll 传过滤条件（URL 过滤语义不可单测，
// domain 过滤会漏读——上一条断言就盯着这个）
ok(
  /getAll\(\s*\{\s*\}\s*\)/.test(sessionSrc),
  'readJarCookies 用 getAll({}) + 域判据，不依赖浏览器的过滤语义'
)
// 两条登录路径都要过 nav 补资料；导入路径漏了就是固定的「（未取到昵称）」
ok(/getUserInfo/.test(sessionSrc), '导入路径也调 nav 补资料')
const importBody = sessionSrc.slice(
  sessionSrc.indexOf('export async function importFromBrowser'),
  sessionSrc.indexOf('async function adoptJarCookies')
)
ok(/getUserInfo\(\)/.test(importBody) && /updateProfile\(/.test(importBody), 'importFromBrowser 里确实调了 nav 并回填资料')
// 登出：两种域形态都要试一次，否则 www 上的 host-only 票据摘不掉
ok(removalUrlsBothHosts(sessionSrc), 'clearAuth 的候选地址同时覆盖 www.bilibili.com 与 bilibili.com')

function removalUrlsBothHosts(src) {
  const i = src.indexOf('function removalUrls')
  if (i < 0) return false
  const body = src.slice(i, i + 700)
  return /www\.bilibili\.com/.test(body) && /withPath\('bilibili\.com'\)/.test(body)
}

// pickBiliCookies 的输出 → 该补域的那几条（host-only 才补，带点的与白名单外的都不动）
eq(
  hostOnlyToRehome(
    [
      { name: 'SESSDATA', value: 'HOST', domain: 'www.bilibili.com' },
      { name: 'SESSDATA', value: 'DOMAIN', domain: '.bilibili.com' },
      { name: 'buvid3', value: 'B', domain: '.bilibili.com' },
      { name: 'b_nut', value: 'n', domain: 'bilibili.com' },
    ],
    { SESSDATA: 'HOST' }
  ).map((c) => `${c.name}@${c.domain}`),
  ['SESSDATA@www.bilibili.com'],
  'hostOnlyToRehome 只挑白名单内、host-only 的那条（带点的不动、白名单外的不管）'
)
eq(hostOnlyToRehome(null, {}).length, 0, 'hostOnlyToRehome(null)')
eq(hostOnlyToRehome([{ name: 'SESSDATA', value: 'x', domain: 'bilibili.com' }], {}).length, 0, '没进 picked 的补都不补')

eq(isBiliDomain('.bilibili.com'), true, 'isBiliDomain 认域 Cookie')
eq(isBiliDomain('bilibili.com'), true, 'isBiliDomain 认裸域（host-only 落点）')
eq(isBiliDomain('www.bilibili.com'), true, 'isBiliDomain 认子域')
eq(isBiliDomain('api.bilibili.com'), true, 'isBiliDomain 认 api 子域')
eq(isBiliDomain('evilbilibili.com'), false, 'isBiliDomain 不认后缀相似的假域')
eq(isBiliDomain('notbilibili.com.evil.com'), false, 'isBiliDomain 不认伪装成子域的域')
eq(isBiliDomain(undefined), false, 'isBiliDomain(undefined)')

const jar = [
  { name: 'SESSDATA', value: 'S', domain: 'www.bilibili.com' },
  { name: 'buvid3', value: 'B', domain: '.bilibili.com' },
  { name: 'other', value: 'x', domain: 'example.com' },
]
eq(filterBiliJarCookies(jar).length, 2, 'filterBiliJarCookies 只留 B 站域')
eq(filterBiliJarCookies(null).length, 0, 'filterBiliJarCookies(null)')

// 摊平去重：同名两条（host-only + 域 Cookie）只留先到的那条的值。
// jar 的排序按 path 长度、同长度按创建时间，所以**不假定哪条先**——
// 这里只断言「留下的是其中一条、且白名单外的丢掉」。
const duped = pickBiliCookies([
  { name: 'SESSDATA', value: 'HOST', domain: 'bilibili.com' },
  { name: 'SESSDATA', value: 'DOMAIN', domain: '.bilibili.com' },
  { name: 'b_nut', value: 'n', domain: '.bilibili.com' },
])
eq(Object.keys(duped), ['SESSDATA'], '同名票据摊平去重 + 白名单外的丢掉')
ok(duped.SESSDATA === 'HOST' || duped.SESSDATA === 'DOMAIN', '留下的是同名两条中的一条')

/* ------------------------------------------------------------- QR 编码 */

section('QR 编码（对照 Python qrcode 库生成的矩阵）')

const qrFixtures = JSON.parse(
  readFileSync(new URL('./fixtures/qr_matrices.json', import.meta.url), 'utf8')
)

function rowsOf(qr) {
  return qr.modules.map((row) => row.map((c) => (c ? '1' : '0')).join(''))
}

/**
 * 逐位比对，失配时报告**第一个不同的位置**——整幅矩阵几十乘几十，
 * 只说「不相等」没法定位是数据铺错了还是格式信息摆错了。
 */
function diffMatrix(actualRows, expectRows, label) {
  if (actualRows.length !== expectRows.length) {
    ok(false, `${label}：尺寸不符 actual=${actualRows.length} expect=${expectRows.length}`)
    return
  }
  for (let r = 0; r < expectRows.length; r++) {
    if (actualRows[r] === expectRows[r]) continue
    let c = 0
    while (c < expectRows[r].length && actualRows[r][c] === expectRows[r][c]) c++
    ok(
      false,
      `${label}：第 ${r} 行第 ${c} 列不同` +
        `\n    期望 ${expectRows[r]}`
        + `\n    实际 ${actualRows[r]}` +
        `\n    (期望位=${expectRows[r][c]} 实际位=${actualRows[r][c]})`
    )
    return
  }
  ok(true, label)
}

for (const f of qrFixtures.auto) {
  const qr = encode(f.text)
  eq(qr.version, f.version, `QR v${f.version} 版本选择（${f.text.slice(0, 24)}…）`)
  eq(qr.mask, f.mask, `QR v${f.version} 掩码选择 = ${f.mask}（${f.text.slice(0, 24)}…）`)
  eq(qr.size, f.rows.length, `QR v${f.version} 矩阵尺寸`)
  diffMatrix(rowsOf(qr), f.rows, `QR v${f.version}/mask${f.mask} 矩阵逐位（${f.text.slice(0, 24)}…）`)
}

// 强制掩码组：把「格式信息摆放」与「掩码选择」两个失败模式隔离开——
// 自动组对不上时先看这里，若强制组全过，说明是罚分算错了而不是铺位错了。
for (const f of qrFixtures.forced) {
  const qr = encode(f.text, { mask: f.mask_requested })
  eq(qr.mask, f.mask_requested, `QR 强制掩码 ${f.mask_requested} 回传`)
  diffMatrix(rowsOf(qr), f.rows, `QR 强制 mask=${f.mask_requested} 矩阵逐位`)
}

ok(encode('abc').size === 21, 'QR 短内容落到 v1（21×21）')
ok(encode('哔哩哔哩').size === 21, 'QR 中文按 UTF-8 计字节')
ok(
  (() => {
    try {
      encode('x'.repeat(3000))
      return false
    } catch (e) {
      return /超出/.test(String(e.message))
    }
  })(),
  'QR 超容量时抛出清晰错误而不是产出坏码'
)

const svg = toSvg(encode('abc'))
ok(svg.startsWith('<svg') && svg.includes('rect'), 'toSvg 产出 SVG')
ok((svg.match(/<rect/g) || []).length > 1, 'toSvg 画出了暗模块（含背景）')

/* -------------------------------------------------- 播放进度外推 */

section('播放进度外推（displayPosition）')

// SW 对 position 落盘节流（PROGRESS_SAVE_INTERVAL = 5s），UI 若直接渲染
// position，进度条就是「5 秒一跳」。displayPosition 拿 positionAt（采样
// 时刻）外推，这里把外推的每条边界钉住。
const T0 = 1700000000000
const playingAt = (over) => ({ position: 100, positionAt: T0, duration: 300, state: 'playing', ...over })

eq(displayPosition(playingAt(), T0), 100, 'playing 刚落盘 → 显示采样值')
eq(displayPosition(playingAt(), T0 + 5000), 105, 'playing 外推 5 秒 → +5')
eq(displayPosition(playingAt(), T0 + 300000), 300, '外推夹在 duration，不会越过曲末（100s+300s → 300s）')
eq(displayPosition(playingAt({ duration: 0 }), T0 + 5000), 105, '时长未知时不夹取')
eq(displayPosition(playingAt({ state: 'paused' }), T0 + 5000), 100, 'paused 冻结不外推')
eq(displayPosition(playingAt({ state: 'loading' }), T0 + 5000), 100, 'loading 不外推')
eq(displayPosition(playingAt({ positionAt: 0 }), T0 + 5000), 100, '无 positionAt（旧数据）退化为原值')
eq(displayPosition(playingAt({ positionAt: T0 + 2000 }), T0), 100, 'positionAt 在未来（时钟偏斜）不倒退')
eq(displayPosition(null), 0, '空 playback → 0')

/* ------------------------------------------------------ 结构与接线自检 */

section('结构与接线（消息名 / 清单 / 页面引用）')

const extRoot = new URL('..', import.meta.url)
const read = (p) => readFileSync(new URL(p, extRoot), 'utf8')

// 消息名对不上不会报错，只会静默返回「未知消息」——这类问题只能靠静态核对抓。
// handler 用的是方法简写 `async key(`，而顶层的都是 `async function name(`，
// 正则靠这个差别把两者分开。
const swSource = read('src/bg/service_worker.js')
const handlerKeys = [...swSource.matchAll(/^\s*async ([a-z][a-zA-Z0-9_]*)\(/gm)].map((m) => m[1])
ok(handlerKeys.length > 10, `service worker 解析出 ${handlerKeys.length} 个 handler`)

function collectUiSends() {
  const keys = new Set()
  for (const file of ['src/ui/popup.js', 'src/ui/player.js', 'src/ui/shared/store.js']) {
    const src = read(file)
    for (const m of src.matchAll(/send\(\s*'([a-z]+)'\s*,\s*'([a-zA-Z_]+)'/g)) {
      keys.add(`${m[1]}_${m[2]}`)
    }
  }
  return [...keys]
}

const uiSends = collectUiSends()
// 元断言：扫描本身失效时（改了调用写法）宁可红，也不要静默地什么都不查
ok(uiSends.length >= 10, `扫描到 ${uiSends.length} 处 UI → SW 调用（少于 10 说明扫描失效）`)
for (const key of uiSends) {
  ok(handlerKeys.includes(key), `UI → SW：${key} 有对应 handler`)
}

// 事件委托的 closest('.类名') 必须与页面真实渲染出的类名对得上。写错不报异常——
// closest 拿不到行就静默 return，整块点击失效。只对 class 属性里的内容做边界匹配：
// 处理器里的 `const row` 同名词不会造成假通过，「list-row 里的 row」也因
// 连字符边界不算数。类名可能写在页面 HTML（静态骨架）或 JS 模板串（动态行）。
const UI_FILES = [
  ['src/ui/popup.js', 'src/ui/popup.html'],
  ['src/ui/player.js', 'src/ui/player.html'],
]
let closestClassSelectors = 0
for (const [jsFile, htmlFile] of UI_FILES) {
  const classAttrs = [...read(jsFile).matchAll(/class="([^"]*)"/g), ...read(htmlFile).matchAll(/class="([^"]*)"/g)]
    .map((m) => m[1])
    .join(' ')
  for (const m of read(jsFile).matchAll(/closest\(\s*'\.([A-Za-z0-9_-]+)'\s*\)/g)) {
    closestClassSelectors++
    const token = new RegExp(`(?<![\\w-])${m[1]}(?![\\w-])`)
    ok(token.test(classAttrs), `${jsFile}：closest('.${m[1]}') 的类名真的会渲染出来`)
  }
}
ok(closestClassSelectors > 0, `扫描到 ${closestClassSelectors} 处 closest('.类') 选择器（为 0 说明扫描失效）`)

// offscreen 通过 requestSW('x') 与 report() 两条路发消息，ns 都是 player
const offSource = read('src/offscreen/audio_host.js')
const offKeys = [...offSource.matchAll(/requestSW\(\s*'([a-zA-Z]+)'/g)].map((m) => `player_${m[1]}`)
offKeys.push('player_state') // report() 走的是字面量 type:'state'
for (const key of new Set(offKeys)) {
  ok(handlerKeys.includes(key), `offscreen → SW：${key} 有对应 handler`)
}

// SW 发给 offscreen 的每种 type 都要有人接，否则指令发出去石沉大海。
// 两条来源都要扫：字面量 `type: 'x'` 和 `sendToOffscreen('x')`——
// 只扫前者会让「改用函数调用」这类重构把检查悄悄变成空转。
const swToOffscreen = [
  ...[...swSource.matchAll(/target: 'offscreen'[\s\S]{0,200}?type: '([a-zA-Z]+)'/g)].map((m) => m[1]),
  ...[...swSource.matchAll(/sendToOffscreen\(\s*'([a-zA-Z]+)'/g)].map((m) => m[1]),
]
const offHandled = [...offSource.matchAll(/msg\.type === '([a-zA-Z]+)'/g)].map((m) => m[1])
// sendToOffscreen(type, payload) 的 type 是调用方传的，单列出来
const offHandledAll = new Set([...offHandled, 'command'])
ok(swToOffscreen.length > 0, `扫描到 ${swToOffscreen.length} 处 SW → offscreen 的 type（为 0 说明扫描失效）`)
for (const t of new Set(swToOffscreen)) {
  ok(offHandledAll.has(t), `SW → offscreen：type='${t}' 有对应分支`)
}
ok(offHandledAll.has('command'), "SW → offscreen：type='command' 有对应分支")

// manifest 声明的每个文件都必须存在（路径写错只会静默加载失败）
const manifest = JSON.parse(read('manifest.json'))
ok(manifest.manifest_version === 3, 'manifest_version = 3')
ok(Array.isArray(manifest.permissions) && manifest.permissions.includes('offscreen'), '声明了 offscreen 权限')
ok(manifest.permissions.includes('declarativeNetRequest'), '声明了 declarativeNetRequest 权限')
ok(manifest.permissions.includes('cookies'), '声明了 cookies 权限')
ok(manifest.permissions.includes('notifications'), '声明了 notifications 权限')
ok(manifest.permissions.includes('storage'), '声明了 storage 权限')
ok(manifest.background && manifest.background.type === 'module', 'service worker 是 module（否则 import 会挂）')

const manifestFiles = [
  manifest.background.service_worker,
  manifest.action.default_popup,
  ...Object.values(manifest.icons),
  ...manifest.declarative_net_request.rule_resources.map((r) => r.path),
]
for (const f of new Set(manifestFiles)) {
  let exists = false
  try {
    read(f)
    exists = true
  } catch {
    exists = false
  }
  ok(exists, `manifest 引用的文件存在：${f}`)
}

// DNR 规则：Referer 改写是整个架构的前提（upos/edge 校验 Referer，缺它必 403）
const rules = JSON.parse(read('rules.json'))
const refererRule = rules.find(
  (r) =>
    r.action &&
    r.action.type === 'modifyHeaders' &&
    (r.action.requestHeaders || []).some((h) => h.header.toLowerCase() === 'referer' && h.operation === 'set')
)
ok(!!refererRule, 'rules.json 里有 set Referer 的改写规则（否则 upos/edge 节点直链必 403）')
ok(
  refererRule &&
    refererRule.condition.requestDomains &&
    refererRule.condition.requestDomains.includes('bilivideo.com'),
  'DNR 覆盖 bilivideo.com（主要 CDN 域）'
)
ok(
  refererRule &&
    (refererRule.condition.resourceTypes || []).includes('media'),
  'DNR 覆盖 resourceTypes=media（<audio> 的请求走这一类）'
)

// HTML 引用的本地资源必须存在
// 用 fileURLToPath + path.relative 解析：URL.pathname 在 Windows 上是 `/D:/...`，
// 手工剥斜杠会得到 `D:/...`，再拼回 URL 时 `D:` 会被当成 scheme。
for (const page of ['src/ui/popup.html', 'src/ui/player.html', 'src/offscreen/offscreen.html']) {
  const html = read(page)
  const refs = [...html.matchAll(/(?:href|src)="([^"#][^"]*)"/g)]
    .map((m) => m[1])
    .filter((u) => !/^(https?:|data:|#)/.test(u))
  for (const ref of refs) {
    const abs = new URL(ref, new URL(page, extRoot))
    const resolved = relative(fileURLToPath(extRoot), fileURLToPath(abs))
    let exists = false
    try {
      read(resolved)
      exists = true
    } catch {
      exists = false
    }
    ok(exists, `${page} 引用的资源存在：${ref}`)
  }
  ok(/<script type="module"/.test(html), `${page} 用 module 方式引入脚本（零构建走 ESM）`)
}

// daisyUI 子集与自定义主题：文件「在」由上面的 HTML 引用检查兜住，
// 但「内容完整」要单独盯——子集被截断或主题变量缺失时，页面会
// 「语法正常、自检不炸、整片 UI 透明」，这种只能靠存在性断言抓。
const daisyCss = read('src/ui/vendor/daisyui.subset.css')
ok(/daisyUI \d+\.\d+\.\d+ 按需子集/.test(daisyCss), 'daisyUI 子集带生成头（由 gen_daisyui_subset.mjs 产出）')
for (const marker of ['.btn{', '.input{', '.select{', '.toggle{', '.range{', '.badge{', '.card{', '.list-row{', '.toast{', '.alert{', '.status{', '.join{']) {
  ok(daisyCss.includes(marker), `daisyUI 子集包含 ${marker}`)
}
ok(!daisyCss.includes('@media (width'), 'daisyUI 子集已剥掉响应式断点复份（体积守门）')

// 令牌层由 md3.tokens.css（角色）+ md3.bridge.css（把角色接到 daisyUI 变量上）
// 两件组成，popup 与播放页都引。少了桥接层，daisyUI 组件会静默拿到 undefined
// （整片透明），所以变量有没有、接哪去都要盯。
const bridgeCss = read('src/ui/md3.bridge.css')
ok(bridgeCss.includes("[data-theme='bilimusic']"), 'md3.bridge.css 覆盖 bilimusic（深色）主题')
ok(bridgeCss.includes("[data-theme='bilimusic-light']"), 'md3.bridge.css 覆盖 bilimusic-light（浅色）主题')
for (const [re, why] of [
  [/--color-primary:\s*var\(--md-primary\)/, 'daisyUI 主色接 MD3 primary'],
  [/--color-base-content:\s*var\(--md-on-surface\)/, 'daisyUI 文字色接 MD3 on-surface'],
  [/--color-error:\s*var\(--md-error\)/, '错误色接 MD3 error'],
]) {
  ok(re.test(bridgeCss), `md3.bridge.css 把 ${why}`)
}
for (const page of ['src/ui/popup.html', 'src/ui/player.html']) {
  const html = read(page)
  ok(/href="\.\/md3\.tokens\.css"/.test(html), `${page} 引入 MD3 令牌`)
}

// Font Awesome 子集（scripts/gen_fontawesome_subset.mjs 产物）：
// 外部源一律由构建脚本拉一次、产物入库，所以这里的重点是：产物完整
// （字体 + 字形都在），且 src/ui 用到的每个图标名都能在子集里找到字形。
const faCss = read('src/ui/vendor/fontawesome.subset.css')
ok(/Font Awesome \d+\.\d+\.\d+ Free 按需子集/.test(faCss), 'FA 子集带生成头（由 gen_fontawesome_subset.mjs 产出）')
ok(faCss.includes("@font-face"), 'FA 子集自带 @font-face（字体随扩展本地加载，不依赖 CDN）')
ok(/src: url\('\.\/webfonts\/fa-solid-900\.woff2'\)/.test(faCss), 'FA 子集引用本地 solid 字体')
ok(/src: url\('\.\/webfonts\/fa-regular-400\.woff2'\)/.test(faCss), 'FA 子集引用本地 regular 字体（.far 轮廓）')
// brands 是第三套字体（码位与 Free 字体不共用）：字形规则齐全也照样会画成方块，
// 少了 @font-face 或字体族规则都只在真机上才看得出来，这里钉死。
ok(/src: url\('\.\/webfonts\/fa-brands-400\.woff2'\)/.test(faCss), 'FA 子集引用本地 brands 字体（.fab / .fa-brands）')
ok(/^\.fab\{font-family:"Font Awesome 5 Brands"\}/m.test(faCss), 'FA 子集声明 .fab 的 brands 字体族')
ok(/\.fa,\.far,\.fas\{font-family:"Font Awesome 5 Free"\}/.test(faCss), 'FA 子集保留字体族声明')
// 基础版式规则（上游 all.min.css 的第一条）：少它图标不会缺字形、不会变方块，
// 只是退回 <i> 的浏览器默认斜体 —— 整屏图标歪着，很容易被当成字体没加载。
ok(
  /^\.fa,[^{]*\{[^}]*font-style:normal/m.test(faCss) && /^\.fa,[^{]*\{[^}]*display:inline-block/m.test(faCss),
  'FA 子集保留基础版式规则（font-style:normal / display:inline-block —— 少了图标就变斜体）'
)
// 上游那条版式规则的选择器里没有 .fa-brands（只补 font-family 别名是不够的）：
// class="fa-brands fa-github" 会退回 <i> 的默认斜体，而字形、字体都齐全，
// 看着像「就那一个图标歪着」，最容易只往字形上查。
const faBrandsAlias = faCss.match(/^\.fa-brands\{[^}]*\}/m)
ok(!!faBrandsAlias, 'FA 子集给 fa-brands 补了别名规则（上游只有 .fab）')
for (const [re, why] of [
  [/font-family:"Font Awesome 5 Brands"/, '字体族'],
  [/font-style:normal/, 'font-style:normal（少了就退回 <i> 的默认斜体）'],
  [/display:inline-block/, 'display:inline-block'],
  [/font-weight:400/, 'font-weight:400'],
]) {
  ok(!!faBrandsAlias && re.test(faBrandsAlias[0]), `.fa-brands 别名规则带 ${why}`)
}
ok(/^\.fa,\.fas\{font-weight:900\}/m.test(faCss) && /\.far\{font-weight:400\}/.test(faCss), 'FA 子集区分 solid/regular 字重（.far 才画轮廓）')
ok(/\.fa-spin\{[^}]*animation:fa-spin/.test(faCss) && /@keyframes fa-spin\{/.test(faCss), 'FA 子集保留 fa-spin 动画与 keyframes（加载中图标在转）')
ok(!/url\((["']?)https?:/.test(faCss), 'FA 子集里没有任何远程 url()')

// 兜底（不只盯 .fa-brands）：src/ui 用到的每个**族前缀**都必须出现在某条
// font-style:normal 的规则里。写了个上游版式规则没覆盖的前缀（如早期只补了
// font-family 的 .fa-brands），表现就是「就那几个图标歪着」，而字形、字体全齐。
const faCovered = new Set()
for (const line of faCss.split('\n')) {
  const open = line.indexOf('{')
  if (open < 0 || !line.slice(open).includes('font-style:normal')) continue
  for (const sel of line.slice(0, open).split(',')) faCovered.add(sel.trim())
}
const faUsedPrefixes = new Set()
for (const f of ['src/ui/popup.html', 'src/ui/player.html', 'src/ui/popup.js', 'src/ui/player.js']) {
  const src = read(f)
  for (const m of src.matchAll(/\b(fa|fas|far|fab|fal|fad|fa-brands)\s+fa-[\w${}]/g)) faUsedPrefixes.add(m[1])
}
ok(faUsedPrefixes.size >= 2, `扫到 ${[...faUsedPrefixes].join(' ')} 几个在用的 FA 族前缀`)
for (const p of faUsedPrefixes) {
  ok(
    faCovered.has(`.${p}`),
    `族前缀 .${p} 在带 font-style:normal 的规则里（不在场 = 该前缀的图标退回 <i> 的默认斜体）`
  )
}

// 字体文件本体必须在盘上且是合法 woff2（只查 CSS 会漏掉「字体被手删」的情况）
for (const f of ['src/ui/vendor/webfonts/fa-solid-900.woff2', 'src/ui/vendor/webfonts/fa-regular-400.woff2', 'src/ui/vendor/webfonts/fa-brands-400.woff2']) {
  let bytes = null
  try {
    bytes = readFileSync(new URL(f, extRoot))
  } catch {
    bytes = null
  }
  ok(!!bytes && bytes.length > 1024, `${f} 存在且非空（${bytes ? bytes.length : 0} B）`)
  ok(!!bytes && bytes.length > 1024 && bytes.readUInt32BE(0) === 0x774f4632, `${f} 是合法 woff2（头 4 字节 wOF2）`)
}

// src/ui 用到的每个 fa-* 图标都必须有字形规则。FA5 的 solid/regular 共用码位，
// 切样式靠字体，所以按名字查 .fa-x:before 即可。
const faNonGlyph = new Set([
  'spin', 'spin-reverse', 'pulse', 'fw', 'ul', 'li', 'border', 'pull-left', 'pull-right',
  'inverse', 'stack', 'swap-opacity', 'rotate-90', 'rotate-180', 'rotate-270', 'rotate-by',
  'flip-horizontal', 'flip-vertical', 'lg', 'xs', 'sm', '1x', '2x', '3x', '4x', '5x', '6x',
])
const usedIcons = new Set()
for (const f of ['src/ui/popup.html', 'src/ui/player.html', 'src/ui/popup.js', 'src/ui/player.js']) {
  const src = read(f)
  // 族前缀里要认 fa-brands：它是 .fab 的别名写法，漏了这条扫描就当没人用过 brands
  for (const m of src.matchAll(/\b(?:fa|fas|far|fab|fal|fad|fa-brands)\s+fa-([a-z][\w-]*)/g)) {
    if (!faNonGlyph.has(m[1])) usedIcons.add(m[1])
  }
  // 模板拼接：<i class="fas fa-${cond ? 'frown' : 'search'}"> —— 名字藏在三元里
  for (const m of src.matchAll(/\b(?:fa|fas|far|fab|fal|fad|fa-brands)\s+fa-\$\{([^}]*)\}/g)) {
    for (const s of m[1].matchAll(/'([a-z][\w-]*)'/g)) usedIcons.add(s[1])
  }
}
ok(usedIcons.size > 20, `扫到 ${usedIcons.size} 个在用的 FA 图标（扫描没漏）`)
const missingIcons = [...usedIcons].filter((n) => !faCss.includes(`.fa-${n}:before`))
ok(
  missingIcons.length === 0,
  `在用的 FA 图标都有字形${missingIcons.length ? `（缺：${missingIcons.join(' ')} —— 跑 gen_fontawesome_subset.mjs 加白名单）` : ''}`
)

// 两个 UI 页面必须真的引入子集与 MD3 令牌层，并预置首帧默认主题（防闪白）
for (const page of ['src/ui/popup.html', 'src/ui/player.html']) {
  const html = read(page)
  ok(/href="\.\/vendor\/daisyui\.subset\.css"/.test(html), `${page} 引入 daisyUI 子集`)
  ok(/href="\.\/vendor\/fontawesome\.subset\.css"/.test(html), `${page} 引入 Font Awesome 子集`)
  ok(/href="\.\/md3\.tokens\.css"/.test(html), `${page} 引入 MD3 色彩令牌`)
  ok(/href="\.\/md3\.bridge\.css"/.test(html), `${page} 引入 MD3 桥接（daisyUI 变量由它提供）`)
  ok(/data-theme="bilimusic"/.test(html), `${page} 预置默认主题（首帧不裸奔）`)
  // 「外部源一律跑构建脚本拉本地」的兜底：页面里不允许再有远程样式 / 脚本 / 图片
  // （普通 <a href="https://…"> 指向 B 站网页不算资源依赖，放行）
  ok(
    !/<link[^>]+href="https?:|<script[^>]+src="https?:|<img[^>]+src="https?:/i.test(html),
    `${page} 不引任何远程资源（外部源一律由 scripts/ 下的构建脚本拉成本地）`
  )
}

// 进度/音量条：daisyUI 的 .progress 套不了 <input type=range>（没有鼠标事件），
// 观感是靠 common.css 把 .range 压成 0.5rem 细条实现的。删掉这段页面照样能用、
// 只是悄悄退回「粗旋钮」的 range 滑块——这种纯观感回归只能靠断言盯。
const commonCss = read('src/ui/shared/common.css')
ok(commonCss.includes('--range-thumb-size: 0.5rem'), 'common.css 把 .range 压成 0.5rem 细条（对齐 .progress 的 height）')
ok(commonCss.includes('--range-thumb: currentColor'), '滑块与填充同色（滑块是 daisyUI 画「已走过的那段」的载体，不能 display:none）')
ok(!/^@layer/m.test(commonCss), 'common.css 不进 @layer（进了就压不过 subset 里 @layer utilities 的 .range）')
for (const page of ['src/ui/popup.html', 'src/ui/player.html']) {
  const html = read(page)
  ok(/href="\.\/shared\/common\.css"/.test(html), `${page} 引入 common.css（进度条观感靠它）`)
  ok(!/range-(xs|sm)/.test(html), `${page} 不挂已失效的 range-xs / range-sm（条高统一由 --range-thumb-size 决定）`)
}

// 存储键与 DEFAULTS 一致：UI 读的键和 SW 写的键必须是同一套
const declaredKeys = [...swSource.matchAll(/^\s{2}(auth|playback|localFav|settings|ui):/gm)].map((m) => m[1])
for (const k of ['auth', 'playback', 'localFav', 'settings', 'ui']) {
  ok(declaredKeys.includes(k), `storage 默认值里有 ${k}`)
}

// 进度链路两端：SW 落盘节流 → positionAt 采样时间戳必须在写入端盖章；
// UI 只读 storage → 必须用 displayPosition 外推 + 本地心跳。拆掉任何一端，
// 进度显示就退回「每 5 秒跳一格」。
ok(/positionAt: 0/.test(swSource), 'SW playback 默认值带 positionAt')
ok(/patch\.positionAt = Date\.now\(\)/.test(swSource), 'SW 给带 position 的 patch 盖采样时间戳')
ok(/position: audio\.currentTime/.test(offSource), "offscreen 的 play 上报带 position（恢复播放时外推基线重新对表）")
for (const page of ['src/ui/popup.js', 'src/ui/player.js']) {
  const src = read(page)
  ok(/displayPosition\(/.test(src), `${page} 进度显示走 displayPosition 外推`)
  ok(/startProgressTicker\(/.test(src), `${page} 有本地进度心跳（不等节流落盘）`)
}

// 播放控制条统一：popup 与 player 的 .npCtl 都是同一套五键、同序
// （循环模式 → 上一首 → 播放/暂停 → 下一首 → 收藏）。
const NP_CTL_TITLES = '循环模式→上一首→播放→下一首→收藏'
for (const page of ['src/ui/popup.html', 'src/ui/player.html']) {
  const html = read(page)
  const start = html.indexOf('class="npCtl"')
  const ctl = start >= 0 ? html.slice(start, html.indexOf('</div>', start)) : ''
  const titles = [...ctl.matchAll(/title="([^"]+)"/g)].map((m) => m[1].replace(/：.*$/, ''))
  ok(
    titles.join('→') === NP_CTL_TITLES,
    `${page} 播放控制条五键同序（${NP_CTL_TITLES}，实到：${titles.join('→') || '没找到 .npCtl'}）`
  )
}

// 装配区绊线：这几条少任何一条，扩展会「语法正确、自检也过、但完全不响应」。
// 这类整块误删在语法检查里是无声的，只能靠存在性断言兜住。
for (const marker of [
  'async function handleMessage',
  'session.restore()',
  'session.watchJar()',
  'qrLogin.subscribe',
  "msg.target !== 'sw'",
  'chrome.runtime.onMessage.addListener',
  'chrome.notifications.onClicked.addListener',
  'async function openPlayerPage',
  'chrome.offscreen.createDocument',
]) {
  ok(swSource.includes(marker), `service worker 装配接线存在：${marker}`)
}
// 消息循环里必须真的把 target 挡在门外，否则各上下文会互相抢答
ok(/target !== 'offscreen'/.test(offSource), 'offscreen 忽略发给别人的消息')
ok(/target !== 'ui'/.test(read('src/ui/shared/store.js')), 'UI 广播订阅只收 target=ui')

// 播放页的 MD3 皮肤（player.css + md3.tokens.css）。改完自检照样绿、页面照样能用，
// 但会悄悄退回「daisyUI 换色」——所以这里钉死几处只能靠观感判断的前提：
// 令牌文件在场且两套 scheme 齐全、daisyUI 变量被改接到 MD3 角色、扁平化开关没被摘掉、
// 伪元素规则没有写进逗号列表（Chrome 会整条丢掉，见下）、滑块填充的两端都在。
const md3Css = read('src/ui/md3.tokens.css')
ok(/MD3 设计令牌（生成物，勿手改）/.test(md3Css), 'md3.tokens.css 带生成头（由 gen_md3_tokens.mjs 产出）')
ok(/gen_md3_tokens\.mjs/.test(md3Css), 'md3.tokens.css 标注了重新生成的方式')
ok(md3Css.includes("[data-theme='bilimusic']") && md3Css.includes("[data-theme='bilimusic-light']"), 'MD3 令牌覆盖深浅两套 scheme')
for (const role of [
  '--md-primary',
  '--md-on-primary',
  '--md-primary-container',
  '--md-on-primary-container',
  '--md-secondary',
  '--md-secondary-container',
  '--md-tertiary',
  '--md-error',
  '--md-error-container',
  '--md-surface',
  '--md-surface-container-low',
  '--md-surface-container-high',
  '--md-surface-container-highest',
  '--md-on-surface',
  '--md-on-surface-variant',
  '--md-outline',
  '--md-outline-variant',
  '--md-inverse-surface',
  '--md-inverse-on-surface',
]) {
  // 两套 scheme 各出现一次才算齐（少一个角色的那套会拿到 undefined → 整块透明）
  const hits = md3Css.split(`${role}:`).length - 1
  ok(hits >= 2, `MD3 令牌有 ${role}（深浅两套各一份，实到 ${hits}）`)
}

const playerCss = read('src/ui/player.css')
const popupCss = read('src/ui/popup.css')
// 桥接层统一在 md3.bridge.css（上面查过），页面 css 里不该再出现一份 --color-* 改接：
// 两页各写一份就会漂
for (const [file, css] of [
  ['player.css', playerCss],
  ['popup.css', popupCss],
]) {
  ok(!/--color-primary:\s*var\(/.test(css), `${file} 不重复声明 daisyUI 变量（桥接统一在 md3.bridge.css）`)
}
// 扁平化三件套：留着任何一条都会退回 daisyUI 的描边 + 内高光 + 噪点观感
for (const [re, why] of [
  [/--depth:\s*0/, '--depth: 0（去掉按钮内高光与立面阴影）'],
  [/--noise:\s*0/, '--noise: 0（去掉噪点纹理）'],
  [/--border:\s*0/, '--border: 0（按钮默认无描边，需要描边的组件自己写）'],
]) {
  ok(re.test(bridgeCss), `md3.bridge.css 保留 MD3 扁平化开关 ${why}`)
}
for (const marker of ['.navBadge', '.chips .btn.btn-primary', '.segBar', '.toggle:checked', '#toast .alert']) {
  ok(playerCss.includes(marker), `player.css 有 MD3 组件覆盖：${marker}`)
}
// popup 的 MD3 皮肤：改完自检照样绿、页面照样能用，只是悄悄退回旧观感，所以钉几处硬前提
for (const [re, why] of [
  [/background:\s*var\(--md-surface-container-high\)/, '「现在播放」卡片用 MD3 的 surface-container-high'],
  [/--btn-bg:\s*var\(--md-primary-container\)/, '主播放键用 MD3 FAB 取色（primary-container）'],
  [/border-radius:\s*8px/, '队列行取 MD3 shape scale 的 8dp'],
  [/color-mix\(in oklab, var\(--md-on-surface\) var\(--md-state-hover\)/, '状态层是叠在 on-surface 上的半透明层（不是实心换色）'],
]) {
  ok(re.test(popupCss), `popup.css 有 MD3 覆盖：${why}`)
}
for (const [re, why] of [
  [/--md-on-surface-variant/, '次级文字色'],
  [/--md-secondary-container/, '当前播放行'],
]) {
  ok(re.test(popupCss), `popup.css 用 MD3 角色上色：${why}`)
}

// 图标：CSS 里画出来的对勾走内联 SVG mask，**不许用 FA 码位**（\f00c 之类）。
// 字体子集只保留白名单字形，码位现在能画出来只是因为 woff2 还没被裁，
// 一旦裁字形就是静默空白——CSS 语法、自检、字形反查全都看不出来。
// （变量与消费者现在分处两个文件：定义在桥接层，mask 规则在播放页。）
ok(/--md-icon-check:\s*url\("data:image\/svg\+xml/.test(bridgeCss), 'MD3 对勾是内联 SVG（不依赖 FA 字形）')
ok(/mask-image:\s*var\(--md-icon-check\)/.test(playerCss), 'player.css 用 mask 给对勾上色（跟着 currentColor）')
const faCodepoints = [...playerCss.matchAll(/content:\s*['"]\\f[0-9a-fA-F]{3}/g)].map((m) => m[0])
ok(
  faCodepoints.length === 0,
  `player.css 不靠 FA 码位画图标${faCodepoints.length ? `（还在用：${faCodepoints.join(' ')}）` : ''}`
)

// Chrome 对选择器列表是「一个不认识就整条规则作废」：`::-webkit-slider-thumb, ::-moz-range-thumb`
// 这种写法在 Chrome 里会被**静默丢掉**（元素级变量还生效，所以看着像「变量改了没反应」）。
// daisyUI 子集自己就是拆开写的，本仓库的 UI 样式也必须拆开。
for (const file of ['src/ui/shared/common.css', 'src/ui/md3.bridge.css', 'src/ui/player.css', 'src/ui/popup.css']) {
  // 先剥注释：注释里正当地提到这两个前缀（说明为什么必须拆开），不能算违规
  const css = read(file).replace(/\/\*[\s\S]*?\*\//g, '')
  const bad = []
  for (const m of css.matchAll(/\{/g)) {
    const before = css.slice(0, m.index)
    const sel = before.slice(before.lastIndexOf('}') + 1).trim()
    if (sel && /-webkit-/.test(sel) && /-moz-/.test(sel)) bad.push(sel)
  }
  ok(bad.length === 0, `${file} 没有把 -webkit- / -moz- 伪元素写进同一个选择器列表${bad.length ? `（违规：${bad[0].slice(0, 60)}）` : ''}`)
}

// 滑块：MD3 的填充画在轨道渐变上（--pos，两页都是），daisyUI 那套「挂在滑块上的阴影球」
// 必须清零，否则 .range 把 overflow 放开之后那颗 100cqw 的阴影会糊满整行。
for (const [file, css] of [
  ['player.css', playerCss],
  ['popup.css', popupCss],
]) {
  ok(/linear-gradient\(/.test(css) && /var\(--pos/.test(css), `${file} 的滑块填充走轨道渐变 + --pos`)
  for (const v of ['--range-fill-x', '--range-fill-y', '--range-fill-spread']) {
    ok(new RegExp(`${v}:\\s*0`).test(css), `${file} 清掉 daisyUI 的滑块阴影填充 ${v}`)
  }
}
const playerJs = read('src/ui/player.js')
ok(/function setRangePos/.test(playerJs), 'player.js 有 setRangePos（写 --pos）')
ok(/setRangePos\(\$\('npSeek'\)/.test(playerJs) && /setRangePos\(\$\('volume'\)/.test(playerJs), 'player.js 给进度与音量滑块都同步 --pos')
// popup 的进度 / 音量也是同一套 --pos 轨道渐变：少了这几处，条会一直是空轨道（填充不动）
const popupJs = read('src/ui/popup.js')
ok(/function setRangePos/.test(popupJs), 'popup.js 有 setRangePos（写 --pos）')
ok(
  /setRangePos\(\$\('seek'\)/.test(popupJs) && /setRangePos\(\$\('volume'\)/.test(popupJs),
  'popup.js 给进度与音量滑块都同步 --pos'
)

/* ------------------------------------------------------------------ 汇总 */

console.log('')
if (fail === 0) {
  console.log(`  ✔ 全部通过：${pass} 项断言`)
  process.exit(0)
}
console.log(`  ✘ 失败 ${fail} / 通过 ${pass}`)
for (const f of failures) console.log(`\n  ${f}`)
process.exit(1)
