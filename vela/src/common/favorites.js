/**
 * 本地收藏的纯逻辑（不 import 任何 @system.* 模块，可被 Node 单测）
 *
 * 「本地收藏」是存放在手表本地的收藏夹（@system.storage 的
 * bilimusic_local_favs），与 B 站账号的收藏夹互不相干：来源页点歌、播放页
 * ♥ 收藏当前曲目，之后在「更多 → 本地收藏」里随时回听。登录与否都能用。
 *
 * 职责边界：
 *   - 本文件只做**数据形状**：条目归一化（挑字段、剥易变字段）、整表归一化
 *     （去重、按收藏时间倒序）、toggle 的读-改-写计算。storage 的读写落在
 *     services/favorites.js，页面只消费那个门面。
 *   - 跨 VM 语义：每个 page 一个独立 JS VM，收藏表没有版本号水位，靠
 *     「每次操作都整表读 → 改 → 整表写」与其它 VM 对齐（收藏改动低频且由
 *     点击触发，不值得上播放态那套 ver 协议，见 services/favorites.js 注释）。
 *
 * 条目形状（normalizeFavTrack 的输出）：
 *   {
 *     key: 'bv:BV1xx411c7mD' | 'av:12345',  // 收藏键（tracks.trackKey 派生）
 *     bvid, id(avid), cid, title, artist, cover, duration,
 *     favTime,                              // 收藏时间戳 ms，展示与排序用
 *   }
 */

// 唯一带显式 .js 扩展名的相对导入：本模块是纯函数、没有 @system 依赖，
// 要能被 scripts/verify.mjs 在挂上解析钩子**之前**静态 import（Node ESM 认不全
// 无扩展名路径）。webpack（aiot build）对显式扩展名照常解析，两边都通。
import { trackKey } from './tracks.js'

/**
 * 收藏条目是**白名单重建**的（见 normalizeFavTrack）：队列里的曲目对象会被
 * biliApi.resolveTrackUrl 挂上 `track.streams` / `track.playUrl` / `track.url`
 * —— 那是带防盗链签名与时效的 CDN 直链（实测 120 分钟过期）。收藏要长期落盘，
 * 这些字段存下来没有一点用处：白占 storage，而且过期地址请求回来正是 403，
 * 排查时反而误导（播放侧的 resolveUrl 会把过期地址滤掉重新取流，但不该靠
 * 这条链路兜底收藏数据）。
 */
const VOLATILE_KEYS = ['playUrl', 'streams', 'url']

/** 本地收藏表的最大条数（services 层写盘前截断）。超限丢最旧的 —— 手表上收藏
 * 到这个量级之前，@system.storage 单键体积先撑爆的风险更大 */
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

  const out = {
    key,
    bvid: track.bvid || '',
    // avid：收藏夹条目带 id，推荐流热门条目带 aid，两头都认（同 tracks.trackKey）
    id:
      track.id !== undefined && track.id !== null
        ? track.id
        : track.aid !== undefined && track.aid !== null
          ? track.aid
          : '',
    // cid 保留：取流时要它（getAudioStreamInfo(bvid, cid)），存下来能省一次稿件查询
    cid: track.cid || 0,
    title: track.title || track.name || '未知',
    artist: track.artist || track.artists || '未知',
    cover: track.cover || '',
    duration: Number(track.duration) > 0 ? Math.floor(Number(track.duration)) : 0,
    favTime: toFavTime(track.favTime, now),
  }
  // 条目是**白名单重建**出来的：队列曲目上挂着的
  // streams / playUrl / url 等易变字段与别的私有字段从形状上就进不了收藏
  return out
}

/**
 * 归一化整份收藏表：脏输入丢弃、按 key 去重（同 key 保留 favTime 新的那份）、
 * 按收藏时间倒序（最新收藏在最前，列表页第一行就是刚收藏的歌）。
 *
 * @param {Array} raw storage 里读回来的原始数组（可能是 null / 垃圾数组）
 */
export function normalizeFavList(raw) {
  const arr = Array.isArray(raw) ? raw : []
  const seen = {}
  const out = []
  for (let i = 0; i < arr.length; i++) {
    const t = normalizeFavTrack(arr[i])
    if (!t) continue
    const prev = seen[t.key]
    if (prev) {
      if (t.favTime > prev.favTime) {
        prev.title = t.title
        prev.artist = t.artist
        prev.cover = t.cover
        prev.duration = t.duration
        prev.cid = t.cid
        prev.bvid = t.bvid
        prev.id = t.id
        prev.favTime = t.favTime
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
 * toggle 的核心计算（纯函数，services 层负责把结果写回 storage）。
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
  const entry = normalizeFavTrack(track, now)
  cur.unshift(entry)
  return { list: cur, added: true, changed: true }
}

/**
 * 这首曲目在收藏表里吗（任何一方取不到键时一律 false —— 与 tracks.sameTrack
 * 同一条铁律：宁可显示「未收藏」，不把两首不同的歌错判成同一首）
 */
export function isFavInList(list, track) {
  const key = trackKey(track)
  if (!key) return false
  const cur = normalizeFavList(list)
  return cur.some((t) => t.key === key)
}

export default {
  FAV_LIST_MAX,
  normalizeFavTrack,
  normalizeFavList,
  toggleInFavList,
  isFavInList,
}
