/**
 * 曲目同一性匹配（纯函数，不 import 任何 @system.* 模块，可被 Node 单测）
 *
 * 为什么需要它：播放队列与来源列表（收藏夹 / 官方推荐）解耦之后，
 * 「列表页点一首歌」不再等于「用整份列表重建队列」：
 *   - 点的歌可能已经在队列里（比如正从这份收藏夹连播）→ 应该跳播而不是重复插入；
 *   - 来源列表页要标出「队列里正在播的是哪一行」（列表 ≠ 队列，不能按下标对齐）。
 * 两处都依赖「怎么算同一首歌」，收进这一个模块。
 *
 * 匹配规则：
 *   1. 优先 bvid（B 站稿件唯一，收藏夹与推荐流都带）；
 *   2. 没有 bvid 时退化到 avid（收藏夹条目的 id / 热门条目的 aid）。
 * 两首歌只有一方带 bvid 时按 avid 对不上就当不同 —— 宁可重复入队，
 * 不要把两首不同的歌错判成同一首。
 */

/** 曲目的匹配键：'bv:BV1xx' / 'av:12345'，取不到任何标识时为 '' */
export function trackKey(t) {
  if (!t || typeof t !== 'object') return ''
  if (t.bvid) return 'bv:' + t.bvid
  const avid = t.id !== undefined && t.id !== null ? t.id : t.aid
  if (avid === undefined || avid === null || avid === '') return ''
  return 'av:' + avid
}

/** 是否同一首歌（任一方取不到键时一律 false） */
export function sameTrack(a, b) {
  const ka = trackKey(a)
  return !!ka && ka === trackKey(b)
}

/** 在曲目列表中找同一首歌的下标，找不到返回 -1 */
export function findTrackIndex(list, track) {
  const key = trackKey(track)
  if (!key) return -1
  const arr = list || []
  for (let i = 0; i < arr.length; i++) {
    if (trackKey(arr[i]) === key) return i
  }
  return -1
}

export default {
  trackKey,
  sameTrack,
  findTrackIndex,
}
