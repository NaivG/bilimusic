/**
 * WBI 口令获取与签名
 *
 * 口令来源优先是 `/x/web-interface/nav` 返回的 `wbi_img.img_url` / `sub_url`，
 * 派生出 32 位 mixin_key 后缓存（官方每日更替，这里缓存 6 小时）。
 *
 * 只依赖 http.js，不 import request.js——request.js 反过来依赖这里。
 */

import { CONFIG } from '../core/config.js'
import { deriveMixinKey, signWbi } from '../core/crypto.js'
import { BiliApiException } from './errors.js'
import { requestOnce, biliHeaders } from './http.js'

let cache = { mixinKey: '', ts: 0 }

/** 进行中的取口令请求，多个调用方共享同一次（避免并发时打一串 nav） */
let inflight = null

/**
 * 口令失效（撞风控后的补签链路会先调它）。
 * 不缓存失败结果：失败就该下次重试，而不是把失败钉死 6 小时。
 */
export function invalidate() {
  cache = { mixinKey: '', ts: 0 }
}

/** 从 `.../img_key.png` 里抠出 key */
function extractWbiKey(url) {
  const file = String(url || '').split('/').pop() || ''
  return file.split('.')[0]
}

/**
 * 取 WBI 实时口令并派生 mixin_key（带内存缓存）。
 *
 * @param {boolean} [force] 无视缓存强制刷新
 * @returns {Promise<string>} 32 位 mixin_key
 */
export function getMixinKey(force) {
  if (!force && cache.mixinKey && Date.now() - cache.ts < CONFIG.WBI_CACHE_TTL) {
    return Promise.resolve(cache.mixinKey)
  }
  if (inflight) return inflight

  inflight = (async () => {
    try {
      const res = await requestOnce({
        url: `${CONFIG.BILI_API}/x/web-interface/nav`,
        headers: biliHeaders(),
      })
      const data = res.json && res.json.data
      if (!data || !data.wbi_img) {
        throw new BiliApiException(res.json ? res.json.code ?? -1 : -1, 'nav 未返回 wbi_img，无法取 WBI 口令')
      }
      const mixinKey = deriveMixinKey(extractWbiKey(data.wbi_img.img_url), extractWbiKey(data.wbi_img.sub_url))
      cache = { mixinKey, ts: Date.now() }
      return mixinKey
    } finally {
      inflight = null
    }
  })()

  return inflight
}

/**
 * 给参数对象做 WBI 签名（含取口令）。
 *
 * @param {object} params
 * @param {boolean} [force] 强制刷新口令
 * @returns {Promise<object>} 原参数 + wts + w_rid
 */
export async function signedParams(params, force) {
  const mixinKey = await getMixinKey(force)
  return signWbi(params, mixinKey)
}

export default { getMixinKey, signedParams, invalidate }
