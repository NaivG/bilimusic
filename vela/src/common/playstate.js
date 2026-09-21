/**
 * 跨 VM 共享播放态（纯函数，不依赖 @system，可被 Node 单测覆盖）
 *
 * 背景：Vela 运行时给**每个 page 起一个独立 JS VM**（真机日志：
 * `[Page:73] new page, new vm page_info:name:pages/player`），模块级变量不跨页共享 ——
 * list.ux 里 `import playerService` 与 pages/player 里的那份是**两个互不相干的实例**。
 * 真机上表现为：从来源页（更多/收藏夹/推荐）点歌能出声（@system.audio 是全局原生服务），
 * 但主页那份 playerService 队列还是空的，一直显示「未在播放」。
 *
 * 所以「当前播哪首」必须落到 @system.storage，由每个 VM 自己读回来对账。
 * 本文件定义那份共享记录的字段与合并规则。
 *
 * 关键约束：storage 没有 CAS，多个 VM 会并发写同一条记录，
 * 因此每个 VM 只能写**自己改动过的字段**（读-改-写），绝不整份覆盖 ——
 * 否则 A 页暂停时会把 B 页刚切的歌 index 冲掉。
 */

/** 与 playerService 的 STATE 保持一致（本文件纯 JS，故不 import 那边） */
const STATE_VALUES = ['idle', 'loading', 'playing', 'paused', 'error']

function toInt(value, fallback) {
  const n = Math.floor(Number(value))
  return isFinite(n) ? n : fallback
}

/**
 * 归一化从 storage 读回来的共享态。
 * 记录可能是空的（首次运行）、旧版本写的、或被人手改过，脏值一律退化成默认值。
 *
 * 注意这里**没有 volume**：音量的唯一真相是系统媒体音量（@system.volume），
 * 任何 VM 都能直接读到真值，再存一份只会与外部（实体键/系统设置）改出来的音量对不上。
 * 老版本写下的 volume 字段会被直接忽略（不报错、不影响其它字段）。
 */
export function normalizeShareState(raw) {
  const r = raw && typeof raw === 'object' ? raw : {}
  const state = typeof r.state === 'string' && STATE_VALUES.indexOf(r.state) >= 0 ? r.state : ''
  return {
    ver: Math.max(0, toInt(r.ver, 0)),
    ts: Math.max(0, toInt(r.ts, 0)),
    index: toInt(r.index, -1),
    queueVer: Math.max(0, toInt(r.queueVer, 0)),
    state,
    loop: !!r.loop,
  }
}

/**
 * 读-改-写：把 patch 里出现过的字段合并进旧记录，其余字段原样保留。
 * 版本号自增，供其他 VM 判断「要不要重新对账」。
 *
 * @param {object} prev 从 storage 读到的旧记录（可以是 null）
 * @param {object} patch 本 VM 要改的字段：index / queueVer / state / loop
 * @param {number} [now] 时间戳（测试可注入）
 */
export function bumpShareState(prev, patch, now) {
  const base = normalizeShareState(prev)
  const p = patch && typeof patch === 'object' ? patch : {}

  return {
    ver: base.ver + 1,
    ts: isFinite(Number(now)) && now !== undefined && now !== null ? Number(now) : Date.now(),
    index: p.index !== undefined ? toInt(p.index, base.index) : base.index,
    queueVer: p.queueVer !== undefined ? Math.max(0, toInt(p.queueVer, base.queueVer)) : base.queueVer,
    state:
      typeof p.state === 'string' && STATE_VALUES.indexOf(p.state) >= 0 ? p.state : base.state,
    loop: p.loop !== undefined ? !!p.loop : base.loop,
  }
}

/**
 * 共享态版本号与本地已知版本不同 → 需要重新对账。
 * 用不等号（而非大于）是为了兼容 storage 被清空后 ver 归零的情况。
 */
export function isShareNewer(shareVer, localVer) {
  return toInt(shareVer, 0) !== toInt(localVer, -1)
}

/** 队列版本号是否变化（队列 JSON 有几百字节到几 KB，能省一次读就省一次） */
export function isQueueNewer(shareQueueVer, localQueueVer) {
  return toInt(shareQueueVer, 0) !== toInt(localQueueVer, -1)
}

/** 日志用短描述：真机排查时一眼看出共享态当前长什么样 */
export function describeShareState(raw) {
  const s = normalizeShareState(raw)
  return (
    'ver=' +
    s.ver +
    ' queueVer=' +
    s.queueVer +
    ' index=' +
    s.index +
    ' state=' +
    (s.state || '-') +
    ' loop=' +
    (s.loop ? '1' : '0')
  )
}

export default {
  normalizeShareState,
  bumpShareState,
  isShareNewer,
  isQueueNewer,
  describeShareState,
}
