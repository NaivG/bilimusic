# BiliMusic 架构

> 本文说明 BiliMusic 的代码如何分层、运行时如何装配、网络与本地数据如何收口，以及哪些边界不能破。
> 构建命令、分支与提交规范见 [CONTRIBUTING.md](CONTRIBUTING.md)；各端专属文档见文末[相关文档](#相关文档)。

---

## 目录

- [设计原则](#设计原则)
- [多端形态](#多端形态)
- [分层职责](#分层职责)
- [一次播放请求的路径](#一次播放请求的路径)
- [目录结构](#目录结构)
- [启动与退出顺序](#启动与退出顺序)
  - [启动（lib/main.dart）](#启动libmaindart)
  - [退出（lib/app/app_lifecycle.dart）](#退出libappapp_lifecycledart)
- [网络与登录态](#网络与登录态)
- [本地存储与数据库落点](#本地存储与数据库落点)
- [平台差异](#平台差异)
- [架构约束](#架构约束)
- [相关文档](#相关文档)

---

## 设计原则

BiliMusic 把 B 站当作音乐内容源：服务端只提供接口，搜索、整理、播放、漫游与同步都在本地完成。围绕这一点，代码组织坚持四条：

1. **一份领域核心，多种宿主。** Flutter 主端与终端客户端（TUI）共用 `lib/core/` 与 `lib/domain/`。`lib/core/` 必须保持纯 Dart（不 import Flutter 及任何插件），平台能力由宿主注入钩子（如 `NetworkConfig.cookieLoader / cookieSaver`），TUI 才能在没有 Flutter 引擎的进程里复用网络与登录态。
2. **依赖方向单向。** UI → 状态 → 编排 → 领域模型 / 基础设施。`core/` 不依赖 `features/`，UI 不直接实例化 Manager / Service。
3. **组合根集中。** 长生命周期服务只在 `lib/app/app_providers.dart` 创建与释放：依赖用 `ref.watch` 声明（初始化顺序在编译期确定），资源用 `ref.onDispose` 释放。UI 只消费 Provider，测试用 `ProviderContainer(overrides: [...])` 替换任意依赖。
4. **平台差异收敛到宿主。** OHOS 走 `ohos/` 宿主与 `packages/*_ohos`；Vela 与 Chrome 扩展各自是独立工程。所有平台都会编译的 Dart 代码判断平台一律用 `Platform.operatingSystem == 'ohos'`，不引入只有某家 SDK 才有的符号。

依赖方向：

```text
shared/widgets · app/shells · features/*/ui
              ↓
   features/<feature>/*_providers.dart
              ↓
   features/<feature>/logic · services
              ↓
        domain/          core/network · core/storage
```

`shared/theme/` 与 `shared/utils/` 是横向能力，UI 层可直接引用；`domain/` 不反向依赖任何层。

---

## 多端形态

仓库里有四个并列的客户端形态、一个共享 `lib/` 的 OHOS 宿主，以及 `packages/` 下的平台实现包：

| 形态 | 入口 | 代码 | 说明 |
| --- | --- | --- | --- |
| Flutter 主端 | `lib/main.dart` | `lib/` | Windows / Linux / Android 稳定；macOS / iOS 实验性；HarmonyOS 5.0+ 即将推出 |
| 终端客户端（TUI） | `bin/bilimusic_tui.dart` | `bin/tui/` | 纯 Dart，`dart_tui` + libmpv FFI；复用 `lib/core/network` 与 App 的登录态 |
| 小米 Vela 手表端 | `vela/src/app.ux` | `vela/` | JS 快应用，走 npm；每个 page 一个独立 JS VM，与主项目不共享代码 |
| Chrome 扩展 | `extension/manifest.json` | `extension/` | MV3，零构建零依赖；UI / service worker / offscreen document 三个上下文 |
| OHOS 宿主 | `ohos/entry/src/main/ets/entryability/EntryAbility.ets` | `ohos/` | ArkTS 宿主，与 Flutter 主端共享 `lib/` |
| 平台实现包 | — | `packages/` | path 依赖、不进 pub.dev，只实现某个平台的插件能力或引导层 |

Vela、Chrome 扩展与 Flutter 端**不共享代码、不共享包管理**，只共用 B 站接口协议（WBI、APP 签名、收藏夹、取流）。同一个功能在手表端与扩展端需要分别实现。

---

## 分层职责

| 层 | 目录 | 职责 |
| --- | --- | --- |
| UI | `lib/features/*/ui/`、`features/*/widgets/`、`lib/shared/widgets/`、`lib/app/shells/` | 页面、组件、横竖屏与方屏布局；不写业务逻辑 |
| 状态 | `lib/features/<feature>/*_providers.dart` | Riverpod 3.x 的 `Notifier` / `NotifierProvider`；桥接服务端 `ChangeNotifier` 的固定写法见 `features/playlist/playlist_providers.dart` |
| 编排 | `lib/features/*/logic/`、`features/*/services/` | 播放编排、漫游、局域网同步、登录、收藏同步等业务流程 |
| 领域模型 | `lib/domain/` | 纯共享数据模型（`Music`、`Playlist`、`BiliItem`、`PeerDevice`…），无 UI、无服务依赖 |
| 基础设施 | `lib/core/network/`、`lib/core/storage/` | HTTP / Cookie / WBI、SQLite 与缓存；**必须纯 Dart** |
| 视觉系统 | `lib/shared/theme/` | Palette、Token、六套主题（Lucent / Nocturne / Verdant / Gruvbox / Nord / Solarized）与运行时切换 |
| 组合根 | `lib/app/app_providers.dart` | 长生命周期服务的创建与释放 |

功能模块内部按关注面分目录（`ui/`、`widgets/`、`logic/`、`services/`、`models/`），不要求每个模块都建满这些目录——没有对应内容就不建。

按「我要改 X」找落点的速查表见 [CONTRIBUTING.md 的「代码分层」](CONTRIBUTING.md#代码分层)。

---

## 一次播放请求的路径

```text
UI / Riverpod Provider
        ↓
PlayerCoordinator  ←── RoamingService
        ↓
DualAudioService  ←── NotificationService / PiP / LAN Sync
        ↓
ApiService
        ↓
BiliClient  ←── Bilibili API
```

各层的职责边界：

- **PlayerCoordinator**（`features/player/logic/player_coordinator.dart`）：播放行为的唯一入口——播放 / 暂停 / 切歌 / 跳转、队列推进，以及与歌单、历史、漫游的联动。UI 只发命令，不直接碰播放器。
- **DualAudioService**（`features/player/logic/dual_audio_service.dart`）：A/B 双播放器 + equal-power 曲线交叉淡入淡出；音效链（均衡器、压缩器、交叉回馈、回声、立体声增强）与音频输出挂在这一层，播放状态通过 `ValueNotifier` 向上广播。
- **ApiService**（`core/network/api_service.dart`）：B 站接口语义层——取流、搜索、收藏夹、多 P、推荐等，把接口响应整理成 `domain/` 模型。
- **BiliClient**（`core/network/bili_client.dart`）：传输层——HTTP、Cookie 装配、WBI 补签、异常体系与重试预算。
- **旁路订阅**：`NotificationService`（系统媒体通知与媒体会话元数据）、`PipService`、`LanSyncService` 消费播放状态；`OfflineCacheService` 在断网时把取流回退到本地缓存。
- **数据源**：`PlaylistService` 是歌单 / 收藏 / 历史的单一数据源，UI 通过 Provider 读取，不自行维护副本。

---

## 目录结构

```text
lib/
├── main.dart                   # 入口：平台初始化 → 数据库落点预检 → 组合根 → audio_service → 窗口
├── app/
│   ├── app_providers.dart      # 组合根：所有长生命周期服务的创建与释放
│   ├── app_lifecycle.dart      # 退出顺序：摘托盘 → 收音频 → 释放容器 → 关窗口
│   └── shells/                 # 横竖屏 / 方屏外壳、导航、桌面窗口控件
├── core/                       # 无 UI 基础设施（必须纯 Dart）
│   ├── network/                # BiliClient、ApiService、CookieJar、WBI/WebTicket、Passport、异常体系
│   └── storage/                # AppDatabase(SQLite)、缓存、落点扫描 / 探查 / 搬迁
├── domain/                     # 纯共享模型：Music、Playlist、BiliItem、PeerDevice、Artist…
├── features/<feature>/         # 功能模块，内部按 ui|widgets|logic|services|models 分层
│   ├── player/                 # PlayerCoordinator、DualAudioService、音效链、通知、PiP、正在播放页
│   ├── playlist/               # 歌单 / 收藏 / 历史的单一数据源
│   ├── roam/                   # 漫游：simhash 排序、种子多样性、相似 / 平衡 / 探索策略
│   ├── lyrics/                 # 歌词检索、多源匹配与逐字渲染
│   ├── lan_sync/               # mDNS 发现、二维码配对、远程控制
│   ├── offline/                # 离线缓存：下载 / 删除 / 清理、断网取流回退
│   ├── auth/ fav_sync/         # 登录态与收藏夹导入 / 同步
│   ├── home/ search/ discover/ following/ artist/ taste/ profile/  # 首页、搜索、发现、关注、UP 主、口味画像、个人中心
│   ├── settings/ update/       # 设置（含音效与均衡器、音频输出）、更新检查与应用内更新
│   ├── diagnostics/            # 音频后端诊断页（只读采集）
│   └── storage/                # 数据库落点冲突的最小 shell（跑在 ProviderContainer 之前）
└── shared/                     # 跨模块共享：widgets/、theme/（六套主题）、utils/

bin/
├── bilimusic_tui.dart          # 终端客户端入口（纯 Dart）
└── tui/                        # mpv_player(FFI)、tui_api、app_model、probe

extension/                      # Chrome 扩展（MV3，零构建零依赖，与其余端不共享代码）
├── manifest.json
├── rules.json                  # declarativeNetRequest：给 bilibili / CDN 改写 Referer
├── scripts/                    # verify.mjs、资源生成脚本、QR 参数表 / 对照矩阵生成
└── src/
    ├── core/                   # 纯函数，无 chrome.* → Node 可直接 import 测
    ├── net/                    # 只在 service worker 里跑的请求层
    ├── auth/                   # cookies(纯) / session / 扫码登录
    ├── qr/qr_encode.js         # 手写 QR 编码器（对照 Python qrcode 逐位验证）
    ├── bg/service_worker.js    # 消息路由 / 存储 / 通知 / offscreen 生命周期（唯一写入面）
    ├── offscreen/              # offscreen.html + audio_host.js（唯一播放面）
    └── ui/                     # popup + player 全页（共用 MD3 皮肤）、shared/store.js（唯一读取面）、vendor/

vela/                           # 小米 Vela JS 快应用（独立 npm 工程）
├── src/
│   ├── app.ux                  # 启动自举：控制类音频事件绑定 + 登录态 / 播放态恢复
│   ├── manifest.json           # features 与 config.background.features 后台运行声明
│   ├── common/                 # 纯函数：config / parse / volume / playstate / favorites / fetchbridge…
│   ├── services/               # session / api / playerService / audioCache / biliApi / authService…
│   └── pages/                  # player / more / recommend / fav / favDetail / localfav / login / volume / about
├── scripts/                    # verify.mjs + aiot-hooks 与 @system.* 桩（仅离线测试用）
└── README.md                   # Vela 端完整文档

ohos/                           # OpenHarmony / HarmonyOS 宿主（与 Flutter 主工程共享 lib/）
├── AppScope/app.json5          # bundleName / 版本号 / 图标
├── entry/src/main/module.json5 # requestPermissions + backgroundModes(audioPlayback)
├── entry/src/main/ets/         # EntryAbility、Index 页、GeneratedPluginRegistrant（生成，已 gitignore）
├── build-profile.json5.example # 本机签名材料不进仓库
└── README.md                   # OHOS 端完整文档

packages/                       # 本仓库自带的平台实现 / 引导层（path 依赖，不进 pub.dev）
├── audio_service_ohos/         # implements audio_service + platforms.ohos
├── share_plus_ohos/            # implements share_plus + platforms.ohos
├── audio_session/              # 上游整包 vendored（无平台接口层）
└── mpv_audio_kit_ohos/         # libmpv 引导层（纯 FFI）

tool/                           # ohos_build.ps1、ohos_libmpv 交叉编译脚本、network_smoke、db_schema_check
test/                           # 单元 / 组件测试，按关注面分目录
```

---

## 启动与退出顺序

### 启动（lib/main.dart）

顺序本身就是契约，改动需谨慎。`main()` 先完成 `WidgetsFlutterBinding` 与 SnowNLP 资源加载，然后分两条路：OHOS 在桌面 / 移动初始化之前就分流到 `_bootstrapOhos()`——先 `runApp` 一个不依赖任何插件的启动壳，再走同一套 `_bootstrapApp(ohos: true)`，插件与 libmpv 的异常落在启动壳上；其余平台走下面这条常规路径。

1. **平台分支初始化 SQLite**：桌面端 `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`，并注入 `AppDatabase.directoryResolver`（`getApplicationSupportDirectory`）；Android / iOS 不注入，走原生 `getDatabasesPath()`。
2. **数据库落点预检**（`_resolveDatabasePlacementIfNeeded()`）：排在窗口和 App 之前。盘上不止一份能读的库时，先 `runApp` 一个只挂弹窗的最小 shell，用户选完归档落败副本并重启进程；没有冲突立即返回。详见[本地存储与数据库落点](#本地存储与数据库落点)。
3. **网络配置**：注入 `NetworkConfig.cookieLoader / cookieSaver`（SharedPreferences 键 `cookies`）→ `NetworkConfig.init(waitForBootstrap: false)`。只等读盘与旧格式迁移，设备自举放后台，不要改成 `await`。
4. **播放引擎**：`MpvAudioKit.ensureInitialized()`（OHOS 为 `MpvAudioKitOhos.ensureInitialized()`），位置保持在 `ProviderContainer` 之前——`dualAudioServiceProvider` 会创建 Player。
5. **组合根**：创建 `ProviderContainer` → 读 `playerCoordinatorProvider` 触发依赖图 → 读 `audioFocusServiceProvider` 让音频焦点在首播前就绪。
6. **播放列表**：`playlistService.initialize()` 刻意不 `await`；`AppDatabase.instance.migrateFromPrefsOnce()` 同样 `unawaited`（它内部要开库，可能还要先搬库）。两者都不阻塞窗口，启动顺序因此是「窗口先出来 → 库打开 → 列表填充」；cid 回填挂在 `playlistReady.then(...)` 上。
7. **音频服务与窗口**：`AudioService.init(...)` → `notificationService.initialize(audioHandler)` → 桌面窗口 / 托盘 → `runApp(UncontrolledProviderScope(...))`。

> [!IMPORTANT]
> 不要在 `runApp` 之前 `await` 开库或搬库：这会把窗口的出现推迟到磁盘操作之后，用户看到的是无响应启动。

### 退出（lib/app/app_lifecycle.dart）

退出只有一个入口 `AppLifecycleManager.quit()`，顺序是**摘托盘 → 停音频并释放系统媒体会话 → 释放 Provider 容器 → 解除关闭拦截 → 关窗口**。两个要点：

- 音频必须在容器之前收尾：handler 由容器里的服务驱动。
- 容器 `dispose()` 会触发 `app_providers.dart` 中所有 `ref.onDispose`，所以服务不要各自再挂退出回调。

---

## 网络与登录态

- **唯一事实来源**是 `NetworkConfig.cookieJar`（`core/network/cookie_jar.dart`），按 RFC 6265 语义决定每个请求带哪些 Cookie。`BiliClient` 对每个响应 `jar.ingest(...)` 回收 `Set-Cookie`，`bili_jct` 自动当写接口的 `csrf`。
- **出站请求头只有一个装配入口**：`NetworkConfig.headersFor(uri)`。封面、头像这类不区分目标域名的请求走 `NetworkConfig.biliHeaders`，不要在别处手写 `Cookie` 头。
- **设备自举**（`BiliBootstrap`）：补 `_uuid` / `b_lsid` / `b_nut` → `/x/frontend/finger/spi` 取 buvid → GenWebTicket 换 `bili_ticket` 与 WBI 口令 → 访问一次主站激活 buvid。失败只记录原因，不阻塞启动。
- **WBI 按需签名**：调用方显式 `signed: true` 才签；撞风控（`-352` / `-412` / HTTP 412）且当次未签名时，刷新口令并补签重试一次，不走传输层重试预算。口令缓存 6 小时。
- **重试边界**：传输层只重试超时、连接失败、408、429 与 5xx；412 交给补签链路，304 应当带 `Cache-Control: no-cache` 重取。
- **异常三类**：`BiliApiException`（HTTP 200 但业务码非 0）、`BiliNetworkException`（传输层）、`BiliParseException`（响应不是预期 JSON），统一 `on BiliException` 兜住。
- **登录态落盘**：Cookie 由 `CookieJar` 序列化进 SharedPreferences；`refresh_token` 单独由 `PassportStore` 保存。登出先调服务端接口，失败时 UI 提供「强制退出登录」，只清本地会话 Cookie（保留 buvid3 / buvid4 / b_nut / bili_ticket / `_uuid` / `b_lsid`）。
- **TUI 复用**：TUI 只注入 `cookieLoader`（读桌面 App 的 `shared_preferences.json`），不注入 saver，所以它只能读登录态，不会覆盖 App 的会话。

---

## 本地存储与数据库落点

- **SQLite**：数据库访问都经 `AppDatabase`（`core/storage/database.dart`），歌单、收藏、历史都在 `playlist.db`。设置走 `shared_preferences`，网络资源与歌词走缓存（`CacheManager`），歌曲可另存为离线缓存。
- **桌面端落点不变量**：数据库必须落在应用数据目录，不能跟着 `Directory.current` 走。`sqflite_common_ffi` 的默认落点是相对 cwd 的 `.dart_tool/sqflite_common_ffi/databases`，换个启动方式就会静默读到另一个空库。
- **盘上不止一份库时**：判据只有「数一数盘上有几份非空主库」，出口三个：

```text
0 份  → 应用数据目录新建
1 份  → 不在应用数据目录就搬过去，然后打开
≥2 份 → 逐份只读探查行数
        ├ 只有一份读得出来 → 其余改名归档，回到「1 份」
        └ 不止一份读得出来 → 弹窗让用户选一份 → 落败的改名归档 → 重启进程
```

- **只归档、不删除**：落选副本整组改名成 `playlist.db.bak-<时间戳>`（含 `-wal` / `-shm` / `-journal`）留在原目录；同名时加序号，绝不覆盖上一份归档。扫描只 `stat` 不开库，探查先把整组拷进系统临时目录再只读打开。
- **两条不变量**（改搬迁 / 开库代码时别破）：
  - `AppDatabase.database` 必须单飞：`playlistService.initialize()` 与 `migrateFromPrefsOnce()` 会并发进来，要缓存「在飞的那次」，而不是只判 `_db != null`。
  - 搬迁失败后绝不返回一个没有库的落点：回滚后按「哪边真的有一份非空主库」决定这次开哪个目录，否则调用方会在空目录里就地建出一个空壳库。
- **决策记录就是文件系统**：没有指纹、没有启动闸门。归档后盘上只剩一份，「上次选了哪份」由新进程重扫回答。

---

## 平台差异

| 平台 | 本地存储 | 音频后端 | 备注 |
| --- | --- | --- | --- |
| Windows / Linux / macOS | `sqflite_common_ffi` | `mpv_audio_kit`（libmpv） | 构建期自动下载 libmpv 并随产物打包；数据库落应用数据目录 |
| Android | `sqflite` | `mpv_audio_kit`（libmpv） | Release 按 ABI 拆分 APK |
| OpenHarmony / HarmonyOS | `sqflite`（`sqflite_ohos` → relational_store） | `mpv_audio_kit` + `packages/mpv_audio_kit_ohos` | 共享 `lib/`；libmpv 由 `tool/ohos_libmpv` 交叉编译，加载失败退占位播放器 |
| 小米 Vela | — | `@system.audio` | 独立 JS 快应用；跨 VM 共享态见 `vela/README.md` |
| Chrome 扩展 | `chrome.storage` | offscreen document 的 `<audio>` | MV3 下 service worker 不能播音，offscreen 只负责播放 |

`packages/` 下四个包的分工：

| 包 | 类型 | 说明 |
| --- | --- | --- |
| `audio_service_ohos` | 联邦化平台实现 | `implements audio_service` + `platforms.ohos`，纯 ArkTS，Dart 侧零胶水 |
| `share_plus_ohos` | 联邦化平台实现 | 同上，ArkTS 认官方 SPI 的 `share` |
| `audio_session` | 整包 vendored | 上游无平台接口层，只能整包替换并保留 path override |
| `mpv_audio_kit_ohos` | FFI 引导层 | 补 libmpv 定位与 `setlocale(LC_NUMERIC, "C")`，无平台接口层 |

> OHOS 构建统一走 `tool/ohos_build.ps1`，不要用裸 `flutter pub get`（pub 缓存与工程不同盘会让 hvigor 报 `srcPath` 不是相对路径）。

---

## 架构约束

以下边界在 code review 会直接打回，完整清单见 [CONTRIBUTING.md 的「硬性规则」](CONTRIBUTING.md#硬性规则)：

1. `lib/core/` 保持纯 Dart，平台能力由宿主注入钩子。
2. 长生命周期服务只在 `app/app_providers.dart` 创建与释放；UI 只消费 Provider。
3. UI 状态 Provider 放 `features/<feature>/*_providers.dart`，用 Riverpod 3.x 的 `Notifier` / `NotifierProvider`。
4. 新文件按分层落位；纯共享模型放 `domain/`；可测逻辑写成纯 Dart 类，不绑 UI。
5. 出站请求头只经 `NetworkConfig.headersFor(uri)`，不手写 `Cookie` 头。
6. 数据库落点与搬迁逻辑不做「顺手简化」，改动要让 `test/storage/` 的回归测试通过。
7. Vela、Chrome 扩展与 Flutter 端不共享代码与包管理；改动分别走 `npm run verify` 与 `node extension/scripts/verify.mjs`。
8. 平台实现优先用联邦化插件（`packages/<x>_ohos`），没有平台接口层才整包 vendored。

---

## 相关文档

- [README.md](README.md) —— 项目介绍、安装与使用。
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 开发环境、分支与 CI、提交规范、硬性规则、测试。
- [vela/README.md](vela/README.md) —— 手表端设计目标、跨 VM 语义与排查表。
- [extension/README.md](extension/README.md) —— 扩展的三上下文、权限与真机验证清单。
- [ohos/README.md](ohos/README.md) —— 依赖接线表、构建变量与排错表。
- [SECURITY.md](SECURITY.md) —— 安全策略与漏洞上报。
