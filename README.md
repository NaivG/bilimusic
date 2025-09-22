<!-- ![BiliMusic](assets/ic_launcher.png) -->
<div align="center">
    <div>
        <img src="./assets/ic_launcher.png" alt="logo" style="width: 20%; height: auto;">
    </div>
<h1>BiliMusic</h1>


另一个基于 Flutter 开发的哔哩哔哩音乐播放器，支持 Windows、Linux 和 Android 平台。

</div>

## 功能特性

- 🎵 哔哩哔哩音乐播放
- 🔍 音乐搜索功能（支持BV号、AV号、EP号）
- 📚 个人歌单管理
- ❤️ 收藏音乐
- 🎧 桌面端支持（Windows、Linux）
- 📱 移动端支持（Android 8+）
- 🌐 网易云音乐歌词匹配
- 🎨 动态主题色彩提取
- 📋 音乐播放列表管理
- ⚙️ 个性化设置选项

## 技术架构

- 使用 Flutter 框架开发，跨平台支持
- 集成 [just_audio](https://pub.dev/packages/just_audio) 实现音频播放
- 使用 [just_aaudio](https://github.com/NaivG/just_aaudio) 实现 Android AAudio 驱动播放
- 使用 [audio_service](https://pub.dev/packages/audio_service) 管理后台播放
- 通过 [http](https://pub.dev/packages/http) 与哔哩哔哩 API 通信
- 采用 [shared_preferences](https://pub.dev/packages/shared_preferences) 进行本地数据存储
- 利用 [cached_network_image](https://pub.dev/packages/cached_network_image) 优化图片加载
- 使用 [bitsdojo_window](https://pub.dev/packages/bitsdojo_window) 提供桌面端窗口定制

## 安装说明

### 系统要求

- Windows 7 及以上版本
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

## 使用指南

### 主要界面

1. **首页** - 展示推荐音乐和个人歌单
2. **搜索** - 搜索哔哩哔哩上的音乐内容
3. **个人中心** - 查看个人信息和收藏的音乐
4. **设置** - 配置应用参数和偏好

### 登录与Cookie设置

由于哔哩哔哩的限制，部分功能可能需要登录才能使用。

受限于极验插件[gt3_flutter_plugin](https://pub.dev/packages/gt3_flutter_plugin)，直接登录功能只能在移动端使用。

对于 PC 平台，你可以进行如下的操作：

1. 在手机端根据步骤登录。
2. 使用数据迁移功能，将 Cookie 等配置迁移至 PC 平台。
3. 重新启动程序。

### 桌面端特色功能

- 支持窗口拖拽和自定义大小
- 系统托盘最小化
- 全局媒体控制快捷键

## 贡献

欢迎提交 Issue 和 Pull Request 来帮助改进项目。

## 许可证

本项目采用 GNU General Public License v3.0 许可证，详情请参见 [LICENSE](LICENSE) 文件。

## 免责声明

本项目仅供学习交流使用，不得用于任何商业用途。音乐内容的版权归原作者所有。请尊重版权，合理使用音乐内容。