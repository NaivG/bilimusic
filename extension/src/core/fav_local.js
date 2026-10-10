/**
 * 本地收藏的数据形状（纯函数）
 *
 * 「本地收藏」存在 chrome.storage 的 localFav 键里，与 B 站账号的在线收藏夹
 * 互不相干：搜索结果页、队列、收藏夹页都能收藏，登录与否都能用。
 *
 * 本文件只做数据形状——条目归一化（挑字段、剥易变字段）、整表归一化
 * （去重、按收藏时间倒序）、toggle 的读-改-写计算。storage 的读写落在
 * bg/service_worker.js，UI 只消费消息门面。
 *
 * 条目是白名单重建的：队列里的曲目对象会被 net/bili_api 的取流挂上
 * `streams` / `playUrl` / `url` —— 那是带防盗链签名与时效的 CDN 直链
 * （实测 120 分钟过期）。收藏要长期落盘，这些字段存下来只会白占 storage，
 * 而且过期地址请求回来正是 403，排查时反而误导。
 */

import { trackKey } from './tracks.js'

/** 本地收藏表最大条数（写盘前截断，超限丢最旧） */
export const FAV_LIST_MAX = 500

function toFavTime(value, fallback) {
  const n = Number(value)
  if (value !== undefined && value !== null && isFinite(n) && n >= 0) return Math.floor(n)
  const f = Number(fallback)
  return isFinite(f) ? Math.floor(f) : Date.now()
}

/**
 * 把任意输入归一化成收藏条目。
 *
 * @param {object} track 队列/来源列表里的曲目对象（可能带着 streams 等易变字段）
 * @param {number} [now] 收藏时间戳（测试注入用；缺省用当前时刻）
 * @returns {object|null} 无法确定同一性（既没 bvid 也没 avid）时返回 null，
 *   调用方直接丢弃 —— 没有键的曲目收藏了也找不回来
 */
export function normalizeFavTrack(track, now) {
  if (!track || typeof track !== 'object') return null
  const key = trackKey(track)
  if (!key) return null

  return {
    key,
    bvid: track.bvid || '',
    id:
      track.id !== undefined && track.id !== null
        ? track.id
        : track.aid !== undefined && track.aid !== null
          ? track.aid
          : '',
    // cid 保留：取流时要它，存下来能省一次稿件查询
    cid: track.cid || 0,
    title: track.title || track.name || '未知',
    artist: track.artist || track.artists || '未知',
    cover: track.cover || '',
    duration: Number(track.duration) > 0 ? Math.floor(Number(track.duration)) : 0,
    favTime: toFavTime(track.favTime, now),
  }
}

/**
 * 归一化整份收藏表：脏输入丢弃、按 key 去重（同 key 保留 favTime 新的那份）、
 * 按收藏时间倒序（最新收藏在最前，列表第一行就是刚收藏的歌）。
 *
 * @param {Array} raw storage 里读回来的原始数组（可能是 null / 垃圾数组）
 */
export function normalizeFavList(raw) {
  const arr = Array.isArray(raw) ? raw : []
  const seen = {}
  const out = []
  for (const item of arr) {
    const t = normalizeFavTrack(item)
    if (!t) continue
    const prev = seen[t.key]
    if (prev) {
      if (t.favTime > prev.favTime) {
        Object.assign(prev, {
          title: t.title,
          artist: t.artist,
          cover: t.cover,
          duration: t.duration,
          cid: t.cid,
          bvid: t.bvid,
          id: t.id,
          favTime: t.favTime,
        })
      }
      continue
    }
    seen[t.key] = t
    out.push(t)
  }
  out.sort((a, b) => b.favTime - a.favTime)
  return out
}

/**
 * 满表截断：超限丢最旧的（favTime 最小的），调用方在写盘前调用。
 *
 * @param {Array} list
 * @param {number} [max]
 */
export function capFavList(list, max) {
  const limit = typeof max === 'number' && max > 0 ? max : FAV_LIST_MAX
  const arr = Array.isArray(list) ? list : []
  if (arr.length <= limit) return arr
  return arr.slice(0, limit)
}

/**
 * toggle 的核心计算（纯函数，service worker 负责把结果写回 storage）。
 *
 * @param {Array} list 当前收藏表（可以是脏数据，内部先归一化）
 * @param {object} track 要切换收藏状态的曲目
 * @param {number} [now] 收藏时间戳（测试注入用）
 * @returns {{list: Array, added: boolean, changed: boolean}}
 *   list = 写回 storage 的整份新表；added = 本次是否变成了「已收藏」；
 *   changed = 表是否真的变了（没键的曲目 toggle 不动表，调用方不必写盘）
 */
export function toggleInFavList(list, track, now) {
  const cur = normalizeFavList(list)
  const key = trackKey(track)
  if (!key) return { list: cur, added: false, changed: false }

  const idx = cur.findIndex((t) => t.key === key)
  if (idx >= 0) {
    cur.splice(idx, 1)
    return { list: cur, added: false, changed: true }
  }
  // 收藏时间用注入值：重收藏会把条目提到最前，语义上等于「刚刚又想听它」
  cur.unshift(normalizeFavTrack(track, now))
  return { list: cur, added: true, changed: true }
}

export default {
  FAV_LIST_MAX,
  normalizeFavTrack,
  normalizeFavList,
  capFavList,
  toggleInFavList,
}
