import { Storage } from './storage'
import { CONFIG } from '../common/config'
import {
  FAV_LIST_MAX,
  normalizeFavList,
  normalizeFavTrack,
  toggleInFavList,
  isFavInList,
} from '../common/favorites'

/**
 * 本地收藏服务（**每个 page VM 一份实例**，真相在 @system.storage）
 *
 * 与 B 站账号收藏夹（biliApi.getCreatedFavFolders / getFavResources）完全无关：
 * 这是存在手表本机的收藏夹，免登录可用，重装应用 / 清数据会一起清空。
 *
 * 跨 VM 语义（与 playerService 的共享态同一条 storage 通道，但简单得多）：
 *   - 每个 page 是独立 JS VM，模块级变量不跨页共享 —— 所以本服务**不留任何
 *     内存缓存**，每次操作都「整表读 → 改 → 整表写」，谁读到的都是最新的。
 *     收藏改动是秒级低频的用户点击，一次整表读写（几百字节）无所谓。
 *   - 没有 ver 水位：收藏表是「一整份列表」而不是「多字段并发改」的记录，
 *     播放态那套读-改-写合并协议（common/playstate.js）在这里没有用武之地。
 *     代价是两个 VM 同时 toggle 两首不同的歌会丢后写的那个 —— 手表上
 *     「同时按两个页面的收藏键」可以忽略不计，README 里已写明。
 *   - 写盘前按 FAV_LIST_MAX 截断（丢最旧），防止极端收藏量撑爆单键 storage。
 */

/** 收藏表当前的读取入口：脏数据（null / 垃圾数组 / 旧版本残留）全部归一化 */
export async function listFavs() {
  const raw = await Storage.getJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, null)
  return normalizeFavList(raw)
}

/** 收藏条数（更多页的入口副标题用） */
export async function favCount() {
  return (await listFavs()).length
}

/** 这首曲目收藏了吗（取不到键一律 false，见 common/favorites.isFavInList） */
export async function isFav(track) {
  const raw = await Storage.getJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, null)
  return isFavInList(raw, track)
}

/**
 * 加入收藏。已在收藏里时等价于「重收藏」：条目更新收藏时间、提到最前。
 *
 * @param {object} track 队列/来源列表里的曲目对象（带 streams 等易变字段也没关系，
 *   归一化时按白名单重建，进不了盘）
 * @returns {Promise<{added: boolean, count: number}>} added=false 表示曲目没有
 *   可收藏的键（bvid/avid 都没有），表未动
 */
export async function addFav(track) {
  const entry = normalizeFavTrack(track)
  if (!entry) return { added: false, count: (await favCount()) }
  const raw = await Storage.getJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, null)
  // [entry] 在最前：normalizeFavList 去重时同 key 保留 favTime 新的那份，
  // 重收藏自然落在最前（整表还会按 favTime 倒序兜一道）
  const next = capFavList(normalizeFavList([entry].concat(raw)))
  await Storage.setJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, next)
  return { added: true, count: next.length }
}

/**
 * 移出收藏。本来就没收藏时是 no-op（表不动、不写盘）。
 *
 * @returns {Promise<{removed: boolean, count: number}>}
 */
export async function removeFav(track) {
  const raw = await Storage.getJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, null)
  const cur = normalizeFavList(raw)
  const entry = normalizeFavTrack(track)
  if (!entry) return { removed: false, count: cur.length }
  const next = cur.filter((t) => t.key !== entry.key)
  if (next.length === cur.length) return { removed: false, count: cur.length }
  await Storage.setJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, next)
  return { removed: true, count: next.length }
}

/**
 * 收藏 / 取消收藏，二合一（播放页 ♥ 的唯一入口）。
 *
 * 表没变（曲目没有键）时不写盘，返回里 added=false。
 *
 * @returns {Promise<{added: boolean, count: number}>}
 */
export async function toggleFav(track) {
  const raw = await Storage.getJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, null)
  const res = toggleInFavList(raw, track)
  if (!res.changed) return { added: false, count: res.list.length }
  const next = capFavList(res.list)
  await Storage.setJson(CONFIG.STORAGE_KEYS.LOCAL_FAVS, next)
  return { added: res.added, count: next.length }
}

/** 超限截断：normalizeFavList 已经按 favTime 倒序，slice 掉的就是最旧的 */
function capFavList(list) {
  return list.length > FAV_LIST_MAX ? list.slice(0, FAV_LIST_MAX) : list
}

export default {
  listFavs,
  favCount,
  isFav,
  addFav,
  removeFav,
  toggleFav,
}
