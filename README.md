<div align="center">
  <img src="./assets/ic_launcher.png" alt="BiliMusic logo" width="120" />
  <h1>BiliMusic</h1>
  <p><strong>把哔哩哔哩里的声音，整理成一张属于你的播放桌面。</strong></p>
  <p>基于 Flutter 的 B 站音乐播放器 · 跨平台 · 漫游发现 · 局域网同步</p>

  <p>
    <a href="https://github.com/NaivG/bilimusic/releases"><img src="https://img.shields.io/github/v/release/NaivG/bilimusic?label=release&sort=semver" alt="Latest release"></a>
    <a href="https://github.com/NaivG/bilimusic/stargazers"><img src="https://img.shields.io/github/stars/NaivG/bilimusic?style=flat" alt="Stars"></a>
    <a href="https://github.com/NaivG/bilimusic/network/members"><img src="https://img.shields.io/github/forks/NaivG/bilimusic?style=flat" alt="Forks"></a>
    <a href="https://github.com/NaivG/bilimusic/issues"><img src="https://img.shields.io/github/issues/NaivG/bilimusic" alt="Issues"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License"></a>
    <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter"></a>
    <a href="https://riverpod.dev/"><img src="https://img.shields.io/badge/State-Riverpod-3D5AFE?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMDAgMTAwIj48Y2lyY2xlIGN4PSI1MCIgY3k9IjUwIiByPSI0NSIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJ3aGl0ZSIgc3Ryb2tlLXdpZHRoPSI4Ii8+PC9zdmc+" alt="Riverpod"></a>
  </p>
</div>

<br/>

> [!IMPORTANT]
> BiliMusic 仅供学习交流使用，不得用于任何商业用途。项目只提供音频播放能力，不提供任何视听内容；音乐及视频内容的版权归原作者所有，请尊重版权并合理使用。
>
> 由于不可抗拒力，请勿在其他平台宣传或讨论本项目。

<div align="center">
  <sub>如果这个项目对你有帮助，欢迎 ⭐ Star 支持一下！</sub>
</div>

---

## 目录

<!-- TOC -->
- [目录](#目录)
- [项目速览](#项目速览)
- [核心特性](#核心特性)
- [平台支持](#平台支持)
- [快速开始](#快速开始)
  - [方式一：直接安装](#方式一直接安装)
  - [方式二：从源码运行](#方式二从源码运行)
  - [构建发布版本](#构建发布版本)
- [使用路径](#使用路径)
- [登录与数据](#登录与数据)
- [技术架构](#技术架构)
  - [一次播放请求的路径](#一次播放请求的路径)
  - [分层职责](#分层职责)
- [代码导航](#代码导航)
  - [主要依赖](#主要依赖)
- [开发命令](#开发命令)
- [参与贡献](#参与贡献)
- [许可证](#许可证)
- [致谢](#致谢)
- [Star History](#star-history)
<!-- /TOC -->

---

## 项目速览

BiliMusic 是一个基于 Flutter 的哔哩哔哩音乐播放器，面向 Windows、Linux、Android、macOS 以及实验性的 Web 平台。它不试图复制一个内容平台，而是专注于三件事：

| | |
| --- | --- |
| **发现** | 搜索 B 站视频、`BV` / `AV` 号；首页推荐、猜你喜欢与播放历史；漫游模式按相似 / 平衡 / 探索策略扩展队列。 |
| **整理** | 本地歌单、收藏、历史；从 B 站收藏夹一键导入；支持跨平台数据迁移。 |
| **沉浸播放** | 双播放器交叉淡入淡出、动态歌词、封面主色主题、后台与系统媒体通知、局域网多设备同步。 |

---

## 核心特性

<details>
<summary><strong>发现与推荐</strong></summary>

- 支持 `BV` 号、`AV` 号与关键词搜索
- 首页：推荐、猜你喜欢、播放历史
- 基于 simhash 的相关度排序与漫游补队列
- 三种漫游风格：**相似** / **平衡** / **探索**
</details>

<details>
<summary><strong>播放体验</strong></summary>

- 播放 / 暂停 / 上一首 / 下一首 / 进度跳转
- 多 P 视频切换、顺序 / 随机 / 单曲循环
- A/B 双播放器 + equal-power 曲线的交叉淡入淡出
- 后台播放、系统媒体通知、音量持久化
- 动态歌词：自动匹配、逐字点亮、辉光效果
- 主题系统：Lucent / Nocturne / Verdant，运行时切换并按封面主色适配
</details>

<details>
<summary><strong>整理与同步</strong></summary>

- 本地歌单：创建、编辑、删除、拖拽排序、滑动删除
- B 站收藏夹导入并跟踪同步状态
- mDNS 局域网发现 + TCP 二维码配对 + 远程播放控制
- 支持手表、折叠屏外屏与近方形 PiP 窗口布局
</details>

---

## 平台支持

| 平台 | 状态 | 备注 |
| --- | --- | --- |
| **Windows** 10+ | ✅ 稳定 | 解压即用 |
| **Linux** | ✅ 稳定 | Ubuntu 20.04+ 或主流发行版；需要 `libmpv-dev` |
| **Android** 8.0+ | ✅ 稳定 | 按设备架构选择 APK（`arm64-v8a` / `armeabi-v7a` / `x86_64`） |
| **macOS 10.15+** | 🧪 测试中 | 可从源码构建 |
| **iOS 13+** | 🧪 测试中 | 可从源码构建无签名版本 |
| **Web** | ⚠️ 实验性 | 解压后部署到 Web 服务器，需配置 CORS |

---

## 快速开始

### 方式一：直接安装

前往 [Releases](https://github.com/NaivG/bilimusic/releases) 下载对应平台的最新版本，解压运行即可。

```bash
# Linux 用户需要先安装依赖
sudo apt install libmpv-dev
```

### 方式二：从源码运行

**环境要求：** Flutter 3.x · Dart SDK ^3.8.1

```bash
git clone https://github.com/NaivG/bilimusic.git
cd bilimusic
flutter pub get
flutter run               # 默认设备
flutter run -d <device-id> # 指定设备
```

### 构建发布版本

```bash
flutter build windows
flutter build linux
flutter build apk
flutter build web
flutter build macos
flutter build ios
```

---

## 使用路径

```
搜索内容 → 加入歌单 → 开始播放 → 匹配歌词与主题 → 漫游扩展 → 局域网同步
```

**常用入口**

| 入口 | 用途 |
| --- | --- |
| 首页 | 推荐、猜你喜欢、播放历史 |
| 搜索 | 查找 B 站音乐内容 |
| 歌单 | 管理本地歌单与导入的收藏夹 |
| 个人中心 | 用户信息、收藏、历史、漫游、设备同步 |
| 设置 | 主题、外观、播放、缓存等偏好 |

**漫游模式**
1. 在个人中心进入漫游模式。
2. 选择歌单或歌曲作为种子。
3. 选择「相似 / 平衡 / 探索」风格。
4. 队列接近末尾时自动发现并补充。

**设备同步(Beta)**

同局域网内开启设备同步：应用通过 mDNS 发现设备，通过二维码或配对请求建立信任连接，之后可同步播放状态、队列与远程控制。

---

## 登录与数据

部分 B 站功能需要登录：

- **移动端**：通过 [gt3_flutter_plugin](https://pub.dev/packages/gt3_flutter_plugin) 完成账号密码登录。
- **桌面端**：默认使用 B 站 App 扫码登录。
- **数据迁移**：可在数据管理中将移动端数据迁移到桌面端。

> **数据存储**：歌单、收藏和历史保存在本地 SQLite；设置使用 `shared_preferences`；网络资源与歌词进入本地缓存。迁移或清理前请做好备份。

---

## 技术架构

### 一次播放请求的路径

```text
UI / Riverpod Provider
        ↓
PlayerCoordinator  ─── RoamingService
        ↓
DualAudioService  ─── NotificationService / PiP / LAN Sync
        ↓
ApiService
        ↓
BiliClient  ─── Bilibili API
```

### 分层职责

| 层 | 目录 | 职责 |
| --- | --- | --- |
| **UI** | `pages/` · `components/` · `shells/` | 页面、组件、横竖屏与方屏布局 |
| **状态** | `providers/` | Riverpod 状态、命令与页面导航 |
| **编排** | `services/` | 播放流程、网络业务、漫游、同步、系统集成 |
| **管理** | `managers/` | 设置、用户、缓存、歌单、推荐、收藏夹同步 |
| **基础设施** | `core/` · `api/` | Provider 容器、数据库、HTTP 客户端、异常体系 |
| **视觉系统** | `theme/` | Palette、Token、主题注册切换 |

> 长生命周期服务统一在 `lib/core/app_providers.dart` 中创建与释放；UI 只消费 Provider，不直接实例化业务管理器。

---

## 代码导航

```text
lib/
├── main.dart                 # 应用入口
├── api/                      # Bilibili HTTP 客户端与异常
├── core/                     # Provider 容器与 SQLite 数据库
├── managers/                 # 设置、用户、歌单、缓存、推荐、同步管理
├── models/                   # 音乐、歌单、播放、漫游、同步等模型
├── providers/                # Riverpod 状态与依赖入口
├── services/                 # API、播放器、漫游、登录、通知、PiP、局域网同步
├── components/               # 可复用 UI、歌词、播放器与播放列表组件
├── pages/                    # 首页、搜索、歌单、详情、设置、个人中心
├── shells/                   # 应用外壳与横竖屏导航布局
├── theme/                    # AppTokens、AppPalette 与主题变体
└── utils/                    # 歌词、颜色、响应式、相似度与平台工具
```

### 主要依赖

| 依赖 | 用途 |
| --- | --- |
| [Flutter](https://flutter.dev/) | 跨平台 UI 框架 |
| [Riverpod](https://riverpod.dev/) | 状态管理与依赖注入 |
| [just_audio](https://pub.dev/packages/just_audio) · [audio_service](https://pub.dev/packages/audio_service) | 音频播放 + 后台与系统媒体控制 |
| [dio](https://pub.dev/packages/dio) · [http](https://pub.dev/packages/http) | 视频详情、音频 URL 与统一 HTTP 客户端 |
| [bonsoir](https://pub.dev/packages/bonsoir) | mDNS 局域网设备发现 |
| [sqflite](https://pub.dev/packages/sqflite) | 本地 SQLite 数据存储 |
| [flutter_lyric](https://pub.dev/packages/flutter_lyric) | 歌词渲染 |
| [color_thief_dart](https://pub.dev/packages/color_thief_dart) | 封面主色提取 |
| [window_manager](https://pub.dev/packages/window_manager) | 桌面窗口管理 |

---

## 开发命令

```bash
flutter pub get       # 安装依赖
flutter analyze       # 静态分析
flutter test          # 运行测试
flutter run           # 调试运行
```

> 提交改动前建议至少执行 `flutter analyze`，并在目标平台完成一次构建验证。

---

## 参与贡献

欢迎通过 [Issue](https://github.com/NaivG/bilimusic/issues) 报告问题，或提交 Pull Request 改进功能。提交前请尽量：

1. 说明复现环境、平台与具体步骤。
2. 保持改动聚焦，并遵循现有 Flutter / Dart 代码风格。
3. 执行 `flutter analyze` 和相关测试。
4. 不提交 Cookie、账号信息、构建产物或其他敏感数据。

---

## 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE) 许可证。

```text
Copyright (C) 2026 NaivG and contributors.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

---

## 致谢

- UI 设计灵感：Apple Music、某云音乐、[ParticleMusic](https://github.com/AfalpHy/ParticleMusic)
- 歌词获取：[LDDC](https://github.com/chenmozhijin/LDDC)
- 歌词渲染：[coriander_player](https://github.com/Ferry-200/coriander_player)
- GitHub Actions：[FlutterHub](https://github.com/xmaihh/FlutterHub)

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=NaivG/bilimusic&type=Date)](https://star-history.com/#NaivG/bilimusic&Date)
