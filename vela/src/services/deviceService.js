import device from '@system.device'
import {
  normalizeDeviceInfo,
  resolveScreenShape,
  safeHorizontalInsetPx,
  shapeClassOf,
  supportsCoverBackground,
  matchedCoverDevice,
} from '../common/device'

/**
 * 设备信息（@system.device）—— 屏幕安全区与「封面背景图」白名单的唯一来源
 *
 * 语义与 @system.device 的关系：
 *   - getInfo 是**回调**接口（没有 Promise 形态），且老 runtime 上可能整个模块
 *     不可用（manifest 没声明 / 机型不支持），所以内部一律 try/catch 兜住，
 *     任何失败都退化成「矩形屏 + 不渲染背景图」的保守结论，绝不把页面拖挂；
 *   - 每个 page 一个独立 JS VM，模块级缓存**不跨页共享**，所以每页各自问一次。
 *     原生侧开销可忽略，同一个 VM 内只问一次（pending 幂等）。
 *
 * 为什么不在 CSS 里用 @media 直接判定：见 common/device.js 顶部注释
 * （媒体查询对 S1 Pro / Redmi Watch 4 / 手环 8 Pro 机型不支持，而 S1 Pro 是圆屏）。
 */

/** 未就绪 / 拿不到信息时的保守结论：矩形屏 + 不渲染背景图 */
const FALLBACK = normalizeDeviceInfo(null)

let pending = null
let cached = FALLBACK

/** 最近一次归一化后的设备信息（同步读，未就绪时是保守兜底值） */
export function getCached() {
  return cached
}

/**
 * 拉取设备信息（幂等：同一个 VM 内只会真的调一次原生接口）
 * @returns {Promise<object>} normalizeDeviceInfo 的结果，永不 reject
 */
export function whenReady() {
  if (pending) return pending

  pending = new Promise((resolve) => {
    let settled = false
    const done = (info) => {
      if (settled) return
      settled = true
      cached = info
      if (info.available) {
        console.log(
          '[Device]',
          info.brand,
          info.model || info.product,
          '| 形状:',
          resolveScreenShape(info),
          '| 背景图白名单:',
          matchedCoverDevice(info) || '未命中'
        )
      } else {
        console.warn('[Device] 未取到设备信息，按矩形屏 + 无背景图处理')
      }
      resolve(info)
    }

    try {
      device.getInfo({
        success: (ret) => done(normalizeDeviceInfo(ret)),
        fail: () => done(FALLBACK),
      })
    } catch (e) {
      console.warn('[Device] getInfo 不可用（manifest 是否声明 system.device？）:', e)
      done(FALLBACK)
    }
  })

  return pending
}

/**
 * 页面要用的现成结论。未就绪时返回保守值，就绪后重新调一次即可拿到真值。
 *
 * safeInsetPx 是「左右安全内缩」的物理像素值，页面把它绑进 .safe 容器的
 * 内联 style（padding-left / padding-right 同值 —— 对称由构造保证）。
 * pageWidthPx 是屏宽的物理像素值，播放页把它绑进两屏 .screen 的内联 style
 * （官方 scroll 文档：水平滚动需要设置定宽，横向翻页两屏靠它成页）；
 * 拿不到屏宽时为 0，页面自行兜底。
 * pageHeightPx 是屏高的物理像素值，播放页把它绑进两屏 .screen 的内联 style
 * （scroll 的子项必须有确定高度才能成页）；拿不到屏高时为 0，页面自行兜底。
 *
 * @returns {{info:object, available:boolean, shape:string, shapeClass:string,
 *            safeInsetPx:number, pageWidthPx:number, pageHeightPx:number,
 *            coverBackground:boolean, coverDevice:string}}
 */
export function capabilities() {
  return {
    info: cached,
    available: cached.available,
    shape: resolveScreenShape(cached),
    shapeClass: shapeClassOf(cached),
    safeInsetPx: safeHorizontalInsetPx(cached),
    pageWidthPx: cached.screenWidth > 0 ? cached.screenWidth : 0,
    pageHeightPx: cached.screenHeight > 0 ? cached.screenHeight : 0,
    coverBackground: supportsCoverBackground(cached),
    coverDevice: matchedCoverDevice(cached),
  }
}

/** 测试用：清掉缓存与幂等 Promise */
export function reset() {
  pending = null
  cached = FALLBACK
}

export default {
  getCached,
  whenReady,
  capabilities,
  reset,
}
