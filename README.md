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
>本项目仅供学习交流使用，不得用于任何商业用途。音乐内容的版权归原作者所有。请尊重版权，合理使用音乐内容。

---

## 📋 目录

- [功能特性](#-功能特性)
- [技术架构](#-技术架构)
- [代码结构](#-代码结构)
- [安装说明](#-安装说明)
- [使用指南](#-使用指南)
- [贡献](#-贡献)
- [许可证](#-许可证)
- [Star History](#Star-History)

---

## ✨ 功能特性

- 🎵 **哔哩哔哩音乐播放** - 播放B站视频音频，支持多分P视频
- 🔍 **音乐搜索功能** - 支持BV号、AV号、EP号搜索
- 📚 **个人歌单管理** - 创建、编辑、删除个人歌单
- ❤️ **收藏音乐** - 一键收藏喜欢的音乐
- 🎧 **多端支持** - 适配Windows、Linux、Android 8+ 
- 🌐 **网易云歌词匹配** - 自动匹配并显示歌词
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
- 集成网易云音乐 API 实现歌词匹配

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
├── main.dart                 # 应用入口
├── index.dart               # 导出文件
│
├── components/              # UI组件库
│   ├── common/              # 通用组件
│   │   └── cards/           # 卡片组件
│   ├── landscape/           # 横屏布局组件
│   ├── playlist/            # 播放列表相关组件
│   ├── cover_display_widget.dart      # 封面显示组件
│   ├── desktop_window_controls.dart   # 桌面窗口控制
│   ├── function_controls_widget.dart  # 功能控制组件
│   ├── lyric_display_widget.dart      # 歌词显示组件
│   ├── mini_player.dart              # 迷你播放器
│   ├── music_info_widget.dart        # 音乐信息组件
│   ├── page_selector_widget.dart     # 分P选择器
│   └── player_controls_widget.dart   # 播放器控制组件
│
├── managers/                # 核心管理器
│   ├── audio_handler.dart    # 音频处理handler
│   ├── cache_manager.dart    # 缓存管理器
│   ├── player_manager.dart   # 播放器管理器
│   ├── playlist_manager.dart # 歌单管理器
│   ├── recommendation_manager.dart # 推荐管理器
│   └── settings_manager.dart # 设置管理器
│
├── models/                  # 数据模型
│   ├── bili_item.dart       # B站视频项模型
│   ├── music.dart           # 音乐模型（含分P支持）
│   ├── playlist.dart        # 歌单模型
│   ├── playlist_tag.dart    # 歌单标签模型
│   └── search_result.dart   # 搜索结果模型
│
├── pages/                   # 页面模块
│   ├── detail/              # 详情页
│   ├── home/               # 首页
│   ├── login/              # 登录页
│   ├── playlist/           # 歌单页
│   ├── profile/            # 个人中心页
│   ├── search/             # 搜索页
│   ├── settings/           # 设置页
│   ├── changelog_page.dart  # 更新日志
│   ├── cookie_page.dart    # Cookie设置页
│   ├── data_migration_page.dart # 数据迁移页
│   ├── detail_page.dart    # 详情页
│   ├── home_page.dart      # 首页
│   ├── login_page.dart      # 登录页
│   ├── playlist_page.dart  # 歌单页
│   ├── profile_page.dart   # 个人中心页
│   ├── search_page.dart    # 搜索页
│   └── settings_page.dart  # 设置页
│
├── providers/              # Riverpod状态管理
│   ├── player_manager_provider.dart
│   ├── playlist_manager_provider.dart
│   └── search_state_provider.dart
│
├── routes/                 # 路由配置
│   └── app_routes.dart     # 应用路由定义
│
├── services/              # 服务层
│   ├── api_service.dart    # B站API服务
│   ├── audio_service.dart  # 音频服务
│   ├── dual_audio_service.dart # 双播放器服务
│   ├── notification_service.dart # 通知服务
│   ├── page_cache.dart     # 页面缓存
│   ├── page_service.dart   # 页面服务
│   ├── player_coordinator.dart # 播放器协调器
│   ├── playlist_cache.dart # 歌单缓存
│   ├── playlist_repository.dart # 歌单仓库
│   ├── playlist_service.dart # 歌单服务
│   └── search_service.dart # 搜索服务
│
├── shells/                # 布局外壳
│   ├── landscape/          # 横屏布局
│   ├── portrait/           # 竖屏布局
│   ├── app_shell.dart      # 应用外壳
│   ├── landscape_shell.dart # 横屏布局壳
│   └── portrait_shell.dart # 竖屏布局壳
│
└── utils/                 # 工具类
    ├── animations.dart     # 动画工具
    ├── captcha_helper.dart # 验证码辅助
    ├── color_extractor.dart # 颜色提取工具
    ├── lyric_parser.dart   # 歌词解析器
    ├── netease_music_api.dart # 网易云音乐API
    ├── network_config.dart  # 网络配置
    ├── platform_helper.dart # 平台辅助
    └── responsive.dart     # 响应式布局工具
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
| `api_service.dart` | B站API封装，视频详情、音频URL获取 |
| `dual_audio_service.dart` | 双播放器引擎，实现交叉淡入淡出 |
| `search_service.dart` | 搜索服务 |
| `playlist_service.dart` | 歌单业务服务 |
| `netease_music_api.dart` | 网易云音乐歌词API |

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

---


## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=NaivG/bilimusic&type=Date)](https://star-history.com/#NaivG/bilimusic&Date)