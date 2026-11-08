import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 图标按钮的可视尺寸档位：28 / 34 / 40。
enum BmIconButtonSize { sm, md, lg }

/// Lucent 图标按钮。
///
/// 可视尺寸 28 / 34 / 40，命中区默认取 `max(可视尺寸, BmTokens.touchDesktop)`；
/// 图标 16 / 20，圆角 [BmTokens.r10All]，四态状态层走 [BmPressable]，不做缩放。
/// tooltip 非空时外层包 [Tooltip]。
///
/// ```dart
/// BmIconButton(
///   icon: Icons.favorite,
///   tooltip: '收藏',
///   active: liked,
///   onPressed: toggleLike,
/// )
/// ```
class BmIconButton extends StatelessWidget {
  const BmIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.size = BmIconButtonSize.md,
    this.iconSize,
    this.active = false,
    this.danger = false,
    this.color,
    this.hitSize,
    this.focusNode,
    this.autofocus = false,
  });

  final IconData icon;

  /// 为 null 时按钮禁用（降到 38% 且不响应点击）。
  final VoidCallback? onPressed;

  /// 为空字符串或 null 时不包 [Tooltip]。
  final String? tooltip;

  final String? semanticLabel;

  final BmIconButtonSize size;

  /// 覆盖默认图标尺寸；sm 默认 16，md / lg 默认 20。
  final double? iconSize;

  /// 选中态：图标走 [BmColors.accent]，状态层走 `stateSelected`。
  final bool active;

  /// 危险操作：图标与状态层走 [BmColors.danger]。
  final bool danger;

  /// 临时语义色（收藏 ♥ / 播放键等），只改图标颜色；
  /// 优先级低于 [active] / [danger]。
  final Color? color;

  /// 命中区边长；默认 `max(可视尺寸, BmTokens.touchDesktop)`。
  final double? hitSize;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final visual = switch (size) {
      BmIconButtonSize.sm => BmTokens.controlSm,
      BmIconButtonSize.md => BmTokens.controlMd,
      BmIconButtonSize.lg => BmTokens.controlLg,
    };
    final effectiveIconSize =
        iconSize ??
        (size == BmIconButtonSize.sm ? BmTokens.iconMenu : BmTokens.icon);
    final hit = hitSize ?? math.max(visual, BmTokens.touchDesktop);

    final Color iconColor;
    if (danger) {
      iconColor = colors.danger;
    } else if (active) {
      iconColor = colors.accent;
    } else {
      iconColor = color ?? colors.textSecondary;
    }

    final button = BmPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      selected: active,
      borderRadius: BmTokens.r10All,
      overlayColor: danger
          ? colors.danger.withValues(alpha: BmAlpha.pressed)
          : null,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: hit,
        height: hit,
        child: Center(
          child: SizedBox(
            width: visual,
            height: visual,
            child: Icon(icon, size: effectiveIconSize, color: iconColor),
          ),
        ),
      ),
    );

    final tooltipText = tooltip;
    if (tooltipText == null || tooltipText.isEmpty) return button;
    return Tooltip(message: tooltipText, child: button);
  }
}
