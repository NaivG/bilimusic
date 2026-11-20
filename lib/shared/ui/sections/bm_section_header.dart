import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Theater 分区标题：`section` 21/27 + 右侧可选动作。
///
/// 替代之前并存的多套写法（竖条 + 标题 / headlineSmall / 16 bold）。
/// 左右内边距由调用方给（竖屏 20/22，横屏内容区 30）；默认上下 28 / 12。
class BmSectionHeader extends StatelessWidget {
  const BmSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onMore,
    this.showChevron = false,
    this.padding,
  });

  final String title;

  /// 自定义右侧内容；与 [onMore] 二选一。
  final Widget? trailing;

  /// 「查看全部」文本按钮。
  final VoidCallback? onMore;

  /// 标题后是否跟一个 chevron（设计稿 `.sec-title .chev`）。
  final bool showChevron;

  /// 覆盖默认上下内边距。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final action =
        trailing ?? (onMore == null ? null : _MoreAction(onTap: onMore!));
    return Padding(
      padding:
          padding ??
          const EdgeInsets.only(top: BmTokens.s6, bottom: BmTokens.s3),
      child: Row(
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.section.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (showChevron) ...[
                  const SizedBox(width: BmTokens.s1),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: BmTokens.iconMenu,
                    color: colors.textTertiary,
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: BmTokens.s2), action],
        ],
      ),
    );
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r10All,
      semanticLabel: '查看全部',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '查看全部',
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: BmTokens.s1 / 2),
            Icon(
              Icons.chevron_right_rounded,
              size: BmTokens.iconMenu,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
