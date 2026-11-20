# `bonsoir_windows`（vendored）

[bonsoir_windows](https://pub.dev/packages/bonsoir_windows) **7.3.1**（pub.dev 上的
最新版，2026-10-25）的整包副本，修复了 Windows 原生实现的崩溃问题。

等Issue #156 和 #159 被修复后即可移除。

## 为什么要 vendor

`bonsoir_windows` 的 Windows 实现是 C++（`DnsServiceBrowse` / `DnsServiceResolve` /
`DnsServiceRegister`）。系统 DNS-SD 的回调跑在 **系统 DNS 工作线程**，而方法通道
回调跑在 **Flutter 平台线程**，两边对同一批对象没有任何同步：

1. `resolveCallback`（工作线程）直接改写 `services` 里那个 `BonsoirService` 的
   `hostAddresses` / `hostname` / `port` / `attributes`；
2. 平台线程在 `MessageWindowProc → processEventQueue → SuccessObject::process →
   BonsoirService::toEncodable()` 里遍历同一个对象做序列化。

两边撞上就是 use-after-free / 读已释放的 `std::string`。此外还有一类 `utilities.cpp` 
里的 `toUtf8()` / `toUtf16()` 抛出 `std::runtime_error` 穿过 C 回调 / 平台通道，
走到 `std::terminate`（直接炸出VC Runtime Error）。对端 mDNS 记录里只要有脏字节就能触发。

上游对应 issue：[#159](https://github.com/Skyost/Bonsoir/issues/159)（本崩溃）、
[#156](https://github.com/Skyost/Bonsoir/issues/156)（stop 持锁 cancel 死锁）。

属于严重的Major Bug，只要局域网同步是打开的就有概率在运行时或者必定在关闭时把应用进程崩↑飞↓。

## 相对上游 7.3.1 的改动

### 1. 上游 PR #161（`Skyost/Bonsoir#161`，未合并）

https://github.com/Skyost/Bonsoir/pull/161 —— 该 PR 的 base 与我们使用的 7.3.1
五个文件 blob 完全一致，直接整份应用。内容是：

- `services` 加 `servicesMutex`；新增 `replaceService()`；
- `resolveCallback` 不再原地改服务对象，而是 **复制一份** 再
  `replaceService()`（`services` 里被登记过的对象从此只读）；
- 待解析请求从 `resolvingServices`（以 `shared_ptr` 为键、cancel 句柄直接 `delete`）
  换成 **按自增 id 键控的全局表** `gPendingResolves`，晚到/重复的回调查不到请求
  就直接返回，不再二次 delete；
- `BonsoirAction::detachFromEngine()`：引擎退出后不再碰事件通道（修退出崩溃）；
- `stop()` 里的 cancel 移到锁外（修 #156 死锁）。

### 2. 本仓库追加

- **browse 侧的悬垂 `this`**：`DnsServiceBrowse` 的 `pQueryContext` 仍是
  `BonsoirDiscovery *this`，而 `DnsServiceBrowseCancel()` 是异步的——取消之后
  回调还会带着这个指针回来。上游在 `disposeAfterStreamCancel` 回调里直接把对象
  `erase`（= delete），晚到的回调就是 use-after-free。现在改成
  `BonsoirWindowsPlugin::retireBroadcast()/retireDiscovery()`：**只 `dispose()`、
  不销毁**，挪进 `retiredBroadcasts` / `retiredDiscoveries`，留到插件析构（引擎
  退出）时统一释放。每次 `start()` 才产生一个对象，数量有界。
- **回调异常兜底**：`browseCallback` / `resolveCallback` / `registerCallback` 全部
  包一层 `try/catch(...)`（`*Unsafe` 为原实现），异常绝不允许穿过 C 回调。
- **`utilities.cpp` 不再抛异常**：`toUtf16()` / `toUtf8()` / `getComputerName()`
  失败时返回空串/空宽串，由上层按「名字为空」降级。对端数据不可信，用抛异常
  处理只会把进程 abort 掉。
- **`browseCallback` 的 `dnsRecord` 空指针守卫**：扫描结束、`status == ERROR_SUCCESS`
  但记录为空时原实现会直接解引用。

## 维护约定

- 上游发布修复后，优先 **删掉本目录 + `dependency_overrides` 里的
  `bonsoir_windows` 条目**，退回 pub.dev。
- 只改 `windows/` 下的原生实现；Dart 侧（`lib/bonsoir_windows.dart`）保持与上游
  一致，避免和 `bonsoir` 前端行为分叉。
