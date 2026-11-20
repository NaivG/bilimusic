import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_overlay_routes.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// iOS 风味对话框。
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

/// 对话框动作按钮。
///
/// 两个以上动作时，列表里的最后一个动作是「默认动作」（实底 accent 胶囊），
/// 其余是 `fillMuted` 底的次要按钮；`destructive` 对话框的最后一个动作走
/// `danger` 文字。
/// 两个动作的文案都放得下时并排，否则按 iOS 的顺序竖排：默认动作在上，
/// 第一个动作（约定为取消）在最下。
///
/// [enabled] 为 false 时按钮降到 `textTertiary`、底色退回 `fillMuted`
/// 并整体 38% 透明度，用于表单未填完、任务进行中等不可提交的瞬间。
@immutable
class BmDialogAction {
  const BmDialogAction({
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
}

/// iOS 风味对话框面板。
///
/// 宽 `min(348, max(280, 屏宽 - 80))`、34 圆角、`panelSurface` 玻璃底
/// （24 高斯模糊）+ 0.5 hairline；标题居中 [BmTypographySet.section]，
/// 正文 [BmTypographySet.body] 次级色；动作是 48 高的胶囊按钮。
///
/// ```dart
/// showBmDialog<bool>(
///   context: context,
///   builder: (dialogContext) => BmDialog(
///     title: '退出登录',
///     message: '确定要退出登录吗？',
///     destructive: true,
///     actions: [
///       BmDialogAction(
///         label: '取消',
///         onPressed: () => Navigator.of(dialogContext).pop(false),
///       ),
///       BmDialogAction(
///         label: '退出登录',
///         onPressed: () => Navigator.of(dialogContext).pop(true),
///       ),
///     ],
///   ),
/// );
/// ```
class BmDialog extends StatelessWidget {
  const BmDialog({
    super.key,
    this.title,
    this.message,
    this.content,
    this.actions = const <BmDialogAction>[],
    this.destructive = false,
    this.hasFields = false,
  }) : assert(message != null || content != null, 'message 与 content 至少提供一个'),
       assert(message == null || content == null, 'message 与 content 只能二选一');

  /// 标题；为 null 时只显示正文。
  final String? title;

  /// 居中的次级正文，用于一两句确认文案。
  final String? message;

  /// 自定义内容，起始对齐（信息行、列表、输入框等）。
  final Widget? content;

  /// 底部动作按钮。
  final List<BmDialogAction> actions;

  /// 最后一个动作销毁数据：走 `danger` 文字而不是实底 accent。
  final bool destructive;

  /// 内容里有输入框：左右内边距收到 16，让输入框占满面板宽度。
  final bool hasFields;

  double _widthOf(MediaQueryData media) => math.min(
    BmTokens.dialogMaxWidth,
    math.max(
      BmTokens.dialogMinWidth,
      media.size.width - BmTokens.dialogScreenInset * 2,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final width = _widthOf(MediaQuery.of(context));
    final title = this.title;
    final content = this.content;
    final message = this.message;
    final inset = hasFields ? BmTokens.s4 : BmTokens.dialogTextInset;

    return SizedBox(
      width: width,
      child: BmChromeSurface(
        floating: true,
        tone: BmChromeTone.raised,
        radius: BmTokens.r34All,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BmTokens.dialogTextInset,
                    BmTokens.s5,
                    BmTokens.dialogTextInset,
                    0,
                  ),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: type.section.copyWith(color: colors.textPrimary),
                  ),
                ),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    inset,
                    title == null ? BmTokens.s5 : BmTokens.s1,
                    inset,
                    BmTokens.s5,
                  ),
                  child: DefaultTextStyle(
                    textAlign: content == null
                        ? TextAlign.center
                        : TextAlign.start,
                    style: type.body.copyWith(color: colors.textSecondary),
                    child: SingleChildScrollView(
                      child:
                          content ??
                          Text(message ?? '', textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BmTokens.s4,
                    0,
                    BmTokens.s4,
                    BmTokens.s4,
                  ),
                  child: _BmDialogActions(
                    actions: actions,
                    destructive: destructive,
                    maxWidth: width - BmTokens.s4 * 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 动作区：两个短文案并排，否则竖排（默认动作在上、取消在最下）。
class _BmDialogActions extends StatelessWidget {
  const _BmDialogActions({
    required this.actions,
    required this.destructive,
    required this.maxWidth,
  });

  final List<BmDialogAction> actions;
  final bool destructive;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // 单个动作不抢主色：关闭 / 知道了这类只有一件事可做的面板保持中性，
    // 两个以上动作时才把最后一个（默认动作）做成实底 accent。
    final hasDefault = actions.length > 1 && !destructive;
    if (_fitsSideBySide(context)) {
      // 两个胶囊等高：文字放大时按较高的一侧取高度。
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _action(context, 0, isDefault: false)),
            const SizedBox(width: BmTokens.s2),
            Expanded(
              child: _action(
                context,
                actions.length - 1,
                isDefault: hasDefault,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = actions.length - 1; index >= 0; index--) ...[
          _action(
            context,
            index,
            isDefault: hasDefault && index == actions.length - 1,
          ),
          if (index != 0) const SizedBox(height: BmTokens.s2),
        ],
      ],
    );
  }

  /// 两个动作、且两段文案都能只占一行放进半面板时才并排。
  bool _fitsSideBySide(BuildContext context) {
    if (actions.length != 2) return false;
    final style = context.bmType.bodyStrong;
    final available = (maxWidth - BmTokens.s2) / 2 - BmTokens.s4 * 2;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    for (final action in actions) {
      final painter = TextPainter(
        text: TextSpan(text: action.label, style: style),
        maxLines: 1,
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final fits = painter.width <= available;
      painter.dispose();
      if (!fits) return false;
    }
    return true;
  }

  Widget _action(BuildContext context, int index, {required bool isDefault}) {
    final colors = context.bmColors;
    final type = context.bmType;
    final action = actions[index];
    final enabled = action.enabled;
    final isDestructive = destructive && index == actions.length - 1;
    final foreground = !enabled
        ? colors.textTertiary
        : isDefault
        ? colors.onAccent
        : isDestructive
        ? colors.danger
        : colors.textPrimary;
    final style = (isDefault ? type.bodyStrong : type.body).copyWith(
      color: foreground,
      fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: BmTokens.row),
      decoration: BoxDecoration(
        color: enabled && isDefault ? colors.accent : colors.fillMuted,
        borderRadius: BmTokens.rPillAll,
      ),
      child: BmPressable(
        onTap: action.onPressed,
        enabled: enabled,
        borderRadius: BmTokens.rPillAll,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.s4,
              vertical: BmTokens.s2,
            ),
            child: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}
