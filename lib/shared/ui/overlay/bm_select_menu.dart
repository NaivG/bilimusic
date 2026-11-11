import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_overlay_routes.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 锚定单选浮层的条目。
@immutable
class BmSelectOption<T> {
  const BmSelectOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
    this.enabled = true,
    this.sectionTitle,
  });

  final T value;
  final String label;

  /// 第二行说明；有值时行高从 44 长到 48。
  final String? subtitle;

  /// 行首控件（主题选择器的色点等）。
  final Widget? leading;

  /// 为 false 时行降到禁用态且不可选。
  final bool enabled;

  /// 分组标题：非空时在这一行上方先画一行小标题。
  ///
  /// 多组选项只给每组第一项设置；标题只做分隔，不参与选择。
  final String? sectionTitle;
}

/// iOS 风味锚定单选浮层。
///
/// 从 [anchorContext] 所在控件的下方弹出（下方空间不足时翻到上方），
/// 面板右缘与锚点右缘对齐；默认宽 [BmTokens.selectMenuWidth]，最大高
/// [BmTokens.selectMenuMaxHeight]，超出后内部滚动。选中项只在行尾画
/// accent 对勾，不铺整行选中底；[selected] 为 null 时都不画，选项可用
/// [BmSelectOption.sectionTitle] 分组。
///
/// 动画走 Lucent 菜单入场：120ms scale 0.96→1 + fade
/// （[BmMotion.small] / [BmMotion.emphasized]），缩放锚点是面板贴近锚点的
/// 那个角；reduce motion 下只保留透明度过渡。
Future<T?> showBmSelectMenu<T>({
  required BuildContext anchorContext,
  required List<BmSelectOption<T>> options,
  required T? selected,
  double? width,
  double maxHeightFactor = 0.66,
  bool isDismissible = true,
}) {
  assert(options.isNotEmpty, '单选浮层至少要有一个选项');
  final media = MediaQuery.of(anchorContext);
  final anchor = _anchorRectOf(anchorContext, media.size);
  final estimatedHeight = _estimatedMenuHeight(anchorContext, options);
  final opensUp = _prefersOpenUp(
    media: media,
    anchor: anchor,
    estimatedHeight: estimatedHeight,
    maxHeightFactor: maxHeightFactor,
  );
  return Navigator.of(anchorContext).push<T>(
    BmSelectMenuRoute<T>(
      anchorRect: anchor,
      opensUp: opensUp,
      width: width,
      maxHeightFactor: maxHeightFactor,
      theme: Theme.of(anchorContext),
      barrierLabel: MaterialLocalizations.of(anchorContext)
          .modalBarrierDismissLabel,
      barrierDismissible: isDismissible,
      reduceMotion: reduceMotionOf(anchorContext),
      builder: (menuContext) => BmSelectMenu<T>(
        options: options,
        selected: selected,
        onSelected: (value) => Navigator.of(menuContext).pop(value),
      ),
    ),
  );
}

/// 锚定单选浮层面板。
///
/// 单独拿出来用于预览页 / 测试；正常调用走 [showBmSelectMenu]。
class BmSelectMenu<T> extends StatelessWidget {
  const BmSelectMenu({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<BmSelectOption<T>> options;

  /// 当前值；为 null 时没有任何行画对勾。
  final T? selected;

  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return BmMenuSurface(
      child: SingleChildScrollView(
        primary: false,
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options) ...[
              if (option.sectionTitle != null)
                _BmSelectSectionHeader(title: option.sectionTitle!),
              _BmSelectMenuRow<T>(
                option: option,
                selected: option.value == selected,
                onTap: option.enabled ? () => onSelected(option.value) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 紧凑的下拉触发按钮（音频输出页这类自定义卡片用）。
///
/// 只负责「当前值 + 上下箭头」的外观与锚定，不承担行布局。
class BmSelectTrigger<T> extends StatelessWidget {
  const BmSelectTrigger({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.menuWidth,
    this.maxLabelWidth = 160,
    this.semanticLabel,
  });

  final String label;
  final List<BmSelectOption<T>> options;

  /// 当前值；为 null / 不在 [options] 里时浮层不画对勾。
  final T? selected;

  final ValueChanged<T> onSelected;
  final bool enabled;
  final double? menuWidth;

  /// 当前值最长宽度；超出省略，避免把卡片标题挤没。
  final double maxLabelWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      child: Builder(
        builder: (anchorContext) => BmPressable(
          onTap: enabled
              ? () async {
                  final value = await showBmSelectMenu<T>(
                    anchorContext: anchorContext,
                    options: options,
                    selected: selected,
                    width: menuWidth,
                  );
                  if (value == null || value == selected) return;
                  onSelected(value);
                }
              : null,
          enabled: enabled,
          borderRadius: BmTokens.r10All,
          semanticLabel: semanticLabel ?? label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: BmTokens.touchDesktop),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BmTokens.s2,
                vertical: BmTokens.s1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxLabelWidth),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: BmTokens.s1),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: BmTokens.iconMenu,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BmSelectMenuRow<T> extends StatelessWidget {
  const _BmSelectMenuRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final BmSelectOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final subtitle = option.subtitle;
    final enabled = option.enabled;
    return BmPressable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: BmTokens.r10All,
      semanticLabel: option.label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: BmTokens.touchScreen),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s3,
            vertical: BmTokens.s1,
          ),
          child: Center(
            child: Row(
              children: [
                if (option.leading != null) ...[
                  option.leading!,
                  const SizedBox(width: BmTokens.s3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.body.copyWith(
                          color: enabled
                              ? colors.textPrimary
                              : colors.textTertiary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: BmTokens.s1 / 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: BmTokens.s2),
                SizedBox(
                  width: BmTokens.icon,
                  height: BmTokens.icon,
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: BmTokens.icon,
                          color: colors.accent,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 锚点控件的全局矩形；取不到时退回屏幕顶部中央的一个零宽点。
Rect _anchorRectOf(BuildContext context, Size screen) {
  final object = context.findRenderObject();
  if (object is RenderBox && object.hasSize) {
    return object.localToGlobal(Offset.zero) & object.size;
  }
  return Rect.fromLTWH(screen.width / 2, screen.height / 2, 0, 0);
}

/// 选项分组小标题：只做分隔，不参与选择。
class _BmSelectSectionHeader extends StatelessWidget {
  const _BmSelectSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BmTokens.s3,
        BmTokens.s2,
        BmTokens.s3,
        BmTokens.s1 / 2,
      ),
      child: Semantics(
        header: true,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.label.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// 估算面板高度，只用于决定弹出方向（实际布局由路由按可用空间夹取）。
double _estimatedMenuHeight<T>(
  BuildContext context,
  List<BmSelectOption<T>> options,
) {
  final type = context.bmType;
  final scaler = MediaQuery.textScalerOf(context);
  final bodyLine =
      scaler.scale(type.body.fontSize ?? 15) * (type.body.height ?? 1.4);
  final captionLine =
      scaler.scale(type.caption.fontSize ?? 12) * (type.caption.height ?? 1.42);
  final sectionLine =
      scaler.scale(type.label.fontSize ?? 13) * (type.label.height ?? 1.46);
  var height = BmTokens.menuInset * 2;
  for (final option in options) {
    if (option.sectionTitle != null) {
      height += sectionLine + BmTokens.s2 + BmTokens.s1 / 2;
    }
    final content =
        bodyLine +
        (option.subtitle == null ? 0 : BmTokens.s1 / 2 + captionLine) +
        BmTokens.s1 * 2;
    height += math.max(BmTokens.touchScreen, content);
  }
  return height;
}

bool _prefersOpenUp({
  required MediaQueryData media,
  required Rect anchor,
  required double estimatedHeight,
  required double maxHeightFactor,
}) {
  final gap = BmTokens.s1;
  final safeTop = media.padding.top;
  final safeBottom = media.size.height - media.padding.bottom;
  final cap = math.min(
    media.size.height * maxHeightFactor,
    BmTokens.selectMenuMaxHeight,
  );
  final height = math.min(estimatedHeight, cap);
  final below = safeBottom - anchor.bottom - gap;
  final above = anchor.top - gap - safeTop;
  return height > below && above > below;
}
