/**
 * Node 侧解析钩子：把 @system.* 换成 scripts/stubs/ 下的桩，
 * 让 scripts/verify.mjs 能在不刷机的情况下跑真实的 playerService 代码。
 *
 * 用法（见 verify.mjs 第 12 节）：
 *   import { register } from 'node:module'
 *   register('./aiot-hooks.mjs', import.meta.url)
 *   const appVm = await import('../src/services/playerService.js?vm=app')
 *
 * `?vm=xxx` 查询串是刻意的：同一个文件配上不同查询串会被 Node 当成不同模块，
 * 于是能加载出两份**互不共享模块级变量**的 playerService ——
 * 正好复现 Vela「每个 page 一个独立 JS VM」的语义。
 * 而它 import 的 @system.storage / @system.audio 桩只有一份（模块缓存），
 * 对应真机上它们都是全局原生服务。
 */

const STUBS = {
  '@system.audio': './stubs/system.audio.mjs',
  '@system.volume': './stubs/system.volume.mjs',
  '@system.storage': './stubs/system.storage.mjs',
  '@system.device': './stubs/system.device.mjs',
  '@system.app': './stubs/system.app.mjs',
  // @system.file 官方口径「所有设备都支持」，源码里是静态 import —— 这里必须给桩
  '@system.file': './stubs/system.file.mjs',
}

// 注意：@system.fetch 与 @system.interconnect 不在这张表里 —— 它们是要"可能不存在"
// 的接口（Redmi Watch 4 / Watch H1 E 上就没有 fetch），源码里走的是
// `require('@system.fetch')` / `require('@system.interconnect')` + try/catch
// （与 crypto.js 取 @system.crypto 同一写法），import 解析钩子管不到。
// 离线自检里由 verify.mjs 注入 globalThis.require 指到同一个桩模块，见第 15 节。

export async function resolve(specifier, context, next) {
  const stub = STUBS[specifier]
  if (stub) {
    return { url: new URL(stub, import.meta.url).href, shortCircuit: true }
  }

  // 快应用源码里的相对导入不带扩展名（`from '../common/config'`），
  // Node ESM 不认，这里补上 .js（先试文件再试目录 index.js）
  const hashAt = specifier.search(/[?#]/)
  const path = hashAt >= 0 ? specifier.slice(0, hashAt) : specifier
  const suffix = hashAt >= 0 ? specifier.slice(hashAt) : ''
  if (path.charAt(0) === '.' && !/\.[a-z]+$/i.test(path)) {
    try {
      return await next(path + '.js' + suffix, context)
    } catch (e) {
      return next(path + '/index.js' + suffix, context)
    }
  }

  return next(specifier, context)
}
