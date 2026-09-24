# 贡献指南

感谢你愿意为 BiliMusic 花时间。

若你想以非提交代码方式帮助 BiliMusic 项目，你可以在 Discussions / Issues 中提建议、问题或功能请求。

> [!NOTE]
> 仓库还有几份面向不同读者的文档，按需查阅：
> - [`README.md`](README.md) —— 项目介绍、安装与使用说明。
> - [`SECURITY.md`](SECURITY.md) —— 安全策略、漏洞上报通道与「贡献者须知」。
> - [`vela/README.md`](vela/README.md) —— 小米 Vela 手表端的完整文档。

---

## 目录

- [从哪里开始](#从哪里开始)
- [沟通约定](#沟通约定)
- [开发环境](#开发环境)
- [分支模型与 CI](#分支模型与-ci)
- [提交规范](#提交规范)
- [提交前检查清单](#提交前检查清单)
- [代码分层](#代码分层)
- [硬性规则](#硬性规则)
- [测试](#测试)
- [Vela 手表端](#vela-手表端)
- [版本号与更新日志](#版本号与更新日志)
- [安全与隐私底线](#安全与隐私底线)
- [Pull Request 流程](#pull-request-流程)
- [许可证与贡献授权](#许可证与贡献授权)

---

## 从哪里开始

| 想做的事 | 去哪里 |
| --- | --- |
| 报告可以稳定复现的缺陷 | [开 Issue](https://github.com/NaivG/bilimusic/issues/new/choose)（Bug 报告模板会引导你补齐平台与版本） |
| 提新功能或改进建议 | [Discussions → Ideas](https://github.com/NaivG/bilimusic/discussions/categories/ideas)，或 Issue 的「功能请求」模板 |
| 提问、交流用法、分享玩法 | [Discussions](https://github.com/NaivG/bilimusic/discussions)（分类见 README 的[社区与讨论](README.md#社区与讨论)） |
| 报**安全漏洞** | **不要**开公开 Issue，走 [`SECURITY.md`](SECURITY.md) 的[私密漏洞报告](https://github.com/NaivG/bilimusic/security/advisories/new) |
| 提交代码 | 往下读本文；大改动请先开 Issue / Discussion 对齐设计 |
| 看版本计划与进度 | [BiliMusic 路线图](https://github.com/NaivG/bilimusic/discussions/29) |

> [!TIP]
> 发帖前**先搜索**现有 Issue 与 Discussion；也**不要**在公开帖子里粘贴 Cookie、账号信息等敏感数据。

---

## 沟通约定

- **中文交流即可**，与仓库现有文档、注释、提交信息保持一致。
- **本项目不做逆向、修改、破解**：不提供视听内容，不接受绕过平台风控、破解会员权益、下载视频流一类的改动或请求。定位是「把 B 站当音乐内容源」的播放器——搜索、整理、播放、漫游、同步。
- **已是既定结论的方向不再重复讨论**：不考虑对接第三方音乐平台的歌曲元数据匹配（内容差距大、性价比过低）。
- **维护者是业余时间在做这件事**：Issue / PR 的回复可能不及时，请保持耐心；也请把问题描述得足够完整，减少来回追问。

---

## 开发环境

| 组件 | 要求 | 说明 |
| --- | --- | --- |
| Flutter | 3.47.x | 项目基于 Flutter 3.47.x 开发 |
| Dart SDK | `^3.13.0` | 见 `pubspec.yaml` 的 `environment` |
| Node.js | 仅改动 `vela/` 时需要 | 手表端是独立 JS 快应用，走 `npm` |
| 平台工具链 | 按目标平台 | Windows 需 VS 桌面 C++ 工作负载；Android 需 Android SDK；Linux 见下 |

```bash
git clone https://github.com/NaivG/bilimusic.git
cd bilimusic
flutter pub get
flutter run -d <device-id>     # 不带 -d 则用默认设备
```

Linux 首次构建若缺托盘依赖：

```bash
sudo apt install libgtk-3-dev libx11-dev libxi-dev
```

> libmpv 不需要预装：播放引擎 `mpv_audio_kit` 会在构建期自动下载并随产物打包。

**Vela 手表端**（只在改动 `vela/` 时需要）：

```bash
cd vela
npm install        # 仅首次
npm run verify     # 离线自检，纯 Node，不需要设备或模拟器
```

> [!WARNING]
> 不要提交 `build/` 与任何构建产物（`.gitignore` 已忽略）；也不要提交 Cookie、账号信息等敏感数据——见[安全与隐私底线](#安全与隐私底线)。

---

## 分支模型与 CI

- **`dev` 是开发主线**：所有 PR 的目标分支都是 `dev`，日常 CI 也挂在它上面。
- **`main` 只承载发布**：不要直接向 `main` 推送改动。
- 从 `dev` 切工作分支，命名用 `<类型>/<简短描述>`，与仓库既有的 `refactor/audio-engine`、`refactor/code-structure` 同构：`feat/xxx`、`fix/xxx`、`refactor/xxx`、`docs/xxx`。

CI 现状（`.github/workflows/`）：

| 工作流 | 触发条件 | 做什么 |
| --- | --- | --- |
| `dart_analyze.yml` | push / PR 到 `dev` | 跑 `dart analyze --no-fatal-warnings`，再跑 `dart format .`；若格式化产生 diff，**由机器人以 `Format code for <sha>` 直接提交推回** |
| `release_build.yml` | push 到 `main`、推送 `v*` 标签、手动触发 | 生成版本号 → 多平台构建（含 Vela RPK）→ 汇总发布 |

---

## 提交规范

采用 **Conventional Commits + 中文描述**：

```text
<type>(<scope>): <中文描述>
```

| type | 用途 |
| --- | --- |
| `feat` | 新功能 |
| `fix` | 缺陷修复 |
| `refactor` | 重构（不改变外部行为） |
| `perf` | 性能优化 |
| `docs` | 文档 |
| `test` | 测试 |
| `chore` | 构建、依赖、CI 等杂项 |
| `style` | 纯格式调整 |

- **scope** 用改动所在的模块或目录名（`player`、`network`、`settings`、`update`…）。
- **Vela 端**用 `vela` 或子模块，保持与 Flutter 端同构，如 `feat(vela): …`、`fix(vela/playerService): …`、`docs(vela): …`。
- 描述写「做了什么」，一行说清；需要解释「为什么」时写在提交正文里。

> [!IMPORTANT]
> **提交前必须 `dart format .`**：仓库的格式化以 CI 里的 `dart format .` 为准。改动 `vela/` 时提交前先 `cd vela && npm run verify`。

---

## 提交前检查清单

**Flutter 主项目**：

```bash
dart format .                        # 必须先跑
dart analyze --no-fatal-warnings     # CI 用的就是这条
flutter test                         # 全量测试
flutter build windows                # 至少构建你改动涉及的平台：windows|linux|apk|macos|ios
```

当前仓库基线与期望结果：

| 命令 | 期望 |
| --- | --- |
| `dart analyze --no-fatal-warnings` | 退出码 0。仓库当前基线有 **34 条 `info` 级 lint**（`prefer_initializing_formals`、`deprecated_member_use`、`sized_box_for_whitespace` 等既有问题）；CI 不因此失败，但**不要新增** error / warning / 新的 info |
| `dart format .` | 被跟踪的源码无 diff。（`build/` 下的第三方生成物会被顺带重排，但 `build/` 已被 gitignore、不参与提交，可以忽略） |
| `flutter test` | 330 个用例全部通过 |
| `flutter build <平台>` | 构建成功 |

> [!NOTE]
> `flutter analyze`（不带 `--no-fatal-warnings`）会因为上面那 34 条 `info` 返回退出码 1——这是既有基线，不是你的改动造成的。以 CI 同款命令 `dart analyze --no-fatal-warnings` 为准，也**不要**为这 34 条无关问题顺手改动。

**Vela 手表端**（只要动过 `vela/` 就必须跑）：

```bash
cd vela
npm run verify     # 期望：通过 770 项，失败 0 项
```

改完网络层、播放状态同步或 `manifest.json`，**必须先跑它再上真机**。

**PR 前自查**：

- [ ] 改动聚焦，没有夹带无关重构或整文件格式化
- [ ] 新增 / 修改的逻辑有对应测试（见[测试](#测试)）
- [ ] 触及平台原生工程（`android/`、`ios/`、`windows/`、`linux/`、`macos/`）的改动已在对应平台实测
- [ ] 没有提交凭据、`build/`、编辑器私有文件
- [ ] 目标分支是 `dev`

---

## 代码分层

一次播放请求的路径——动手前先确认自己在哪一层：

```text
UI / Riverpod Provider → PlayerCoordinator → DualAudioService → ApiService → BiliClient → Bilibili API
```

| 层 | 目录 | 职责 |
| --- | --- | --- |
| UI | `lib/features/*/ui/`、`lib/shared/widgets/`、`lib/app/shells/` | 页面与组件，**不写业务逻辑** |
| 状态 | `lib/features/<feature>/*_providers.dart` | Riverpod 3.x 的 `Notifier` / `NotifierProvider` |
| 编排 | `lib/features/*/logic/`、`services/` | 播放编排、漫游、局域网同步、登录等流程 |
| 领域模型 | `lib/domain/` | 纯共享数据模型（无 UI、无服务依赖） |
| 基础设施 | `lib/core/` | 网络与存储，**必须纯 Dart** |
| 视觉系统 | `lib/shared/theme/` | Palette、Token、主题注册与切换 |
| 组合根 | `lib/app/app_providers.dart` | 长生命周期服务的创建与释放 |

「我要改 X，该去哪」：

| 想改的东西 | 落点 |
| --- | --- |
| 界面 / 交互 | `lib/features/<feature>/ui/` 或 `widgets/` |
| 页面状态 | `lib/features/<feature>/*_providers.dart` |
| 业务编排 | `lib/features/<feature>/logic/`、`services/` |
| B 站接口 / 请求头 / Cookie / 签名 | `lib/core/network/`（纯 Dart，不能 import Flutter） |
| 数据库 / 缓存 / 落点搬迁 | `lib/core/storage/`（对应 `test/storage/`） |
| 主题与视觉 | `lib/shared/theme/` |
| 终端客户端 | `bin/bilimusic_tui.dart` 与 `bin/tui/`（复用 `lib/core/network`） |
| 手表端 | `vela/`（独立 JS 快应用，与主项目不共享代码） |

> [!NOTE]
> 新增可测逻辑优先写成**纯 Dart 类 / 纯函数**，放在 `logic/`、`core/` 或 `vela/src/common/`，不要绑到 UI 上——只有这样它才能被 `flutter test` / `npm run verify` 覆盖。

---

## 硬性规则

以下是 review 会直接打回的规则，动手前建议把相关那条读一遍。

1. **`lib/core/` 保持纯 Dart**：禁止 import Flutter 及任何 Flutter 插件。core 层要被 TUI / CLI 宿主复用，平台能力由宿主注入钩子（如 `NetworkConfig.cookieLoader / cookieSaver`）。
2. **长生命周期服务只在 `lib/app/app_providers.dart` 创建与释放**：依赖用 `ref.watch` 声明，资源用 `ref.onDispose` 释放。UI 只消费 Provider，禁止直接实例化 Manager / Service。
3. **UI 状态 Provider 放 `features/<feature>/*_providers.dart`**：用 Riverpod 3.x 的 `Notifier` / `NotifierProvider`；桥接服务端 `ChangeNotifier` / `ValueNotifier` 的固定写法见 `features/playlist/playlist_providers.dart`。
4. **`AnimatedSwitcher` 的 `transitionBuilder` 必须用 `switcherFadeTransition`**（`lib/shared/utils/animations.dart`）：子树 key 固定或为 null 时，默认 builder 会挂 `ValueKey(child.key)`，触发 `Duplicate keys found` 断言。
5. **出站请求头只有一个装配入口**：`NetworkConfig.headersFor(uri)`。**不要手写 `Cookie` 头**，也不要新增绕过它的请求路径。
6. **数据库落点与搬迁逻辑不要「顺手简化」**：`lib/core/storage/` 的扫描、冲突处置、搬迁顺序都是踩过事故后的现场结论；改动请同步更新 `test/storage/` 下的回归测试，尤其别破坏那两条不变量（`AppDatabase.database` 单飞、搬迁失败后不返回空落点）。
7. **版本号改动必须同步两处**：`pubspec.yaml`（`version: x.y.z+build`）与 `assets/version.json`（`version` + `changelog` 条目）。只改一处会让应用内更新判断错乱，详见[版本号与更新日志](#版本号与更新日志)。
8. **禁止提交**：Cookie、账号信息、`build/`、任何构建产物与敏感数据。
9. **不要整项目关闭 lint 规则**：`analysis_options.yaml` 保留 `flutter_lints`；确需例外时用**行级** `// ignore:` 抑制。

---

## 测试

现有测试位于 `test/`（共 30 个文件、330 个用例），按关注面分子目录：`network/`、`storage/`、`player/`、`offline/`、`sync/`、`settings/`、`lyrics/`、`shell/`。

**什么时候必须补测试**：

| 改动 | 要求 |
| --- | --- |
| `lib/core/network/` | 先跑 `flutter test test/network/`。写纯 Dart 测试，**注入固定时钟与内存 loader / saver**，不要依赖真实网络 |
| `lib/core/storage/` 的落点与搬迁 | 补 `test/storage/`，覆盖并发开库、搬迁失败回退这类不变量 |
| 新增纯逻辑（解析、排序、编解码、状态归并、设置序列化） | 就地补单元测试 |
| 播放编排 / 离线缓存 / 局域网同步 | 补 `test/player/`、`test/offline/`、`test/sync/` 下的对应用例 |
| `vela/` 手表端 | 断言写进 `vela/scripts/verify.mjs`（`npm run verify`） |

**写法要求**：

- 跑全量用 `flutter test`。
- 需要替换依赖时用 `ProviderContainer(overrides: [...])` —— 这正是组合根设计的意图。
- 可测逻辑写成纯 Dart 类；不要把测试绑到真实 UI 或真实网络上。

---

## Vela 手表端

`vela/` 是与 Flutter 主项目**并列**的小米 Vela JS 快应用手表端：两者**不共享代码、不共享包管理、不共享依赖清单**，仅共用 B 站接口协议。

- 手表端走 `npm`，**不要**在 `vela/` 里跑 `flutter pub`。
- 改动 Flutter 端**不会**同步到手表端，反之亦然——同一功能两边要分别实现。
- 分层与主项目同构：`common/`（纯函数，无 `@system` 依赖，可被 Node 单测）、`services/`（有状态服务）、`pages/`（每页一个独立 JS VM）。
- 提交前最低要求：`cd vela && npm run verify` 全部通过。
- 真机调试用 `npm run start`（AIoT-IDE）；构建 RPK 用 `npm run build`。

手表端最容易踩的坑，动手前请先读 [`vela/README.md`](vela/README.md) ：

| 主题 | 一句话规则 |
| --- | --- |
| 跨 VM 共享 | 每个 page 一个独立 JS VM，模块级变量不跨页共享；播放状态必须落盘到 `@system.storage` 的 `bilimusic_play_state`，各 VM 自己读回；并发写**只改自己改过的字段，绝不整份覆盖** |
| 后台运行 | 后台接口必须**同时**写进 `manifest.json` 的最外层 `features` 与 `config.background.features`，且在 `app.ux` 里实际使用；**改完必须 `npm run build` 重装 RPK**——热更新不会替换已安装包的声明，漏了这条就是真机「回主页就停播」 |
| 事件绑定 | app VM 只绑控制类（`onended` / `onprevious` / `onnext`），常驻主页 VM 只绑展示类；两边不重叠，临时页面一律不绑 |
| 播放队列 | 收藏夹 / 官方推荐只是**选歌来源**，与队列解耦：单曲走 `playTrackNow`，连播整个来源走 `setQueue`；来源页绝不整份替换队列 |
| 页面栈 | 临时页面（登录等）只 `router.back()`，不 push / replace 别的页；「播放全部回播放器」走固定步数 `back({step:n})`，栈里多一层就整体带偏 |
| 音量 | 只认 `@system.volume`；音量不进共享态、不落盘、不写 `audio.volume` |
| 版本号 | `src/manifest.json` 的 `versionName` / `versionCode` **由 Release CI 强制改写**，不要当手工发布项；本地值只是快照 |

---

## 版本号与更新日志

只在发版、或你的改动需要并入新版本时才动版本号，并且**必须同步两处**：

| 文件 | 改什么 |
| --- | --- |
| `pubspec.yaml` | `version: x.y.z+build`（`+build` 是构建号） |
| `assets/version.json` | `version` 字段，以及 `changelog` 数组新增一条条目 |

`assets/version.json` 被 `features/update/update_checker.dart` 拉取做应用内更新比较，同时也是「设置 → 更新日志」的数据源。条目按现有风格写：

```json
{
  "version": "1.10.1",
  "date": "2026-09-24",
  "changes": [
    "新增……",
    "修复……",
    "重构……"
  ]
}
```

- 更新检测只比较 `major.minor.patch`，忽略 `+build`。
- **Vela 端例外**：`vela/src/manifest.json` 的 `versionName` / `versionCode` 不需要跟手改——Release CI 出包前会用 `MAIN_VERSION`（pubspec 主版本号）与 `BUILD_VERSION`（提交数）强制改写它们，改写发生在 `npm run verify` 与 `npm run release` 之前。

---

## 安全与隐私底线

完整策略、范围界定与上报通道见 [`SECURITY.md`](SECURITY.md)。作为贡献者，这几条是底线：

1. **不提交任何凭据**：Cookie、`SESSDATA`、`refresh_token`、账号密码、设备指纹，以及含上述内容的日志或抓包文件。
2. **出站请求只有一个装配入口**：`NetworkConfig.headersFor(uri)`；不要手写 `Cookie` 头，也不要新增绕过它的请求路径。
3. **新增出站目标必须显式评审**：把数据发往 B 站及其 CDN 之外的域名（尤其是任何遥测、统计、错误上报服务）属于需要讨论的变更，不能顺手加上。
4. **新依赖需评估**：引入新的 pub / npm 依赖时请说明来源与用途；Vela 端不要引入与主项目无关的依赖。
5. **更新链路不得放宽校验**：`assets/version.json` 与 Release 解析、下载、校验、替换的链路是攻击面，改动请附带测试。

> [!IMPORTANT]
> 安全漏洞**不要**开公开 Issue，请走 [私密漏洞报告](https://github.com/NaivG/bilimusic/security/advisories/new)。公开披露会让所有用户在修复前的这段时间里处于风险中。

---

## Pull Request 流程

1. **大改动先对齐设计**：开一个 Issue 或在 [Discussions → Ideas](https://github.com/NaivG/bilimusic/discussions/categories/ideas) 说明动机与方案，避免写完之后才发现方向不一致。
2. **从 `dev` 切分支**：`git switch -c feat/your-feature dev`。
3. **完成改动**，跑完[提交前检查清单](#提交前检查清单)，按[提交规范](#提交规范)提交。
4. **向 `dev` 开 PR**，描述里写清：
   - 这个改动解决什么问题（有关联 Issue 请带上编号）/ 添加什么功能
   - 改动范围与关键实现选择
   - **怎么验证的**：跑了哪些测试、在哪个平台 / 设备上实测过
   - UI 相关改动附前后对比截图（横屏、竖屏 / 方屏布局都可能受影响）
5. **评审**：维护者可能要求补测试、拆提交或调整分层落位，请保持改动聚焦。
6. **合并**：以 merge commit 并入 `dev`。若分支已落后，先同步 `dev`、解决冲突并重跑检查清单。

> [!IMPORTANT]
> PR 在有人审核（review）后，请不要进行 force push(`git push -f`)，否则将可能会导致审核人需要重新审核你的全部代码。

---

## 许可证与贡献授权

- 本项目采用 [GNU Affero General Public License v3.0](LICENSE)。**你提交的代码将以 AGPL-3.0 授权**；提交 PR 即表示你同意这一点，并确认你对所提交内容拥有相应权利。
- **仅供学习交流，不得用于任何商业用途。** 引入第三方代码或资源时，请确认其许可证与 AGPL-3.0 兼容，并在 PR 中说明来源与许可证。
- 项目图标采用 [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)，请勿用于商业场景。

