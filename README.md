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
> 
>本项目仅供学习交流使用，不得用于任何商业用途。BiliMusic 仅提供音频播放功能，不提供任何视听服务。音乐内容的版权归原作者所有。请尊重版权，合理使用音乐内容。
>
> **由于不可抗拒力，请勿在任何平台宣传、讨论有关本项目的内容。**

---

## 📋 目录

- [功能特性](#-功能特性)
- [技术架构](#-技术架构)
- [代码结构](#-代码结构)
- [安装说明](#-安装说明)
- [使用指南](#-使用指南)
- [贡献](#-贡献)
- [许可证](#-许可证)
- [参考项目](#-参考项目)
- [Star History](#Star-History)

---

## ✨ 功能特性

- 🎵 **哔哩哔哩音乐播放** - 播放B站视频音频，支持多分P视频
- 🔍 **音乐搜索功能** - 支持BV号、AV号、EP号搜索
- 📚 **个人歌单管理** - 创建、编辑、删除个人歌单
- ❤️ **收藏音乐** - 一键收藏喜欢的音乐
- 🎧 **多端支持** - 适配Windows、Linux、Android 8+ 
- 🌐 **歌词匹配** - 自动匹配并显示歌词
- 🎨 **动态主题色彩** - 从封面提取主题色，自动切换界面配色
- 📋 **播放列表管理** - 支持拖拽排序、循环模式切换
- ⚙️ **个性化设置** - 多种设置选项满足不同需求
- 🔄 **交叉淡入淡出** - 双播放器引擎实现无缝切歌
- 🤖 **智能推荐** - 基于播放历史推荐你喜欢的内容
- 📤 **数据迁移** - 支持跨平台数据同步

---

## 🏗️ 技术架构

### 核心框架
- 使用 **Flutter** 框架开发，跨平台支持

### 音频处理
- 集成 [just_audio](https://pub.dev/packages/just_audio) 实现音频播放
- 使用 [just_aaudio](https://github.com/NaivG/just_aaudio) 实现 Android AAudio 驱动播放
- 使用 [audio_service](https://pub.dev/packages/audio_service) 管理后台播放
- **双播放器引擎**：DualAudioService 实现交叉淡入淡出效果

### 网络通信
- 通过 [http](https://pub.dev/packages/http) 与<s>不可抗拒力</s>通信
- 集成某某云音乐 API 实现歌词匹配

### 数据存储
- 采用 [shared_preferences](https://pub.dev/packages/shared_preferences) 进行本地数据存储
- 利用 [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager) 管理缓存
- 歌词本地缓存（30天有效期）

### UI/UX
- 利用 [cached_network_image](https://pub.dev/packages/cached_network_image) 优化图片加载
- 使用 [bitsdojo_window](https://pub.dev/packages/bitsdojo_window) 提供桌面端窗口定制
- 使用 [color_thief_dart](https://pub.dev/packages/color_thief_dart) 实现动态主题色提取
- 使用 [flutter_lyric](https://pub.dev/packages/flutter_lyric) 展示歌词

### 其他依赖
- [gt3_flutter_plugin](https://pub.dev/packages/gt3_flutter_plugin) - 极验验证码
- [share_plus](https://pub.dev/packages/share_plus) - 分享功能
- [file_picker](https://pub.dev/packages/file_picker) - 文件选择
- [rxdart](https://pub.dev/packages/rxdart) - 响应式编程扩展

---

## 📁 代码结构

```
lib/
├── main.dart                      # 应用入口
├── index.dart                     # 导出文件
├── core/
│   └── service_locator.dart       # 依赖注入容器
│
├── components/                    # UI组件库
│   ├── auto_appbar.dart           # 自动导航栏
│   ├── common/                     # 通用组件
│   │   ├── background_blur_widget.dart  # 背景模糊组件
│   │   ├── cards/                  # 卡片组件
│   │   │   ├── bili_item_cards.dart
│   │   │   ├── common_music_list_tile.dart
│   │   │   ├── horizontal_music_card.dart
│   │   │   ├── music_card.dart
│   │   │   ├── music_list_item.dart
│   │   │   ├── playlist_card.dart
│   │   │   ├── responsive_music_card.dart
│   │   │   └── stacked_music_card.dart
│   │   ├── landscape_cover_art.dart    # 横屏封面
│   │   ├── landscape_seek_bar.dart     # 横屏进度条
│   │   ├── landscape_volume_bar.dart    # 横屏音量条
│   │   └── widgets/index.dart
│   ├── desktop_window_controls.dart     # 桌面窗口控制
│   ├── dialogs/                       # 对话框
│   │   └── update_dialog.dart
│   ├── landscape/                     # 横屏布局组件
│   │   ├── album_section.dart
│   │   ├── apple_cover.dart
│   │   ├── apple_slider.dart
│   │   └── background.dart
│   ├── lyric/                         # 歌词组件
│   │   ├── lyric_line_widget.dart
│   │   ├── lyric_section.dart
│   │   └── lyric_source.dart
│   ├── mini_player.dart               # 迷你播放器
│   ├── playlist/                      # 播放列表组件
│   │   ├── playlist_item.dart
│   │   └── playlist_sheet.dart
│   └── long_press_menu.dart           # 长按菜单
│
├── managers/                         # 核心管理器
│   ├── audio_handler.dart             # 音频Handler
│   ├── cache_manager.dart             # 缓存管理
│   ├── player_manager.dart            # 播放器管理
│   ├── playlist_manager.dart          # 歌单管理
│   ├── recommendation_manager.dart    # 推荐管理
│   └── settings_manager.dart          # 设置管理
│
├── models/                           # 数据模型
│   ├── bili_item.dart                # B站视频项
│   ├── changelog_entry.dart           # 更新日志条目
│   ├── music.dart                    # 音乐模型
│   ├── playlist.dart                  # 歌单模型
│   ├── playlist_tag.dart              # 歌单标签
│   └── search_result.dart             # 搜索结果
│
├── pages/                            # 页面模块
│   ├── changelog_page.dart            # 更新日志
│   ├── cookie_page.dart               # Cookie设置
│   ├── data_management_page.dart      # 数据管理
│   ├── data_migration_page.dart       # 数据迁移
│   ├── detail/                        # 详情页
│   │   ├── landscape_detail_page.dart
│   │   ├── portrait_detail_page.dart
│   │   └── widgets/controls_bar.dart
│   ├── detail_page.dart               # 详情页入口
│   ├── home_content.dart              # 首页内容
│   ├── home_page.dart                 # 首页
│   ├── login_page.dart                # 登录页
│   ├── playlist/                      # 歌单页
│   │   ├── landscape_playlist_page.dart
│   │   ├── portrait_playlist_page.dart
│   │   └── widgets/
│   │       ├── playlist_header.dart
│   │       ├── playlist_sidebar.dart
│   │       └── playlist_song_list.dart
│   ├── playlist_page.dart             # 歌单页入口
│   ├── profile_page.dart              # 个人中心
│   ├── search/                        # 搜索页
│   │   └── widgets/
│   │       ├── search_bar_widget.dart
│   │       ├── search_empty_state.dart
│   │       ├── search_result_card.dart
│   │       └── search_type_tabs.dart
│   ├── search_page.dart               # 搜索页入口
│   └── settings_page.dart             # 设置页
│
├── providers/                        # Riverpod状态管理
│   ├── search_state_provider.dart
│   └── shell_navigation_provider.dart
│
├── routes/                           # 路由配置
│   ├── app_routes.dart               # 应用路由
│   └── index.dart
│
├── services/                         # 服务层
│   ├── api_service.dart               # B站API
│   ├── audio_service.dart             # 音频服务
│   ├── dual_audio_service.dart        # 双播放器服务
│   ├── notification_service.dart      # 通知服务
│   ├── page_cache.dart                # 页面缓存
│   ├── page_service.dart              # 页面服务
│   ├── player_coordinator.dart        # 播放器协调
│   ├── playlist_cache.dart           # 歌单缓存
│   ├── playlist_repository.dart       # 歌单仓库
│   ├── playlist_service.dart          # 歌单服务
│   └── search_service.dart            # 搜索服务
│
├── shells/                           # 布局外壳
│   ├── app_shell.dart                # 应用外壳
│   ├── landscape/                    # 横屏布局
│   │   ├── landscape_bottom_control.dart
│   │   ├── landscape_sidebar.dart
│   │   └── landscape_title_bar.dart
│   ├── landscape_shell.dart           # 横屏外壳
│   ├── portrait_shell.dart            # 竖屏外壳
│   └── shell_page_manager.dart        # 页面管理
│
└── utils/                            # 工具类
    ├── animations.dart                # 动画工具
    ├── captcha_helper.dart            # 验证码辅助
    ├── color_extractor.dart           # 颜色提取
    ├── color_infra.dart               # 颜色基础设施
    ├── dialog_helpers.dart            # 对话框辅助
    ├── lyric_parser.dart              # 歌词解析
    ├── netease_music_api.dart         # 某某云音乐API
    ├── network_config.dart            # 网络配置
    ├── platform_helper.dart           # 平台辅助
    ├── responsive.dart                # 响应式布局
    ├── update_checker.dart            # 更新检查
    └── window_listener.dart          # 窗口监听
```

### 模块说明

#### 📦 managers/ - 核心管理器
| 文件 | 职责 |
|------|------|
| `player_manager.dart` | 播放器核心管理，控制播放、暂停、切歌等 |
| `playlist_manager.dart` | 歌单管理，CRUD操作 |
| `audio_handler.dart` | 音频Handler，处理后台播放 |
| `cache_manager.dart` | 全局缓存管理 |
| `recommendation_manager.dart` | 推荐算法，基于播放历史推荐 |
| `settings_manager.dart` | 应用设置管理 |

#### 📦 services/ - 服务层
| 文件 | 职责 |
|------|------|
| `api_service.dart` | API封装，视频详情、音频URL获取 |
| `dual_audio_service.dart` | 双播放器引擎，实现交叉淡入淡出 |
| `search_service.dart` | 搜索服务 |
| `playlist_service.dart` | 歌单业务服务 |
| `netease_music_api.dart` | 某某云音乐歌词API |

#### 📦 models/ - 数据模型
| 文件 | 描述 |
|------|------|
| `music.dart` | 音乐模型，支持多分P视频 |
| `bili_item.dart` | B站视频项，包含分P信息 |
| `playlist.dart` | 歌单模型 |
| `search_result.dart` | 搜索结果模型 |

#### 📦 components/ - UI组件
- **通用组件**：卡片、按钮等基础UI
- **播放器组件**：控制条、歌词显示、封面展示
- **布局组件**：横竖屏适配

---

## 📥 安装说明

### 系统要求

- Windows 10 及以上版本
- Linux (Ubuntu 20.04+ 或其他主流发行版)
- Android 8.0 (API 26) 及以上版本

### 下载安装

1. 前往 [Releases](https://github.com/naivg/bilimusic/releases) 页面下载最新版本
2. 根据您的操作系统选择合适的安装包：
   - Windows: 下载 `.exe` 安装文件
   - Linux: 下载 `.AppImage` 或 `.deb` 文件
   - Android: 下载 `.apk` 文件
3. 按照系统提示完成安装

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
```

---

## 📖 使用指南

### 主要界面

1. **首页** - 展示推荐音乐、猜你喜欢和播放历史
2. **搜索** - 搜索哔哩哔哩上的音乐内容（支持BV/AV/EP号）
3. **歌单** - 管理个人歌单
4. **个人中心** - 查看个人信息、收藏和播放历史
5. **设置** - 配置应用参数和偏好

### 播放器功能

- 🎵 **播放控制**：播放/暂停、上一首/下一首
- 📃 **分P切换**：支持多P视频快速切换
- 🔀 **播放模式**：顺序播放、随机播放、单曲循环
- 🎚️ **进度控制**：拖动进度条跳转
- 🔊 **音量调节**：调整播放音量
- ✨ **交叉淡入淡出**：双引擎实现无缝切歌
- 🎨 **动态主题**：封面色彩自动应用到界面

### 登录与Cookie设置

由于哔哩哔哩的限制，部分功能可能需要登录才能使用。

受限于极验插件[gt3_flutter_plugin](https://pub.dev/packages/gt3_flutter_plugin)，直接登录功能只能在移动端使用。

对于 PC 平台，你可以进行如下的操作：

1. 在手机端根据步骤登录。
2. 使用**数据迁移**功能，将 Cookie 等配置迁移至 PC 平台。
3. 重新启动程序。

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来帮助改进项目。

---

## 📄 许可证

本项目采用 GNU AFFERO GENERAL PUBLIC LICENSE v3.0 许可证，详情请参见 [LICENSE](LICENSE) 文件。

```
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
 - [coriander_player](https://github.com/Ferry-200/coriander_player) 歌词渲染参考
 - [FlutterHub](https://github.com/xmaihh/FlutterHub) github workflow参考
---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=NaivG/bilimusic&type=Date)](https://star-history.com/#NaivG/bilimusic&Date)