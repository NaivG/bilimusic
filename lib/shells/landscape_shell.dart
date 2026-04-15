import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/pages/search_page.dart';
import 'package:bilimusic/shells/landscape/landscape_sidebar.dart';
import 'package:bilimusic/shells/landscape/landscape_player_bar.dart';
import 'package:bilimusic/shells/landscape/landscape_home_content.dart';
import 'package:bilimusic/utils/platform_helper.dart';

/// 横屏模式外壳 - 仿网易云音乐风格
/// 布局：标题栏 + 左侧歌单栏 + 主内容区 + 底部播放器栏
class LandscapeShell extends StatelessWidget {
  final int selectedIndex;
  final List<Widget> pages;
  final List<Playlist> playlists;
  final List<PlaylistTag> allTags;
  final String? selectedPlaylistId;
  final Function(int index) onNavTap;
  final Function(String playlistId)? onPlaylistTap;
  final VoidCallback? onCreatePlaylist;
  final VoidCallback onExpand;
  final VoidCallback onPlayList;
  final VoidCallback onWindowClose;
  final Function(String query)? onSearchSubmit; // 搜索提交回调
  final VoidCallback? onProfileTap; // 用户页面回调
  final VoidCallback? onSettingsTap; // 设置页面回调
  final String? landscapePendingQuery; // 横屏搜索栏的待搜索词

  const LandscapeShell({
    super.key,
    required this.selectedIndex,
    required this.pages,
    required this.playlists,
    required this.allTags,
    this.selectedPlaylistId,
    required this.onNavTap,
    this.onPlaylistTap,
    this.onCreatePlaylist,
    required this.onExpand,
    required this.onPlayList,
    required this.onWindowClose,
    this.onSearchSubmit,
    this.onProfileTap,
    this.onSettingsTap,
    this.landscapePendingQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth = 200.0;
          return Column(
            children: [
              // 顶部AppBar - 全宽
              SizedBox(
                height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900]! : Colors.white,
                  ),
                  child: PlatformHelper.isDesktop
                      ? MoveWindow(child: _buildAppBarContent(isDark))
                      : _buildAppBarContent(isDark),
                ),
              ),
              // 下方：侧栏 + 主内容区 + 底部播放器
              Expanded(
                child: Row(
                  children: [
                    // 左侧固定侧栏
                    SizedBox(
                      width: sidebarWidth,
                      child: LandscapeSidebar(
                        selectedIndex: selectedIndex,
                        playlists: playlists,
                        allTags: allTags,
                        selectedPlaylistId: selectedPlaylistId,
                        onNavTap: onNavTap,
                        onPlaylistTap: onPlaylistTap,
                        onCreatePlaylist: onCreatePlaylist,
                      ),
                    ),
                    // 右侧主内容区 + 底部播放器
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: selectedIndex == 0
                                ? _buildLandscapeHomeContent(context)
                                : selectedIndex == 1
                                    ? SearchPage(
                                        pendingQuery: landscapePendingQuery,
                                      )
                                    : pages[selectedIndex],
                          ),
                          LandscapePlayerBar(
                            onExpand: onExpand,
                            onPlayList: onPlayList,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建AppBar内容
  Widget _buildAppBarContent(bool isDark) {
    return Row(
      children: [
        // 左侧 Logo + 标题
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            children: [
              Image.asset(
                'assets/ic_launcher.png',
                width: 32,
                height: 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
              Text(
                'BiliMusic',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey[800],
                  fontFamily: 'CabinSketch',
                ),
              ),
              const SizedBox(width: 4),
              kDebugMode
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Beta',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    )
                  : const SizedBox(width: 36),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _TitleBarButton(
          icon: Icons.home_outlined,
          onTap: () => onNavTap(0),
          isDark: isDark,
          tooltip: '返回主页',
        ),
        // 中间：搜索栏
        Container(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 200),
          height: 36,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(18),
          ),
          child: TextField(
            onSubmitted: (query) {
              if (query.isNotEmpty) {
                onSearchSubmit?.call(query);
                // 切换到搜索页面（索引1）
                onNavTap(1);
              }
            },
            decoration: InputDecoration(
              hintText: '搜索音乐、视频、用户...',
              hintStyle: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 16,
                color: isDark ? Colors.white38 : Colors.grey[500],
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white : Colors.grey[800],
            ),
          ),
        ),
        // 中间弹性区域
        const Spacer(),
        // 右侧：用户按钮 + 设置按钮
        _TitleBarButton(
          icon: Icons.person_outline,
          onTap: () {
            if (onProfileTap != null) {
              onProfileTap!();
            } else {
              // 默认行为：切换到用户页面（索引2）
              onNavTap(2);
            }
          },
          isDark: isDark,
        ),
        _TitleBarButton(
          icon: Icons.settings_outlined,
          onTap: () {
            if (onSettingsTap != null) {
              onSettingsTap!();
            } else {
              // 默认行为：切换到设置页面（索引3）
              onNavTap(3);
            }
          },
          isDark: isDark,
        ),
        // 窗口控制按钮
        PlatformHelper.isDesktop
            ? const WindowButtons()
            : const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildLandscapeHomeContent(BuildContext context) {
    return LandscapeHomeContent(
      playlists: playlists,
      selectedPlaylistId: selectedPlaylistId,
      onPlaylistTap: onPlaylistTap,
    );
  }
}

/// 标题栏按钮
class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final String? tooltip;

  const _TitleBarButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isDark ? Colors.white70 : Colors.grey[700],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// 窗口控制按钮组件
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformHelper.isDesktop;

    return Row(
      children: [
        _WindowButton(
          icon: Icons.minimize,
          onTap: () {
            if (isDesktop) appWindow.minimize();
          },
        ),
        _WindowButton(
          icon: isDesktop && appWindow.isMaximized
              ? Icons.filter_none
              : Icons.crop_square,
          onTap: () {
            if (isDesktop) {
              if (appWindow.isMaximized) {
                appWindow.restore();
              } else {
                appWindow.maximize();
              }
            }
          },
        ),
        _WindowButton(
          icon: Icons.close,
          onTap: () {
            if (isDesktop) appWindow.close();
          },
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered
              ? (widget.isClose
                    ? Colors.red
                    : Colors.grey[400]!.withValues(alpha: 0.3))
              : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: 14,
              color: _isHovered && widget.isClose
                  ? Colors.white
                  : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }
}
