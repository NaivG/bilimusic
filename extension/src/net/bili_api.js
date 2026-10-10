/**
 * B 站接口封装
 *
 * 只做「调哪个接口 + 怎么解析」，信封校验与签名重试都在 net/request.js。
 *
 * 搜索不主动签名：撞上 -352/-412/412 时由 request.js 自动刷口令补签重试一次，
 * 这条路是自愈的；而一上来就签若口令拿不到会让搜索彻底不可用。
 */

import { CONFIG, QUALITY_FALLBACK, AUDIO_QUALITY } from '../core/config.js'
import { classifyQuery, parseSearchResults, emptySearchResponse, COVER_THUMB_SUFFIX } from '../core/search.js'
import { asStreamList, collectCandidates, uniq } from '../core/cdn.js'
import { signApp } from '../core/crypto.js'
import { getJson, getData, send, postForm } from './request.js'
import { requestOnce, biliHeaders } from './http.js'
import { getMid } from '../auth/session.js'

/* ------------------------------------------------------------ 用户资料 */

/**
 * 拉当前登录用户信息（顺带刷新 WBI 口令）。
 * 未登录时 nav 返回 code=-101，这里当作「未登录」而不是异常。
 *
 * @returns {Promise<{isLogin:boolean, mid:number, uname:string, face:string}>}
 */
export async function getUserInfo() {
  try {
    const json = await getJson('/x/web-interface/nav')
    const data = json.data || {}
    return {
      isLogin: !!(data.isLogin || data.is_login),
      mid: Number(data.mid) || 0,
      uname: data.uname || '',
      face: data.face || '',
    }
  } catch (e) {
    if (e && e.isNotLogin) {
      return { isLogin: false, mid: 0, uname: '', face: '' }
    }
    throw e
  }
}

/* ---------------------------------------------------------------- 稿件详情 */

/**
 * 稿件详情（拿 cid / 封面 / UP 主 / 分 P）。
 *
 * @param {string} bvid
 * @returns {Promise<object|null>} 解析失败或稿件不存在返回 null
 */
export async function getVideoInfo(bvid) {
  try {
    const data = await getData('/x/web-interface/view', { params: { bvid } })
    if (!data || typeof data !== 'object') return null
    const owner = data.owner || {}
    const pages = (Array.isArray(data.pages) ? data.pages : []).map((p) => ({
      cid: String(p.cid || ''),
      part: p.part || '',
      duration: Number(p.duration) || 0,
    }))
    return {
      bvid: data.bvid || bvid,
      aid: Number(data.aid) || 0,
      title: data.title || '',
      cover: data.pic || '',
      artist: owner.name || '未知作者',
      duration: Number(data.duration) || 0,
      cid: pages[0] ? pages[0].cid : String(data.cid || ''),
      pages,
    }
  } catch (e) {
    console.warn('[BiliAPI] getVideoInfo 失败', bvid, e && e.message)
    return null
  }
}

/* ------------------------------------------------------------------- 搜索 */

/**
 * 搜索入口：BV/AV 号直查稿件，其余走关键词。
 *
 * @param {string} query 用户输入
 * @param {object} [opts] {page} 关键词搜索的页码（BV/AV 直查不分页）
 * @returns {Promise<object>} SearchResponse 形状（见 core/search.js）
 */
export async function search(query, opts = {}) {
  const q = classifyQuery(query)
  if (!q.value) return emptySearchResponse(query)

  if (q.kind === 'bvid') {
    const info = await getVideoInfo(q.value)
    if (!info) return emptySearchResponse(q.value)
    return {
      keyword: q.value,
      results: [
        {
          id: info.bvid,
          title: info.title,
          subtitle: info.artist,
          coverUrl: info.cover ? info.cover + COVER_THUMB_SUFFIX : '',
          type: 'video',
          bvid: info.bvid,
          playable: true,
        },
      ],
      hasMore: false,
      page: 1,
      totalResults: 1,
    }
  }

  try {
    const json = await getJson('/x/web-interface/search/all/v2', {
      params: { keyword: q.value, page: opts.page || 1 },
    })
    return parseSearchResults(json.data, query)
  } catch (e) {
    if (e && e.isNotLogin) console.warn('[BiliAPI] 搜索需要登录')
    else console.warn('[BiliAPI] 搜索失败', e && e.message)
    return emptySearchResponse(query)
  }
}

/* ------------------------------------------------------------------- 取流 */

/**
 * 从 DASH 流候选里挑一档。
 *
 * 先精确匹配请求档，匹配不到按 192K > 132K > 64K 从高到低回退。
 * 注：dash.audio 的数组顺序不保证，不能按下标取。
 *
 * @param {object[]} candidates
 * @param {string} qualityId
 * @returns {object|null}
 */
function pickAudioStream(candidates, qualityId) {
  for (const quality of [qualityId, ...QUALITY_FALLBACK]) {
    for (const c of candidates) {
      if (String(c.id) === quality) {
        const url = c.baseUrl || c.base_url || ''
        if (url) return c
      }
    }
  }
  return null
}

/**
 * 取 DASH 音频流信息。
 *
 * fnval=4048 一次性返回全部 DASH 流（含 Hi-Res/杜比位，无大会员时字段为空）。
 * 标准三档在 `dash.audio`；Hi-Res 单流在 `dash.flac`、杜比在 `dash.dolby`，
 * 三者都要收进来——只看 audio 会让大会员用户拿不到无损。
 *
 * @param {string} bvid
 * @param {string} cid
 * @param {string} [qualityId]
 * @returns {Promise<{url:string, candidates:string[], qualityId:string}>}
 */
export async function getAudioStreamInfo(bvid, cid, qualityId = AUDIO_QUALITY.HIGH) {
  const data = await getData('/x/player/playurl', {
    params: { bvid, cid, fnval: '4048' },
  })

  const dash = data && data.dash
  if (dash && typeof dash === 'object') {
    const flac = dash.flac
    const dolby = dash.dolby
    const candidates = [
      ...asStreamList(dash.audio),
      ...asStreamList(flac && typeof flac === 'object' ? flac.dash || flac.audio : null),
      ...asStreamList(dolby && typeof dolby === 'object' ? dolby.audio || dolby.dash : null),
    ]
    const picked = pickAudioStream(candidates, qualityId)
    if (picked) {
      const urls = uniq(collectCandidates(picked))
      return { url: urls[0], candidates: urls, qualityId: String(picked.id) }
    }
  }

  // 回退：少数稿件没有独立音轨，只有 durl 合流文件（音轨可正常出声）
  if (data && Array.isArray(data.durl) && data.durl.length) {
    const seg = data.durl[0]
    const urls = uniq([seg.url].concat(seg.backup_url || seg.backupUrl || []).filter(Boolean))
    if (urls.length) return { url: urls[0], candidates: urls, qualityId: 'durl' }
  }

  throw new Error('接口未返回可用音频流')
}

/**
 * 解析一条曲目的可播放地址。
 *
 * 队列曲目上的 `track.streams` 是取流缓存，带时效：B 站 CDN 地址的 `deadline`
 * 实测只有 120 分钟，而队列里的曲目会活一整个会话。这里主动把过期的滤掉，
 * 全都过期就重新取流。
 *
 * @param {object} track {bvid, cid?, title, artist, cover, duration?}
 * @param {object} [opts] {force, qualityId, marginSec}
 * @returns {Promise<{url:string, candidates:string[], qualityId:string}>}
 */
export async function resolveStream(track, opts = {}) {
  if (!track || !track.bvid) throw new Error('曲目缺少 bvid，无法取流')
  const qualityId = opts.qualityId || AUDIO_QUALITY.HIGH

  if (!opts.force && Array.isArray(track.streams) && track.streams.length) {
    // filterFreshUrls 只滤过期不去重；候选本身已去重过
    const fresh = track.streams.filter((u) => {
      const m = String(u).match(/[?&]deadline=(\d{6,})/)
      if (!m) return true
      return Number(m[1]) * 1000 - Date.now() > (opts.marginSec ?? CONFIG.URL_TTL_MARGIN) * 1000
    })
    if (fresh.length) {
      track.streams = fresh
      return { url: fresh[0], candidates: fresh, qualityId: track.qualityId || qualityId }
    }
    // 全部过期 → 重新取流，别拿死链再试一次
  }

  let cid = track.cid
  if (!cid) {
    const info = await getVideoInfo(track.bvid)
    if (!info || !info.cid) throw new Error('拿不到稿件 cid，无法取流')
    cid = info.cid
    track.cid = cid
    if (!track.duration && info.duration) track.duration = info.duration
    if (!track.cover && info.cover) track.cover = info.cover
    if (!track.artist && info.artist) track.artist = info.artist
  }

  const stream = await getAudioStreamInfo(track.bvid, cid, qualityId)
  track.streams = stream.candidates
  track.qualityId = stream.qualityId
  return stream
}

/* --------------------------------------------------------------- 收藏夹 */

/**
 * 指定用户创建的所有收藏夹。
 *
 * @param {number} [mid] 缺省用当前登录用户
 * @returns {Promise<Array<{mediaId:number, title:string, count:number, cover:string}>>}
 */
export async function getCreatedFavFolders(mid) {
  const uid = mid || getMid()
  if (!uid) throw new Error('未登录，无法获取收藏夹')
  const data = await getData('/x/v3/fav/folder/created/list-all', { params: { up_mid: uid } })
  const list = data && Array.isArray(data.list) ? data.list : []
  return list.map((f) => ({
    mediaId: Number(f.id),
    title: f.title || '默认收藏夹',
    count: Number(f.media_count) || 0,
    cover: f.cover || '',
  }))
}

/**
 * 收藏夹内容（分页）。
 *
 * @param {number} mediaId
 * @param {number} [pn]
 * @param {number} [ps]
 * @returns {Promise<{tracks:Array, hasMore:boolean, total:number}>}
 */
export async function getFavResources(mediaId, pn = 1, ps = CONFIG.FAV_PAGE_SIZE) {
  const data = await getData('/x/v3/fav/resource/list', {
    params: { media_id: mediaId, pn, ps, platform: 'web' },
  })
  const medias = data && Array.isArray(data.medias) ? data.medias : []
  return {
    tracks: medias
      // attr=1 为失效稿件
      .filter((m) => m && m.attr !== 1)
      .map(toTrack),
    hasMore: !!(data && data.has_more),
    total: (data && data.info && data.info.media_count) || 0,
  }
}

/**
 * 收藏夹条目 → 播放队列的曲目对象。
 * @param {object} m
 * @returns {object}
 */
export function toTrack(m) {
  const upper = m.upper || {}
  return {
    bvid: m.bvid || m.bv_id || '',
    id: Number(m.id) || 0,
    cid: Number(m.cid) || 0,
    title: m.title || '未知',
    artist: upper.name || '未知',
    cover: m.cover || '',
    duration: Number(m.duration) || 0,
  }
}

/**
 * 加入 / 取消收藏某个稿件到默认收藏夹。
 *
 * 需要 csrf = Cookie 里的 bili_jct；未登录时接口自己会回 -111。
 *
 * @param {string} bvid
 * @param {boolean} add
 * @returns {Promise<void>}
 */
export async function dealFav(bvid, add) {
  await postForm('/x/v3/fav/resource/deal', {
    form: { bvid, add: add ? 1 : 0, type: 2, platform: 'web' },
  })
}

/* --------------------------------------------------- TV 端扫码（passport） */

/**
 * TV 端签名请求（APP 签名，非 WBI）。passport 域不在 BILI_API 下，单列。
 *
 * @param {string} path
 * @param {object} params
 * @returns {Promise<{code:number, message?:string, data?:object}>}
 */
async function tvPost(path, params) {
  const signed = signApp(params, CONFIG.LOGIN.TV_APPKEY, CONFIG.LOGIN.TV_APPSEC)
  const res = await requestOnce({
    url: `${CONFIG.BILI_PASSPORT}${path}`,
    method: 'POST',
    headers: biliHeaders({ 'Content-Type': 'application/x-www-form-urlencoded' }),
    body: buildFormBody(signed),
    // 扫码登录不带主站 Cookie：这是申请新会话的接口，带旧票据反而可能被拒
    withCookie: false,
  })
  return res.json || {}
}

function buildFormBody(params) {
  const parts = []
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null) continue
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
  }
  return parts.join('&')
}

/**
 * 申请 TV 端登录二维码。
 *
 * 登录票据直接在响应体 cookie_info 里，不碰响应头——所以这条路不依赖
 * Set-Cookie，也不依赖跨域地址。
 *
 * @returns {Promise<{url:string, authCode:string}>}
 */
export async function tvGenerateQrCode() {
  const body = await tvPost('/x/passport-tv-login/qrcode/auth_code', {
    local_id: CONFIG.LOGIN.TV_LOCAL_ID,
    ts: Math.floor(Date.now() / 1000),
  })
  if (body.code !== 0 || !body.data) {
    throw new Error(`申请二维码失败：code=${body.code} ${body.message || ''}`.trim())
  }
  const { url, auth_code: authCode } = body.data
  if (!url || !authCode) throw new Error('申请二维码失败：返回缺少 url/auth_code')
  return { url, authCode }
}

/**
 * 轮询 TV 端扫码状态。
 *
 * 状态码在**根级 code**（不是 data.code）：
 *   0 成功 | 86038 已失效 | 86039 / 86090 已扫码未确认
 * 成功时 data.cookie_info.cookies[] 直接给出登录票据。
 *
 * @param {string} authCode
 * @returns {Promise<object>} 完整响应体
 */
export function tvPollQrCode(authCode) {
  return tvPost('/x/passport-tv-login/qrcode/poll', {
    auth_code: authCode,
    local_id: CONFIG.LOGIN.TV_LOCAL_ID,
    ts: Math.floor(Date.now() / 1000),
  })
}

export default {
  getUserInfo,
  getVideoInfo,
  search,
  getAudioStreamInfo,
  resolveStream,
  getCreatedFavFolders,
  getFavResources,
  dealFav,
  toTrack,
  tvGenerateQrCode,
  tvPollQrCode,
}
