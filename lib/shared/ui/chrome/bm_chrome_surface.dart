import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// Chrome 表面的贴边方向。
enum BmChromeEdge { top, bottom, left, right }

/// Lucent Chrome 材质外壳。
///
/// 贴边栏（[floating] 为 false）保持直角，只在 [edges] 指定的边画 0.5px
/// [BmColors.hairline]；浮块（[floating] 为 true）用 14 圆角、四边 hairline
/// 与 `shadow` 投影。开启 [blur] 时底色为半透明 [BmColors.chrome] 并叠加
/// 24 高斯模糊；关闭时改用 [BmColors.chromeOpaque] 且不挂 [BackdropFilter]。
///
/// 只负责材质、裁剪与描边，不读设置；模糊开关与内边距由调用点传入。
class BmChromeSurface extends StatelessWidget {
  const BmChromeSurface({
    super.key,
    required this.child,
    this.floating = false,
    this.blur = true,
    this.edges = const <BmChromeEdge>{BmChromeEdge.bottom},
    this.padding,
  });

  /// 表面内容。
  final Widget child;

  /// 浮块：14 圆角 + 四边 hairline + 阴影；贴边栏为直角。
  final bool floating;

  /// 是否启用背景模糊；关闭时不创建 [BackdropFilter]。
  final bool blur;

  /// 贴边栏需要描边的边，仅 [floating] 为 false 时生效。
  final Set<BmChromeEdge> edges;

  /// 内容内边距，默认不额外留白。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final radius = floating ? BmTokens.r14All : BorderRadius.zero;
    final border = floating
        ? Border.all(color: colors.hairline, width: BmTokens.hairlineWidth)
        : _edgeBorder(colors.hairline, edges);
    final shadow = floating
        ? <BoxShadow>[
            BoxShadow(
              color: colors.shadow,
              blurRadius: BmTokens.s6,
              offset: const Offset(0, BmTokens.s2),
            ),
          ]
        : null;

    Widget content = ColoredBox(
      color: blur ? colors.chrome : colors.chromeOpaque,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (blur) {
      content = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: BmTokens.chromeBlurSigma,
          sigmaY: BmTokens.chromeBlurSigma,
        ),
        child: content,
      );
    }
    content = ClipRRect(borderRadius: radius, child: content);

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: DecoratedBox(
        // 描边画在内容之上，避免被裁剪后的内容盖住。
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(borderRadius: radius, border: border),
        child: content,
      ),
    );
  }

  /// 只给 [edges] 指定的边生成 hairline，其余边为 none。
  Border _edgeBorder(Color color, Set<BmChromeEdge> edges) {
    final side = BorderSide(color: color, width: BmTokens.hairlineWidth);
    return Border(
      top: edges.contains(BmChromeEdge.top) ? side : BorderSide.none,
      bottom: edges.contains(BmChromeEdge.bottom) ? side : BorderSide.none,
      left: edges.contains(BmChromeEdge.left) ? side : BorderSide.none,
      right: edges.contains(BmChromeEdge.right) ? side : BorderSide.none,
    );
  }
}
