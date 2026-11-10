import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// Theater 白卡：设置组、曲目表、面板卡共用。
///
/// 默认白底（[BmColors.surfaceRaised]）+ 0.5px [BmColors.hairline] 描边 +
/// [BmTokens.cardRadius] 圆角；`elevated` 打开时补一层很浅的投影。
/// 不裁剪内容——需要裁切的调用点自己包 `ClipRRect`。
class BmCard extends StatelessWidget {
  const BmCard({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.elevated = false,
    this.color,
    this.border = true,
  });

  final Widget child;

  /// 内容内边距；为 null 时不留白（列表自己控制行内边距）。
  final EdgeInsetsGeometry? padding;

  /// 覆盖圆角，默认 [BmTokens.cardRadius]。
  final BorderRadiusGeometry? radius;

  /// 是否补投影。
  final bool elevated;

  /// 覆盖底色，默认 [BmColors.surfaceRaised]。
  final Color? color;

  /// 是否画 0.5px 描边。
  final bool border;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final effectiveRadius =
        radius ?? BorderRadius.circular(BmTokens.cardRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? colors.surfaceRaised,
        borderRadius: effectiveRadius,
        border: border
            ? Border.all(color: colors.hairline, width: BmTokens.hairlineWidth)
            : null,
        boxShadow: elevated
            ? <BoxShadow>[
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: BmTokens.s6,
                  offset: const Offset(0, BmTokens.s1),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}
