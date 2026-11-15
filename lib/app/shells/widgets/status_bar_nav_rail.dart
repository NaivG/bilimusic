import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/chrome/bm_dock.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 竖栏里的标签导航（iPhone Duo 合上时）。
///
/// 和系统一样，Dock 的入口竖排在竖栏最下面，只显示图标（标题作为无障碍
/// 标签和长按提示）。由外壳放进系统给竖栏的区域里；不画底色，直接透出
/// 外壳背景。
class StatusBarNavRail extends StatelessWidget {
  const StatusBarNavRail({
    super.key,
    required this.width,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final double width;
  final List<BmDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 每个入口的大小。
  static const double itemExtent = 48;
  static const double _itemGap = 6;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: _itemGap),
            _StatusBarNavItem(
              item: items[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBarNavItem extends StatelessWidget {
  const _StatusBarNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BmDockItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Tooltip(
      message: item.label,
      child: BmPressable(
        onTap: onTap,
        selected: selected,
        selectedColor: colors.accentSoftStrong,
        pressScale: 0.96,
        borderRadius: BmTokens.railItemRadius,
        semanticLabel: item.label,
        child: SizedBox(
          width: StatusBarNavRail.itemExtent,
          height: StatusBarNavRail.itemExtent,
          child: Center(
            child: Icon(
              selected ? (item.activeIcon ?? item.icon) : item.icon,
              size: BmTokens.navIcon,
              color: selected ? colors.accentDeep : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
