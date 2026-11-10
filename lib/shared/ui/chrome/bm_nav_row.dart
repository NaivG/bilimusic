import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 侧栏 / 列表导航行。
///
/// 10 圆角，左侧 3px 选中条（选中时 20 高），选中底为 accent 12%；
/// 未选中图标与文字用 textSecondary，选中文字 textPrimary、图标 accent。
class BmNavRow extends StatelessWidget {
  const BmNavRow({
    super.key,
    required this.icon,
    required this.title,
    this.activeIcon,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.height = BmTokens.navRowHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: BmTokens.s3),
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  /// 未选中时的图标。
  final IconData icon;

  /// 行标题，单行省略。
  final String title;

  /// 选中时替换的图标；为空时沿用 [icon]。
  final IconData? activeIcon;

  /// 行尾内容，例如数量或操作按钮。
  final Widget? trailing;

  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 行高，默认 [BmTokens.navRowHeight]。
  final double height;

  /// 内容内边距，默认左右 [BmTokens.s3]。
  final EdgeInsetsGeometry padding;

  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final iconData = selected ? (activeIcon ?? icon) : icon;
    final iconColor = selected ? colors.accentDeep : colors.textSecondary;
    final textColor = selected ? colors.textPrimary : colors.textSecondary;

    return ClipRRect(
      borderRadius: BmTokens.r10All,
      child: BmPressable(
        selected: selected,
        selectedColor: colors.accentSoftStrong,
        borderRadius: BmTokens.r10All,
        onTap: onTap,
        onLongPress: onLongPress,
        focusNode: focusNode,
        autofocus: autofocus,
        semanticLabel: semanticLabel,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                Icon(iconData, size: BmTokens.icon, color: iconColor),
                const SizedBox(width: BmTokens.s3),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: motionDuration(context, BmMotion.small),
                    curve: BmMotion.standard,
                    style: type.body.copyWith(color: textColor),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
