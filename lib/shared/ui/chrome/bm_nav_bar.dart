import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 竖屏底栏的一项。
class BmNavBarItem {
  const BmNavBarItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });

  /// 未选中时的图标。
  final IconData icon;

  /// 底栏文案。
  final String label;

  /// 选中时替换的图标；为空时沿用 [icon]。
  final IconData? activeIcon;
}

/// 竖屏底栏。
///
/// 表面走 [BmChromeSurface]（顶部 hairline + 模糊），行高
/// [BmTokens.navBarHeight] 外加底部 safe area。选中项只做 80ms 颜色过渡，
/// 不做位移。
class BmNavBar extends StatelessWidget {
  const BmNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.blur = true,
  });

  final List<BmNavBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 是否启用背景模糊，直接透传给 [BmChromeSurface]。
  final bool blur;

  @override
  Widget build(BuildContext context) {
    return BmChromeSurface(
      edges: const <BmChromeEdge>{BmChromeEdge.top},
      blur: blur,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: BmTokens.navBarHeight,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _BmNavBarItemView(
                    item: items[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个底栏项：图标 + 2px 间距 + micro 文案，整体居中。
class _BmNavBarItemView extends StatelessWidget {
  const _BmNavBarItemView({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BmNavBarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final targetColor = selected ? colors.accent : colors.textSecondary;
    final icon = selected ? (item.activeIcon ?? item.icon) : item.icon;

    return BmPressable(
      onTap: onTap,
      selected: selected,
      borderRadius: BmTokens.r10All,
      child: Center(
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(begin: targetColor, end: targetColor),
          duration: motionDuration(context, BmMotion.micro),
          curve: BmMotion.linear,
          builder: (context, color, _) {
            final tint = color ?? targetColor;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: BmTokens.icon, color: tint),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.micro.copyWith(color: tint),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
