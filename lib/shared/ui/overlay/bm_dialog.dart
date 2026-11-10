import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_overlay_routes.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 打开 Lucent 对话框，返回 `Navigator.pop` 的结果。
///
/// 遮罩用调用点主题的 `scrim`，面板 fade + scale 0.94→1（180ms 进 / 120ms 退）；
/// 危险操作传 `barrierDismissible: false`。
Future<T?> showBmDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final theme = Theme.of(context);
  return Navigator.of(context).push<T>(
    BmDialogRoute<T>(
      builder: builder,
      theme: theme,
      barrierColor: BmColors.of(context).scrim,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierDismissible: barrierDismissible,
      reduceMotion: reduceMotionOf(context),
    ),
  );
}

/// Lucent 对话框面板。
///
/// 宽 `min(420, 90vw)`，`floating` 底 + 0.5 hairline + 20 圆角，内边距 24；
/// 标题 `headline`、正文 `body`，按钮行右对齐并按 8 的间距换行。
class BmDialog extends StatelessWidget {
  const BmDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const <Widget>[],
  });

  /// 标题；为 null 时只显示正文。
  final String? title;

  /// 正文，默认继承 `body` 文本样式。
  final Widget content;

  /// 底部操作按钮，右对齐。
  final List<Widget> actions;

  static const double _maxWidth = 420;
  static const double _widthFactor = 0.9;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final width = math.min(
      _maxWidth,
      MediaQuery.sizeOf(context).width * _widthFactor,
    );
    final title = this.title;
    return SizedBox(
      width: width,
      child: Material(
        color: colors.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BmTokens.r20All,
          side: BorderSide(color: colors.hairline, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(BmTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Text(
                  title,
                  style: type.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: BmTokens.s2),
              ],
              Flexible(
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: type.body.copyWith(color: colors.textPrimary),
                    child: content,
                  ),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: BmTokens.s4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: BmTokens.s2,
                  runSpacing: BmTokens.s2,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
