import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:bilimusic/features/player/pip/pip_service.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 桌面窗口控制按钮组：画中画 / 最小化 / 最大化 / 关闭。
///
/// 四个按钮统一走 [BmIconButton]（sm，图标 16），关闭走 `danger`，
/// tooltip 为中文。标题栏与 [DesktopNavBar] 共用。
class BmWindowControls extends StatelessWidget {
  const BmWindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BmIconButton(
          icon: Icons.picture_in_picture_alt,
          tooltip: '画中画',
          size: BmIconButtonSize.sm,
          onPressed: () => PipService().toggle(),
        ),
        BmIconButton(
          icon: Icons.minimize_rounded,
          tooltip: '最小化',
          size: BmIconButtonSize.sm,
          onPressed: () => windowManager.minimize(),
        ),
        BmIconButton(
          icon: Icons.crop_square_rounded,
          tooltip: '最大化/还原',
          size: BmIconButtonSize.sm,
          onPressed: _toggleMaximize,
        ),
        BmIconButton(
          icon: Icons.close_rounded,
          tooltip: '关闭',
          size: BmIconButtonSize.sm,
          danger: true,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }

  Future<void> _toggleMaximize() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }
}

/// 桌面端窗口导航栏（含 Logo + 导航项 + 窗口控件）。
///
/// 表面走 [BmChromeSurface]（底边 hairline + 可选模糊），导航项用
/// [BmPressable] 承载 hover / pressed / selected 状态，选中走 accent。
class DesktopNavBar extends ConsumerWidget {
  final int selectedIndex;
  final Function(int) onNavTap;

  const DesktopNavBar({
    super.key,
    required this.selectedIndex,
    required this.onNavTap,
  });

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(Icons.home_outlined, Icons.home, '首页', 0),
    _NavItem(Icons.explore_outlined, Icons.explore, '发现', 1),
    _NavItem(Icons.person_outlined, Icons.person, '我的', 2),
    _NavItem(Icons.settings_outlined, Icons.settings, '设置', 3),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 非桌面平台返回空导航栏
    if (!PlatformHelper.isDesktop) {
      return const SizedBox.shrink();
    }

    final colors = context.bmColors;
    final type = context.bmType;
    final blur = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );

    return BmChromeSurface(
      edges: const <BmChromeEdge>{BmChromeEdge.bottom},
      blur: blur,
      child: SizedBox(
        height: BmTokens.controlLg,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
                child: Row(
                  children: [
                    Icon(
                      Icons.music_note_rounded,
                      color: colors.accent,
                      size: BmTokens.icon,
                    ),
                    const SizedBox(width: BmTokens.s2),
                    Text(
                      'BiliMusic',
                      style: type.label.copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final item in _items)
                    _NavTile(
                      icon: selectedIndex == item.index
                          ? item.activeIcon
                          : item.icon,
                      label: item.label,
                      isActive: selectedIndex == item.index,
                      onTap: () => onNavTap(item.index),
                    ),
                ],
              ),
            ),
            const BmWindowControls(),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;

  const _NavItem(this.icon, this.activeIcon, this.label, this.index);
}

/// 导航项：图标 16 + caption 文案，选中 accent。
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final tint = isActive ? colors.accent : colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: BmPressable(
        onTap: onTap,
        selected: isActive,
        borderRadius: BmTokens.r10All,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s2,
            vertical: BmTokens.s1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: BmTokens.iconMenu, color: tint),
              const SizedBox(width: BmTokens.s1),
              Text(label, style: type.caption.copyWith(color: tint)),
            ],
          ),
        ),
      ),
    );
  }
}
