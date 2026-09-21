import { CONFIG, PLAY } from '../common/config'
import { request, buildQuery } from './api'
import {
  parseRecommendItem,
  parsePopularItem,
  cdnNodeClass,
  isDirectLinkCapable,
  flattenAudioTiers,
  filterFreshUrls,
} from '../common/parse'
import { deriveMixinKey, signWbi, signApp } from './crypto'
import { getCookieHeader, getMid } from './session'

const API = CONFIG.BILI_API
const PASSPORT = CONFIG.BILI_PASSPORT

/* ------------------------------ 基础请求 ------------------------------ */

function baseHeaders(extra) {
  return {
    Referer: CONFIG.BILI_REFERER,
    Origin: CONFIG.BILI_ORIGIN,
    ...(extra || {}),
  }
}

/**
 * 主站 GET，默认带上登录 Cookie（未登录时自动省略）
 * @returns {Promise<{httpCode:number, body:any, headers:object}>}
 */
function biliGet(path, params = {}, opts = {}) {
  const query = buildQuery(params)
  const url = `${API}${path}${query ? (path.indexOf('?') >= 0 ? '&' : '?') + query : ''}`
  return request({
    url,
    method: 'GET',
    responseType: 'json',
    withCookie: opts.withCookie !== false,
    headers: baseHeaders(opts.headers),
  })
}

/**
 * 从信封中取业务数据，业务 code 非 0 时抛错
 */
function unwrap(res, action) {
  const body = res && res.body
  if (!body) throw new Error(`${action}：响应为空`)
  if (body.code !== 0) {
    throw new Error(`${action}失败：code=${body.code} ${body.message || ''}`.trim())
  }
  return body.data
}

/* ------------------------------ WBI 签名 ------------------------------ */

let wbiCache = { mixinKey: '', ts: 0 }

function extractWbiKey(url) {
  const file = String(url || '').split('/').pop()
  return file.split('.')[0]
}

/**
 * 取 WBI 实时口令并派生 mixin_key（带内存缓存，官方每日更替）
 */
export async function getMixinKey(force) {
  if (!force && wbiCache.mixinKey && Date.now() - wbiCache.ts < CONFIG.WBI_CACHE_TTL) {
    return wbiCache.mixinKey
  }
  const res = await biliGet('/x/web-interface/nav')
  const data = res.body && res.body.data
  if (!data || !data.wbi_img) {
    throw new Error('获取 WBI 口令失败：nav 未返回 wbi_img')
  }
  const imgKey = extractWbiKey(data.wbi_img.img_url)
  const subKey = extractWbiKey(data.wbi_img.sub_url)
  const mixinKey = deriveMixinKey(imgKey, subKey)
  wbiCache = { mixinKey, ts: Date.now() }
  console.log('[Bili] WBI mixin_key 已更新')
  return mixinKey
}

/**
 * 需要 WBI 签名的 GET
 */
async function signedGet(path, params = {}, opts = {}) {
  const mixinKey = await getMixinKey()
  const signed = signWbi(params, mixinKey)
  return biliGet(path, signed, opts)
}

/* --------------------- TV 端扫码登录（唯一路径） --------------------- */

/**
 * TV 端签名请求（APP 签名，非 WBI）
 */
function tvPost(path, params) {
  const signed = signApp(params, CONFIG.LOGIN.TV_APPKEY, CONFIG.LOGIN.TV_APPSEC)
  return request({
    url: `${PASSPORT}${path}`,
    method: 'POST',
    data: buildQuery(signed),
    responseType: 'json',
    headers: baseHeaders({ 'Content-Type': 'application/x-www-form-urlencoded' }),
  })
}

/**
 * 申请 TV 端登录二维码
 *
 * 扫码登录只有这一条路：登录票据 Cookie 直接在响应体 cookie_info 里，不碰响应头。
 *
 * @returns {Promise<{url:string, authCode:string}>}
 */
export async function tvGenerateQrCode() {
  const res = await tvPost('/x/passport-tv-login/qrcode/auth_code', {
    local_id: CONFIG.LOGIN.TV_LOCAL_ID,
    ts: Math.floor(Date.now() / 1000),
  })
  const body = res.body || {}
  if (body.code !== 0 || !body.data) {
    throw new Error(`申请二维码失败：code=${body.code} ${body.message || ''}`.trim())
  }
  const { url, auth_code: authCode } = body.data
  if (!url || !authCode) {
    throw new Error('申请二维码失败：返回缺少 url/auth_code')
  }
  console.log('[Bili] TV 端二维码已申请，auth_code =', authCode)
  return { url, authCode }
}

/**
 * 轮询 TV 端扫码状态
 * 状态码在**根级 code**（不是 data.code）：
 *   0 成功 | 86038 已失效 | 86039/86090 已扫码未确认
 * 成功时 data.cookie_info.cookies[] 直接给出登录票据
 */
export function tvPollQrCode(authCode) {
  return tvPost('/x/passport-tv-login/qrcode/poll', {
    auth_code: authCode,
    local_id: CONFIG.LOGIN.TV_LOCAL_ID,
    ts: Math.floor(Date.now() / 1000),
  })
}

/**
 * 拉取当前登录用户信息（同时会刷新 WBI 口令）
 */
export async function getUserInfo() {
  const res = await biliGet('/x/web-interface/nav')
  const body = res.body || {}
  const data = body.data || {}
  if (data.wbi_img) {
    const imgKey = extractWbiKey(data.wbi_img.img_url)
    const subKey = extractWbiKey(data.wbi_img.sub_url)
    wbiCache = { mixinKey: deriveMixinKey(imgKey, subKey), ts: Date.now() }
  }
  if (!data.isLogin) {
    throw new Error(`未登录：code=${body.code} ${body.message || ''}`.trim())
  }
  return {
    mid: data.mid,
    uname: data.uname,
    face: data.face,
  }
}

/* ------------------------------ 收藏夹 ------------------------------ */

/**
 * 获取指定用户创建的所有收藏夹
 */
export async function getCreatedFavFolders(mid) {
  const uid = mid || getMid()
  if (!uid) throw new Error('缺少 mid，无法获取收藏夹')
  const res = await biliGet('/x/v3/fav/folder/created/list-all', { up_mid: uid })
  const data = unwrap(res, '获取收藏夹')
  const list = (data && data.list) || []
  return list.map((f) => ({
    mediaId: f.id,
    title: f.title,
    count: f.media_count,
  }))
}

/**
 * 获取收藏夹内容明细
 * @param {number|string} mediaId
 * @param {number} pn 页码（从 1 开始）
 */
export async function getFavResources(mediaId, pn = 1, ps = CONFIG.FAV_PAGE_SIZE) {
  const res = await biliGet('/x/v3/fav/resource/list', {
    media_id: mediaId,
    pn,
    ps,
    platform: 'web',
  })
  const data = unwrap(res, '获取收藏内容')
  const medias = (data && data.medias) || []
  return {
    tracks: medias
      .filter((m) => m && m.attr !== 1) // attr=1 为失效稿件
      .map(toTrack),
    hasMore: !!(data && data.has_more),
    total: (data && data.info && data.info.media_count) || 0,
  }
}

/**
 * 把收藏项规范化为播放队列的曲目对象
 */
export function toTrack(m) {
  const upper = m.upper || {}
  return {
    id: m.id, // avid
    bvid: m.bvid || m.bv_id || '',
    cid: m.cid || 0, // 取流时才解析
    title: m.title || '未知',
    artist: upper.name || '未知',
    cover: m.cover || '',
    duration: m.duration || 0,
    type: m.type,
  }
}

/* ------------------------------ 官方推荐 ------------------------------ */

/**
 * 官方推荐流（B 站「推荐」tab 的数据源）
 *
 * 两个接口：
 *  - 老版 `/x/web-interface/index/top/feed/rcmd`：主路径。虽带 items 但不签名也能用，
 *    未登录约 12 条/页，条目直接带 bvid/cid（取流无需再查稿件信息）；
 *    分页靠 fresh_idx 递增，接口没有 has_more —— 某页返回 0 条即到底。
 *  - `/x/web-interface/popular`（综合热门）：rcmd 整页失败时的兜底（部分网络环境下
 *    推荐流会撞风控），pn/ps 分页，`no_more` 判到底。带 redirect_url 的 PGC 条目
 *    在解析层直接丢弃（见 common/parse.js 的 parsePopularItem）。
 *
 * 广告/直播等非稿件条目在 parseRecommendItem 里过滤，这里只拿得到可播放曲目。
 *
 * @param {number} [freshIdx] 推荐流翻页游标，从 1 开始；popular 兜底时用作页码 pn
 * @param {string} [force] 'rcmd' 优先；'popular' 直接走热门
 * @returns {Promise<{tracks:Array, hasMore:boolean, nextIdx:number, source:string}>}
 */
export async function getRecommendResources(freshIdx = 1, force) {
  const ps = CONFIG.RECOMMEND_PAGE_SIZE

  if (force !== 'popular') {
    try {
      const res = await biliGet('/x/web-interface/index/top/feed/rcmd', {
        ps,
        fresh_idx: freshIdx,
        fresh_idx_1h: freshIdx,
      })
      const data = unwrap(res, '获取推荐')
      const items = (data && data.item) || []
      return {
        tracks: items.map(parseRecommendItem).filter(Boolean),
        // rcmd 没有 has_more：本页 0 条视为到底（解析层还会再滤掉广告）
        hasMore: items.length > 0,
        nextIdx: freshIdx + 1,
        source: 'rcmd',
      }
    } catch (e) {
      if (force === 'rcmd') throw e // 调用方显式只要 rcmd 时不兜底
      console.warn('[Bili] 推荐流失败，改走综合热门兜底:', e.message || e)
    }
  }

  const res = await biliGet('/x/web-interface/popular', { ps, pn: freshIdx })
  const data = unwrap(res, '获取热门')
  const list = (data && data.list) || []
  return {
    tracks: list.map(parsePopularItem).filter(Boolean),
    hasMore: !(data && data.no_more),
    nextIdx: freshIdx + 1,
    source: 'popular',
  }
}

/* ------------------------------ 取流 ------------------------------ */

/**
 * 获取稿件信息（含 cid）。实测该接口不签名也可用。
 */
export async function getVideoInfo(bvid) {
  const res = await biliGet('/x/web-interface/view', { bvid })
  const data = unwrap(res, '获取稿件信息')
  if (!data || !data.cid) throw new Error('获取稿件信息失败：缺少 cid')
  return {
    bvid,
    cid: data.cid,
    title: data.title,
    duration: data.duration,
    cover: data.pic,
    owner: data.owner && data.owner.name,
  }
}

/**
 * 取音频流地址（DASH 音轨，**所有音质档的地址拍平成一个候选列表**）
 *
 * 注意：返回的是 CDN 直链，带防盗链签名与时效（`deadline`，实测 120 分钟）；
 * `@system.audio` 的 src 不支持自定义请求头，所以「哪些地址能直链播」由节点类决定
 * （mcdn 能，upos/edge 不能 —— 见 common/parse.js 的 cdnNodeClass）。
 *
 * 为什么要把所有音质档拍平：
 * 防盗链是按**节点类**生效的，而同一条流的 `backupUrl[]` 常常整档都是 upos
 * ——「带宽最高那档全是 upos」的稿件，那条唯一的 mcdn 地址可能躺在**别的档**里；
 * 只取最高档的话它永远轮不到，稿件就「固定播不了」（三档全 upos 的稿件则只能落盘）。
 * 档间顺序仍是带宽从高到低（音质优先），档内仍是 baseUrl → backupUrl。
 *
 * 联调提示：若机型播不动 .m4s 音轨，把 config.js 的 PLAY.FORCE_DURL 置为 true，
 * 会改走 fnval=0 的 MP4 合流（音轨可正常出声）。
 *
 * @returns {Promise<{url:string, candidates:string[]}>}
 */
export async function getAudioStreamInfo(bvid, cid) {
  const fnval = PLAY.FORCE_DURL ? PLAY.FNVAL_MP4 : PLAY.FNVAL_DASH
  const params = {
    bvid,
    cid,
    fnval,
    fnver: 0,
    fourk: 1,
    platform: 'pc',
    high_quality: 1,
  }
  // MP4 模式需要 qn 指定清晰度（不影响音频）
  if (PLAY.FORCE_DURL) params.qn = 32

  const res = await signedGet('/x/player/wbi/playurl', params)
  const data = unwrap(res, '取流')

  if (!PLAY.FORCE_DURL) {
    const dash = data && data.dash
    if (dash && Array.isArray(dash.audio) && dash.audio.length) {
      // 跨档拍平（档从高到低、档内 baseUrl → backupUrl、去重）—— 规则与理由见
      // common/parse.js 的 flattenAudioTiers：只取最高档会让别的档里那条 mcdn 永远轮不到。
      const list = flattenAudioTiers(dash.audio)
      if (list.length) {
        const shape = dash.audio
          .slice()
          .sort((a, b) => (b.bandwidth || 0) - (a.bandwidth || 0))
          .map((t) => 'id=' + t.id + '[' + collectCandidates(t).map((u) => cdnNodeClass(u)).join('/') + ']')
        console.log(
          '[Bili] DASH 候选地址', list.length, '条（档从高到低）:',
          shape.join(' '),
          '| 可直链播的（mcdn）', list.filter((u) => isDirectLinkCapable(u)).length, '条'
        )
        return { url: list[0], candidates: list }
      }
    }
  }

  // 回退：少数稿件没有独立音轨，用合流文件（音轨可正常播放）
  if (data && Array.isArray(data.durl) && data.durl.length) {
    console.warn('[Bili] 回退 durl 合流文件')
    const seg = data.durl[0]
    const list = [seg.url].concat(seg.backup_url || seg.backupUrl || []).filter(Boolean)
    const uniq = dedupe(list)
    return { url: uniq[0], candidates: uniq }
  }

  throw new Error('接口未返回可用音频流')
}

/**
 * 兼容入口：只要一个地址的调用方（诊断脚本等）拿第一条
 */
export async function getAudioStream(bvid, cid) {
  const info = await getAudioStreamInfo(bvid, cid)
  return info.url
}

/** 主地址 + backupUrl/backup_url，去重但保持顺序（主地址必须排第一） */
function collectCandidates(stream) {
  const primary = stream.baseUrl || stream.base_url || ''
  const backups = stream.backupUrl || stream.backup_url || []
  return dedupe([primary].concat(backups).filter(Boolean))
}

function dedupe(list) {
  const seen = {}
  const out = []
  for (let i = 0; i < list.length; i++) {
    const u = list[i]
    if (!u || seen[u]) continue
    seen[u] = true
    out.push(u)
  }
  return out
}

/**
 * 播放服务的取流解析器：注入给 playerService
 *
 * @param {object} track
 * @param {object} [opts]
 * @param {boolean} [opts.force] 无视曲目上缓存的地址，重新打一次 playurl
 *        （直链与落盘都失败之后必须用这个：死链重试多少次都还是死链）
 * @returns {Promise<string>} 首选地址（其余候选挂在 track.streams 上）
 */
export async function resolveTrackUrl(track, opts) {
  const urls = await resolveTrackUrls(track, opts)
  return urls[0]
}

/**
 * 取候选地址列表（直链兜底与落盘下载共用）。
 *
 * 曲目对象上的 `track.streams` 就是缓存，但它**带时效**：B 站 CDN 地址的 `deadline`
 * 实测只有 120 分钟，而队列里的曲目对象会活一整个会话（预取还更早把地址取回来放着）。
 * 拿一个过期地址去请求，CDN 回的正是 403 —— 报错文案是「防盗链或直链已过期」，
 * 而两者处置完全相反（换节点 vs 重新取流），所以这里必须主动把过期的滤掉。
 *
 * @param {object} track
 * @param {object} [opts] force / marginSec（默认留 5 分钟余量）
 * @returns {Promise<string[]>}
 */
export async function resolveTrackUrls(track, opts) {
  if (!track) throw new Error('曲目为空')
  const force = !!(opts && opts.force)
  const marginSec = opts && typeof opts.marginSec === 'number' ? opts.marginSec : undefined

  if (track.playUrl) return [track.playUrl]

  if (!force && Array.isArray(track.streams) && track.streams.length) {
    const fresh = filterFreshUrls(track.streams, 0, marginSec)
    if (fresh.length) {
      // 缓存里混着过期地址：顺手把曲目上那份也换掉，别让下一个人再拿到死链
      if (fresh.length !== track.streams.length) {
        console.warn('[Bili] 取流缓存里有', track.streams.length - fresh.length, '条已过期，已剔除')
        track.streams = fresh
      }
      return fresh
    }
    if (track.streams.length) console.warn('[Bili] 取流缓存全部过期，重新取流')
  }

  if (!track.bvid) throw new Error('曲目缺少 bvid，无法取流')

  let cid = track.cid
  if (!cid) {
    const info = await getVideoInfo(track.bvid)
    cid = info.cid
    track.cid = cid
    if (info.duration) track.duration = info.duration
    if (!track.cover && info.cover) track.cover = info.cover
  }
  const { candidates } = await getAudioStreamInfo(track.bvid, cid)
  if (!candidates || !candidates.length) throw new Error('取流后仍未拿到可用地址')
  // 候选地址挂在曲目上：直链失败要换下一条、落盘要逐条试，都能就地取到
  track.streams = candidates
  return candidates
}

export default {
  getMixinKey,
  tvGenerateQrCode,
  tvPollQrCode,
  getUserInfo,
  getCreatedFavFolders,
  getFavResources,
  getRecommendResources,
  getVideoInfo,
  getAudioStream,
  getAudioStreamInfo,
  resolveTrackUrl,
  resolveTrackUrls,
  toTrack,
}
