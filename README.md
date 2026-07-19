<!-- ![BiliMusic](assets/ic_launcher.png) -->

<div align="center">
    <div>
        <img src="./assets/ic_launcher.png" alt="logo" style="width: 20%; height: auto;">
    </div>

<h1>BiliMusic</h1>

另一个基于 Flutter 开发的哔哩哔哩音乐播放器，支持 Windows、Linux 和 Android 平台。

![Stars](https://shields.io/github/stars/NaivG/bilimusic.svg)
![Forks](https://img.shields.io/github/forks/NaivG/bilimusic.svg)
![Issues](https://img.shields.io/github/issues/ProjectCoral/Coral.svg)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.1-02569B.svg?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.11.0-0175C2.svg?logo=dart)](https://dart.dev/)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/NaivG/bilimusic)](https://github.com/NaivG/bilimusic/releases)
[![License](https://img.shields.io/badge/License-AGPL3.0-blue.svg)](LICENSE)

</div>

> [!important]
>本项目仅供学习交流使用，不得用于任何商业用途。BiliMusic 仅提供音频播放功能，不提供任何视听服务。音乐内容的版权归原作者所有。请尊重版权，合理使用音乐内容。
>
> **由于不可抗拒力，请勿在其他平台宣传、讨论有关本项目的内容。**

---

## 📋 目录

- [功能特性](#-功能特性)
- [安装说明](#-安装说明)
- [使用指南](#-使用指南)
- [技术架构](#-技术架构)
- [代码结构](#-代码结构)
- [贡献](#-贡献)
- [许可证](#-许可证)
- [参考项目](#-参考项目)
- [Star History](#star-history)

---

## ✨ 功能特性

- 🎵 **哔哩哔哩音乐播放** - 播放B站视频音频，支持多分P视频
- 🔍 **音乐搜索功能** - 支持BV号、AV号、EP号搜索
- 📚 **个人歌单管理** - 创建、编辑、删除个人歌单
- ❤️ **收藏音乐** - 一键收藏喜欢的音乐
- 🎧 **多端支持** - 适配Windows、Linux、Android 8+ 
- 🌐 **歌词匹配** - 自动匹配并显示歌词
- 🎨 **动态主题色彩** - 从封面提取主题色，自动切换界面配色
- 🎭 **多主题切换** - 内置 Lucent / Nocturne / Verdant 等多套主题
- 📋 **播放列表管理** - 支持拖拽排序、循环模式切换
- ⚙️ **个性化设置** - 多种设置选项满足不同需求
- 🔄 **交叉淡入淡出** - 双播放器引擎（equal-power 曲线）实现无缝切歌
- 🔊 **音量控制** - 用户音量持久化、横屏静音快捷键
- 📱 **方屏适配** - 手表 / 折叠外屏 / 近方形 PiP 专属方屏详情页
- 🔐 **扫码登录** - 桌面端通过 B 站 App 扫码登录
- 🤖 **智能推荐** - 基于播放历史推荐你喜欢的内容
- 📤 **数据迁移** - 支持跨平台数据同步
- 📥 **收藏夹导入** - 从B站收藏夹一键导入，自动创建本地歌单并跟踪同步状态

---

## 📥 安装说明

### 系统要求

- Windows 10 及以上版本
- Linux (Ubuntu 20.04+ 或其他主流发行版)
- Android 8.0 (API 26) 及以上版本

### 下载安装

1. 前往 [Releases](https://github.com/naivg/bilimusic/releases) 页面下载最新版本
2. 根据您的操作系统选择合适的安装包：
   - **Windows**: 下载 `bilimusic_win32_x64-*.zip` 文件，解压后运行
   - **Linux**: 下载 `bilimusic_linux-x64-*.zip` 文件，确保你已经安装了`libmpv` (`sudo apt install libmpv-dev`), 解压后运行
   - **Android**: 根据您的设备架构选择对应的 APK 文件：
     - `bilimusic_android-arm64-v8a-*.apk` (适用于大多数现代 Android 设备)
     - `bilimusic_android-armeabi-v7a-*.apk` (适用于较旧的 32 位 ARM 设备)
     - `bilimusic_android-x86_64-*.apk` (适用于 x86_64 架构的模拟器或设备)
   - **Web**: 下载 `bilimusic_web-release-*.zip` 文件，解压后部署到 Web 服务器 (需要配置CORS跨域)
3. 按照系统提示完成安装或部署

### 从源码构建

```bash
# 克隆项目
git clone https://github.com/naivg/bilimusic.git
cd bilimusic

# 获取依赖
flutter pub get

# 运行应用
flutter run

# 构建发布版本
flutter build windows    # Windows
flutter build linux      # Linux
flutter build apk        # Android
flutter build web        # Web
flutter build macos      # MacOS (testing)
```

---

## 📖 使用指南

### 主要界面

1. **首页** - 展示推荐音乐、猜你喜欢和播放历史
2. **搜索** - 搜索哔哩哔哩上的音乐内容（支持BV/AV/EP号）
3. **歌单** - 管理个人歌单，支持从B站收藏夹导入<s>（NTR）</s>创建歌单
4. **个人中心** - 查看个人信息、收藏和播放历史
5. **设置** - 配置应用参数和偏好（包含主题、外观、播放等）

### 播放器功能

- 🎵 **播放控制**：播放/暂停、上一首/下一首
- 📃 **分P切换**：支持多P视频快速切换
- 🔀 **播放模式**：顺序播放、随机播放、单曲循环
- 🎚️ **进度控制**：拖动进度条跳转
- 🔊 **音量调节**：调整播放音量，支持一键静音
- ✨ **交叉淡入淡出**：双引擎 + equal-power 曲线实现无缝切歌
- 🎨 **动态主题**：封面色彩自动应用到界面
- 🖼️ **多形态详情页**：根据屏幕形状自动选择横屏 / 竖屏 / 方屏布局

### 登录方式

B 站部分功能需要登录后才能使用。本项目支持两种登录方式：

- **移动端**：通过极验插件 [gt3_flutter_plugin](https://pub.dev/packages/gt3_flutter_plugin) 进行账号密码登录。
- **桌面端**：默认使用 B 站 App 扫码登录，无需手动迁移 Cookie。

如果想在桌面端复用已有 Cookie，可使用**数据迁移**功能将移动端的登录数据迁移过来。

---

## 🏗️ 技术架构

### 核心框架

- 使用 **Flutter** 框架开发，跨平台支持
- 使用 **Riverpod** 进行依赖注入与状态管理（已替换旧的 ServiceLocator）

### 音频处理

- 集成 [just_audio](https://pub.dev/packages/just_audio) 实现音频播放
- 使用 [just_aaudio](https://github.com/NaivG/just_aaudio) 实现 Android AAudio 驱动播放
- 使用 [audio_service](https://pub.dev/packages/audio_service) 管理后台播放
- **双播放器引擎**：DualAudioService 以 equal-power 曲线实现交叉淡入淡出

### 网络通信

- 统一通过自研 `BiliClient` 封装 headers / cookies / 错误处理
- `BiliException` 体系统一封装 API / 网络异常
- 集成某某云音乐 API 实现歌词匹配

### 数据存储

- 采用 [shared_preferences](https://pub.dev/packages/shared_preferences) 进行本地配置存储
- 使用本地 SQLite（通过 `core/database.dart` 单例）存储歌单 / 收藏 / 历史
- 利用 [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager) 管理网络缓存
- 歌词本地缓存（30天有效期）

### UI/UX

- 利用 [cached_network_image](https://pub.dev/packages/cached_network_image) 优化图片加载
- 使用 [window_manager](https://pub.dev/packages/window_manager) 提供桌面端窗口定制
- 使用 [color_thief_dart](https://pub.dev/packages/color_thief_dart) 实现动态主题色提取
- 使用 [flutter_lyric](https://pub.dev/packages/flutter_lyric) 展示歌词
- 主题系统基于 `AppTokens` + `AppPalette` 构建，支持运行时切换

### 其他依赖

- [qr_flutter](https://pub.dev/packages/qr_flutter) - 二维码生成（扫码登录）
- [gt3_flutter_plugin](https://pub.dev/packages/gt3_flutter_plugin) - 极验验证码
- [share_plus](https://pub.dev/packages/share_plus) - 分享功能
- [file_picker](https://pub.dev/packages/file_picker) - 文件选择
- [riverpod](https://pub.dev/packages/flutter_riverpod) - 状态管理与依赖注入
- [rxdart](https://pub.dev/packages/rxdart) - 响应式编程扩展

---

## 📁 代码结构

```
lib/
├── main.dart                      # 应用入口
├── api/                           # 网络层封装
│   ├── bili_client.dart           # 统一HTTP客户端
│   └── bili_exception.dart        # API/网络异常体系
│
├── components/                    # UI组件库
│   ├── auto_appbar.dart           # 自动导航栏
│   ├── common/                    # 通用组件
│   │   ├── background_blur_widget.dart  # 背景模糊组件
│   │   ├── cards/                 # 卡片组件
│   │   │   ├── common_music_list_tile.dart
│   │   │   ├── music_list_item.dart
│   │   │   └── playlist_card.dart
│   │   ├── landscape_cover_art.dart    # 横屏封面
│   │   ├── landscape_seek_bar.dart     # 横屏进度条
│   │   └── landscape_volume_bar.dart   # 横屏音量条
│   ├── desktop_window_controls.dart   # 桌面窗口控制
│   ├── dialogs/                    # 对话框
│   │   └── update_dialog.dart
│   ├── import_progress_dialog.dart # 收藏夹导入进度
│   ├── landscape/                  # 横屏布局组件
│   │   ├── album_section.dart
│   │   ├── apple_cover.dart
│   │   ├── apple_slider.dart
│   │   └── background.dart
│   ├── lyric/                      # 歌词组件
│   │   ├── lyric_line_widget.dart
│   │   ├── lyric_section.dart
│   │   └── lyric_source.dart
│   ├── mini_player_bar.dart        # 迷你播放条
│   ├── pip/                        # 小窗组件
│   │   └── pip_overlay.dart
│   ├── playlist/                   # 播放列表组件
│   │   ├── playlist_item.dart
│   │   └── playlist_sheet.dart
│   └── long_press_menu.dart        # 长按菜单
│
├── core/                          # 核心基础设施
│   ├── app_providers.dart          # Riverpod 全局 Provider 容器
│   └── database.dart               # SQLite 数据库单例
│
├── managers/                      # 核心管理器
│   ├── audio_handler.dart          # 音频Handler
│   ├── cache_manager.dart          # 缓存管理
│   ├── fav_sync_manager.dart       # 收藏夹同步
│   ├── playlist_manager.dart       # 歌单管理
│   ├── recommendation_manager.dart # 推荐管理
│   ├── settings_manager.dart       # 设置管理
│   └── user_manager.dart           # 用户信息管理
│
├── models/                        # 数据模型
│   ├── bili_fav_folder.dart       # B 站收藏夹
│   ├── bili_fav_resource.dart      # 收藏夹资源
│   ├── bili_item.dart              # B站视频项
│   ├── changelog_entry.dart        # 更新日志条目
│   ├── fav_import_record.dart      # 收藏夹导入记录
│   ├── music.dart                  # 音乐模型
│   ├── play_mode.dart              # 播放模式
│   ├── player_state.dart           # 播放状态
│   ├── playlist.dart               # 歌单模型
│   ├── playlist_tag.dart           # 歌单标签
│   ├── search_result.dart          # 搜索结果
│   └── user_info.dart              # 用户信息
│
├── pages/                         # 页面模块
│   ├── changelog_page.dart        # 更新日志
│   ├── cookie_page.dart           # Cookie设置
│   ├── data_management_page.dart  # 数据管理
│   ├── data_migration_page.dart   # 数据迁移
│   ├── detail/                    # 详情页
│   │   ├── landscape_detail_page.dart
│   │   ├── portrait_detail_page.dart
│   │   ├── square_detail_page.dart      # 方屏（手表/折叠外屏）适配
│   │   └── widgets/controls_bar.dart
│   ├── detail_page.dart           # 详情页入口
│   ├── fav_import_page.dart       # 收藏夹导入
│   ├── home_content.dart          # 首页内容
│   ├── home_page.dart             # 首页
│   ├── login_page.dart            # 登录页
│   ├── playlist/                  # 歌单页
│   │   ├── landscape_playlist_page.dart
│   │   ├── portrait_playlist_page.dart
│   │   └── widgets/
│   │       ├── playlist_header.dart
│   │       ├── playlist_hero.dart
│   │       ├── playlist_sidebar.dart
│   │       └── playlist_song_list.dart
│   ├── playlist_page.dart         # 歌单页入口
│   ├── profile_page.dart          # 个人中心
│   ├── qr_login_widget.dart       # 扫码登录组件
│   ├── search/                    # 搜索页
│   │   ├── search_overlay.dart
│   │   ├── search_results_overlay.dart
│   │   └── widgets/
│   │       ├── search_bar_widget.dart
│   │       ├── search_empty_state.dart
│   │       ├── search_result_card.dart
│   │       └── search_type_tabs.dart
│   └── settings_page.dart         # 设置页
│
├── providers/                     # Riverpod 状态管理
│   ├── fav_sync_providers.dart    # 收藏夹同步 Provider
│   ├── navigation_providers.dart  # 导航 Provider
│   ├── playback_providers.dart    # 播放状态 Provider
│   ├── playlist_providers.dart    # 歌单 Provider
│   ├── search_providers.dart      # 搜索 Provider
│   ├── service_providers.dart     # 服务 Provider
│   ├── settings_provider.dart     # 设置 Provider
│   ├── shell_page_providers.dart  # Shell 页面 Provider
│   └── user_providers.dart        # 用户 Provider
│
├── services/                     # 服务层
│   ├── api_service.dart          # B 站 API（基于 BiliClient）
│   ├── dual_audio_service.dart   # 双播放器服务（equal-power 交叉淡入淡出）
│   ├── notification_service.dart # 系统通知
│   ├── pip_service.dart          # 小窗服务
│   ├── player_coordinator.dart   # 播放器协调（CID 缺失自动补齐、playNextFromIndex 等）
│   ├── playlist_service.dart     # 歌单业务服务（含 CID 回填）
│   └── qr_login_service.dart     # 扫码登录轮询
│
├── shells/                        # 布局外壳
│   ├── app_shell.dart             # 应用外壳
│   ├── landscape/                 # 横屏布局
│   │   ├── landscape_bottom_control.dart
│   │   ├── landscape_sidebar.dart
│   │   └── landscape_title_bar.dart
│   ├── landscape_shell.dart       # 横屏外壳
│   ├── portrait_shell.dart        # 竖屏外壳
│   └── shell_page_manager.dart    # 页面管理
│
├── theme/                         # 主题系统
│   ├── app_palette.dart           # 统一颜色 palette
│   ├── app_tokens.dart            # 设计 token
│   ├── lucent_theme.dart          # 默认主题
│   ├── nocturne_theme.dart        # Nocturne 主题
│   ├── theme_registry.dart        # 主题注册表
│   └── verdant_theme.dart         # Verdant 主题
│
└── utils/                         # 工具类
    ├── animations.dart            # 动画工具
    ├── av_bv.dart                 # AV / BV 号互转
    ├── captcha_helper.dart        # 验证码辅助
    ├── color_extractor.dart       # 颜色提取
    ├── dialog_helpers.dart        # 对话框辅助
    ├── lyric_parser.dart          # 歌词解析
    ├── netease_music_api.dart     # 某某云音乐API
    ├── network_config.dart        # 网络配置
    ├── platform_helper.dart       # 平台辅助
    ├── responsive.dart            # 响应式布局（含方屏判断）
    ├── update_checker.dart        # 更新检查
    └── window_listener.dart       # 窗口监听
```

### 模块说明

#### 📦 core/ - 核心基础设施

| 文件 | 职责 |
|------|------|
| `app_providers.dart` | 全局 Riverpod Provider 容器，统一管理服务/管理器依赖 |
| `database.dart` | SQLite 数据库单例，封装歌单/收藏/历史表结构 |

#### 📦 api/ - 网络层

| 文件 | 职责 |
|------|------|
| `bili_client.dart` | 统一 HTTP 客户端，自动处理 headers、cookies 与错误校验 |
| `bili_exception.dart` | `BiliApiException` / `BiliNetworkException` 异常体系 |

#### 📦 managers/ - 核心管理器

| 文件 | 职责 |
|------|------|
| `audio_handler.dart` | 音频 Handler，处理后台播放 |
| `cache_manager.dart` | 全局缓存管理 |
| `fav_sync_manager.dart` | B 站收藏夹拉取、同步与跟踪 |
| `playlist_manager.dart` | 歌单管理，CRUD 操作 |
| `recommendation_manager.dart` | 推荐算法，基于播放历史推荐 |
| `settings_manager.dart` | 应用设置管理（含主题键名迁移） |
| `user_manager.dart` | 用户登录状态与信息缓存 |

#### 📦 services/ - 服务层

| 文件 | 职责 |
|------|------|
| `api_service.dart` | B 站 API 封装（基于 BiliClient），视频详情、音频 URL、搜索 |
| `dual_audio_service.dart` | 双播放器引擎，equal-power 交叉淡入淡出 |
| `player_coordinator.dart` | 播放器协调，播放流程编排 + CID 自动补齐 |
| `qr_login_service.dart` | 扫码登录轮询、过期与错误处理 |
| `playlist_service.dart` | 歌单业务服务（含缺失 CID 回填） |
| `notification_service.dart` | 系统媒体通知 |
| `pip_service.dart` | 小窗服务 |

#### 📦 providers/ - Riverpod 状态管理

| 文件 | 职责 |
|------|------|
| `playback_providers.dart` | 播放状态、播放命令、音量与静音 |
| `playlist_providers.dart` | 歌单状态与命令 |
| `settings_provider.dart` | 设置项的响应式状态 |
| `user_providers.dart` | 用户登录与信息 |
| `fav_sync_providers.dart` | 收藏夹同步状态 |
| `search_providers.dart` | 搜索状态 |
| `shell_page_providers.dart` | Shell 页面路由 |
| `navigation_providers.dart` | 全局导航 |
| `service_providers.dart` | 服务层 Provider 入口 |

#### 📦 models/ - 数据模型

| 文件 | 描述 |
|------|------|
| `music.dart` | 音乐模型，支持多分P视频 |
| `bili_item.dart` | B站视频项，包含分P信息 |
| `playlist.dart` | 歌单模型（带 source 字段区分来源） |
| `playlist_tag.dart` | 歌单标签 |
| `search_result.dart` | 搜索结果模型 |
| `bili_fav_folder.dart` | B 站收藏夹元数据 |
| `bili_fav_resource.dart` | 收藏夹资源条目 |
| `fav_import_record.dart` | 收藏夹导入记录 |
| `user_info.dart` | 用户信息 |
| `play_mode.dart` | 播放模式枚举 |
| `player_state.dart` | 播放状态模型 |
| `changelog_entry.dart` | 更新日志条目 |

#### 📦 components/ - UI组件

- **通用组件**：卡片、按钮等基础UI
- **播放器组件**：控制条、歌词显示、封面展示
- **布局组件**：横屏/竖屏/方屏自适应
- **小窗组件**：pip_overlay

#### 📦 theme/ - 主题系统

- `AppTokens` 统一管理尺寸/间距/圆角等设计 token
- `AppPalette` 通过 `context.appPalette` 提供响应式配色
- 通过 `theme_registry` 注册并切换 Lucent / Nocturne / Verdant 等主题

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来帮助改进项目。

---

## 📄 许可证

本项目采用 GNU AFFERO GENERAL PUBLIC LICENSE v3.0 许可证，详情请参见 [LICENSE](LICENSE) 文件。

```license
Copyright (C) 2026 NaivG and contributors.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
```

---

## ✨ 参考项目

 - [某某云音乐] UI参考
 - <s>[不可抗拒力]</s> 接口参考
 - [ParticleMusic](https://github.com/AfalpHy/ParticleMusic) 横屏UI参考
 - [LDDC](https://github.com/chenmozhijin/LDDC) 歌词获取参考
 - [coriander_player](https://github.com/Ferry-200/coriander_player) 歌词渲染参考
 - [FlutterHub](https://github.com/xmaihh/FlutterHub) github workflow参考
---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=NaivG/bilimusic&type=Date)](https://star-history.com/#NaivG/bilimusic&Date)