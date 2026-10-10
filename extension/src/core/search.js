/**
 * 搜索：输入分派 + 结果解析（纯函数）
 */

import { av2bv, extractAid, extractBvid } from './av_bv.js'

/** 封面缩略图后缀 */
export const COVER_THUMB_SUFFIX = '@672w_378h'

/** 搜索结果类型 */
export const RESULT_TYPES = ['video', 'album', 'author', 'bangumi', 'topic', 'upuser']

/** 类型的中文展示名，UI 筛选条直接消费 */
export const RESULT_TYPE_LABELS = {
  video: '视频',
  album: '专辑',
  author: 'UP主',
  bangumi: '番剧',
  topic: '话题',
  upuser: '用户',
}

/**
 * `result_type` 字段 → 类型枚举。返回 null 表示这一组结果本端不认，整组跳过。
 *
 * @param {string} raw
 * @returns {string|null}
 */
export function mapResultType(raw) {
  switch (raw) {
    case 'video':
    case 'album':
    case 'author':
    case 'media_bangumi':
    case 'topic':
    case 'upuser':
      return raw === 'media_bangumi' ? 'bangumi' : raw
    default:
      return null
  }
}

/**
 * 搜出来的标题是富文本：关键词被 `<em>` 包着。先剥标签再解实体，
 * 顺序不能反（`&lt;em&gt;` 这类会被误伤）。
 *
 * @param {string} raw
 * @returns {string}
 */
export function cleanTitle(raw) {
  if (raw === undefined || raw === null) return ''
  let title = String(raw)
  if (title.includes('<em') && title.includes('</em>')) {
    title = title.replace(/<[^>]*>/g, '')
  }
  return title
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
}

/**
 * 副标题按类型拼装。
 *
 * @param {object} json
 * @param {string} type
 * @returns {string}
 */
export function buildSubtitle(json, type) {
  switch (type) {
    case 'video':
      return `${json.author ?? '未知作者'} - ${json.tag ?? ''}`
    case 'author':
      return `${json.fans ?? ''} 粉丝`
    case 'album':
      return json.author ?? '未知作者'
    case 'bangumi':
      return json.desc ?? ''
    case 'topic':
      return `${json.thread ?? 0} 讨论`
    case 'upuser':
      return json.uname ?? ''
    default:
      return ''
  }
}

/**
 * 封面可能给成 `//i0.hdslb.com/...` 这种协议相对地址，补成 https。
 *
 * @param {string} raw
 * @returns {string}
 */
export function normalizeCover(raw) {
  const cover = String(raw || '')
  if (!cover) return ''
  return cover.startsWith('http') ? cover : `https:${cover}`
}

/**
 * 取第一个非 null/undefined 的值。
 *
 * 不写 `a ?? b ?? c`：三元表达式会产出 `''`，而 `''` 在 JS 里不是 nullish，
 * 链条会提前停在那儿，后面的 fallback 永远轮不到。
 *
 * @param {...any} vals
 * @returns {any}
 */
function firstNonNull(...vals) {
  for (const v of vals) {
    if (v !== undefined && v !== null) return v
  }
  return ''
}

/**
 * 单条搜索结果 → 本端的播放曲目形状。
 *
 * 只有 video 类型能直接播（有 bvid），其余类型在 UI 上是不可播放的入口项。
 *
 * @param {object} json
 * @param {string} type
 * @returns {object|null}
 */
export function parseSearchItem(json, type) {
  if (!json || typeof json !== 'object') return null
  const id = firstNonNull(json.bvid, json.mid, json.season_id)
  const bvid = json.bvid || ''
  return {
    id: String(id),
    title: cleanTitle(json.title),
    subtitle: buildSubtitle(json, type),
    coverUrl: normalizeCover(json.pic),
    type,
    // 播放曲目形状：搜索结果没有 cid，取流时才查稿件详情
    bvid,
    playable: type === 'video' && !!bvid,
  }
}

/**
 * 解析 `search/all/v2` 的响应体。
 *
 * 信封形状：`{ data: { result: [ { result_type, data: [...] }, ... ], page, numPages } }`
 * —— `result` 是按类型分组的，每组里的条目才是真正的结果。
 *
 * @param {object} data 响应里的 data 字段（可能不是对象）
 * @param {string} query 原始关键词
 * @returns {{keyword:string, results:Array, hasMore:boolean, page:number, totalResults:number}}
 */
export function parseSearchResults(data, query) {
  const groups = Array.isArray(data?.result) ? data.result : []
  const results = []
  let total = 0

  for (const group of groups) {
    if (!group || typeof group !== 'object') continue
    const mapped = mapResultType(group.result_type)
    if (!mapped) continue
    const items = Array.isArray(group.data) ? group.data : []
    for (const item of items) {
      const parsed = parseSearchItem(item, mapped)
      if (parsed) results.push(parsed)
    }
    total += items.length
  }

  const page = Number.isInteger(data?.page) ? data.page : 1
  const numPages = Number.isInteger(data?.numPages) ? data.numPages : 1

  return {
    keyword: query,
    results,
    hasMore: page < numPages,
    page,
    totalResults: total,
  }
}

/** 空响应（输入为空 / 解析前就失败） */
export function emptySearchResponse(query) {
  return { keyword: query, results: [], hasMore: false, page: 0, totalResults: 0 }
}

/**
 * 输入分派：BV 号直接查稿件详情，AV 号先转 BV，其余走关键词搜索。
 *
 * @param {string} raw 用户输入
 * @returns {{kind:'bvid'|'keyword', value:string}}
 *   kind=bvid 时 value 是 BV 号；kind=keyword 时 value 是清洗后的关键词
 */
export function classifyQuery(raw) {
  const trimmed = String(raw || '').trim()
  if (!trimmed) return { kind: 'keyword', value: '' }

  const bvid = extractBvid(trimmed)
  if (bvid) return { kind: 'bvid', value: bvid }

  const aid = extractAid(trimmed)
  if (aid > 0) return { kind: 'bvid', value: av2bv(aid) }

  return { kind: 'keyword', value: trimmed }
}

export default {
  COVER_THUMB_SUFFIX,
  RESULT_TYPES,
  RESULT_TYPE_LABELS,
  mapResultType,
  cleanTitle,
  buildSubtitle,
  normalizeCover,
  parseSearchItem,
  parseSearchResults,
  emptySearchResponse,
  classifyQuery,
}
