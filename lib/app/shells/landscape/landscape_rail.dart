import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 图标轨里的可跳转入口。
enum LandscapeRailDestination {
  home('首页', Icons.home_outlined, Icons.home_rounded),
  discover('发现', Icons.explore_outlined, Icons.explore_rounded),
  library('资料库', Icons.library_music_outlined, Icons.library_music_rounded),
  recent('最近播放', Icons.history_rounded, Icons.history_rounded),
  offline('离线缓存', Icons.download_outlined, Icons.download_rounded),
  favorites('我喜欢的音乐', Icons.favorite_outline_rounded, Icons.favorite_rounded);

  const LandscapeRailDestination(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// 横屏左侧图标轨（设计稿 `.rail`）。
///
/// 宽 76（900–1199 缩到 68）、通高；顶部 logo，中部 6 个 44×44 入口，
/// 底部同步状态点 / 设置 / 头像。选中项 accentSoftStrong 底 + accentDeep 图标，
/// 其余图标 textSecondary。
class LandscapeRail extends ConsumerWidget {
  const LandscapeRail({
    super.key,
    required this.selected,
    required this.settingsSelected,
    required this.onSelected,
    required this.onSettings,
    required this.onProfile,
    required this.onSync,
  });

  /// 当前高亮入口；非导航页（歌单 / 详情等）为 null。
  final LandscapeRailDestination? selected;

  /// 设置页是否高亮。
  final bool settingsSelected;

  final ValueChanged<LandscapeRailDestination> onSelected;
  final VoidCallback onSettings;
  final VoidCallback onProfile;

  /// 同步状态点：进入局域网同步页。
  final VoidCallback onSync;

  /// 设计稿 `.rail` padding 14。
  static const double _verticalInset = 14;

  /// 设计稿 `.rail-nav` margin-top 26。
  static const double _navTopGap = 26;

  /// 设计稿 `.rail-bottom` gap 10。
  static const double _bottomGap = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );
    final connectedPeers = ref.watch(connectedPeersProvider);
    const destinations = LandscapeRailDestination.values;

    return SizedBox(
      width: LandscapeBreakpoints.railWidth(context),
      child: BmChromeSurface(
        tone: BmChromeTone.canvas,
        edges: const <BmChromeEdge>{BmChromeEdge.right},
        blur: blur,
        // 把内容让到安全区域
        child: SafeArea(
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: Column(
            children: [
              const SizedBox(height: _verticalInset),
              // 品牌 logo：点回首页
              Tooltip(
                message: LandscapeRailDestination.home.label,
                child: BmPressable(
                  onTap: () => onSelected(LandscapeRailDestination.home),
                  borderRadius: BmTokens.r10All,
                  semanticLabel: '首页',
                  child: ClipRRect(
                    borderRadius: BmTokens.r10All,
                    child: Image.asset(
                      'assets/ic_launcher.png',
                      width: BmTokens.railLogo,
                      height: BmTokens.railLogo,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _navTopGap),
              // 窄屏横屏（手机 / 小平板）高度可能装不下六个入口，导航允许纵向滚动。
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final destination in destinations) ...[
                        _RailButton(
                          icon: destination.icon,
                          activeIcon: destination.activeIcon,
                          label: destination.label,
                          selected: destination == selected,
                          onTap: () => onSelected(destination),
                        ),
                        if (destination != destinations.last)
                          const SizedBox(height: BmTokens.railItemGap),
                      ],
                    ],
                  ),
                ),
              ),
              _SyncDot(connectedCount: connectedPeers.length, onTap: onSync),
              const SizedBox(height: _bottomGap),
              _RailButton(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: '设置',
                selected: settingsSelected,
                onTap: onSettings,
              ),
              const SizedBox(height: _bottomGap),
              _Avatar(onTap: onProfile),
              const SizedBox(height: _verticalInset),
            ],
          ),
        ),
      ),
    );
  }
}

/// 44×44 图标按钮；选中态走 accentSoftStrong 胶囊。
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;

    return Tooltip(
      message: label,
      child: BmPressable(
        onTap: onTap,
        selected: selected,
        selectedColor: colors.accentSoftStrong,
        borderRadius: BmTokens.railItemRadius,
        semanticLabel: label,
        child: SizedBox(
          width: BmTokens.railItem,
          height: BmTokens.railItem,
          child: Center(
            child: Icon(
              selected ? activeIcon : icon,
              size: BmTokens.icon,
              color: selected ? colors.accentDeep : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部 28 同步状态点：有已连接设备时亮 success 小圆点。
class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.connectedCount, required this.onTap});

  final int connectedCount;
  final VoidCallback onTap;

  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final connected = connectedCount > 0;

    return Tooltip(
      message: connected ? '私有同步 · $connectedCount 台设备' : '私有同步 · 未连接',
      child: BmPressable(
        onTap: onTap,
        borderRadius: BmTokens.rPillAll,
        semanticLabel: '局域网同步',
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: colors.success.withValues(alpha: BmAlpha.selected),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.sync_rounded,
                size: BmTokens.iconMenu,
                color: colors.accentDeep,
              ),
              if (connected)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.success,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.bg,
                        width: BmTokens.hairlineWidth * 3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部 32 圆形头像：未登录退化为占位人像。
class _Avatar extends ConsumerStatefulWidget {
  const _Avatar({required this.onTap});

  final VoidCallback onTap;

  @override
  ConsumerState<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends ConsumerState<_Avatar> {
  static const double _size = 32;

  @override
  void initState() {
    super.initState();
    // 头像需要用户信息；首帧后再拉一次（缓存 5 分钟，未登录直接返回）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final manager = ref.read(userManagerProvider);
      manager.checkCookieLogin();
      if (manager.isLoggedIn && manager.userInfo == null) {
        manager.getUserInfo();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final manager = ref.watch(userManagerProvider);

    return ListenableBuilder(
      listenable: manager,
      builder: (context, child) {
        final user = manager.userInfo;
        final avatar = user?.avatar ?? '';
        return Tooltip(
          message: '我的',
          child: BmPressable(
            onTap: widget.onTap,
            borderRadius: BmTokens.rPillAll,
            semanticLabel: '我的',
            child: Container(
              width: _size,
              height: _size,
              foregroundDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.lineStrong,
                  width: BmTokens.hairlineWidth,
                ),
              ),
              child: ClipOval(
                child: avatar.isEmpty
                    ? ColoredBox(
                        color: colors.bgDeep,
                        child: Icon(
                          Icons.person_rounded,
                          size: BmTokens.iconMenu,
                          color: colors.textSecondary,
                        ),
                      )
                    : BmArtImage(url: avatar, cacheKey: 'avatar-${user?.uid}'),
              ),
            ),
          ),
        );
      },
    );
  }
}
