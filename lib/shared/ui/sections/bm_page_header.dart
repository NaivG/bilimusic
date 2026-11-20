import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Theater 页头：小字 eyebrow + `display` 36/42 大标题 + 右侧动作。
///
/// 竖屏内边距 22/16、横屏由壳层内容区给；替代各页自建的标题行。
class BmPageHeader extends StatelessWidget {
  const BmPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions,
    this.padding,
  });

  /// 大标题（36/42）。
  final String title;

  /// 标题上方的小字（日期 / 版本号 / 面包屑）。
  final String? eyebrow;

  /// 标题下方的一行说明。
  final String? subtitle;

  /// 右侧动作（搜索圆钮、头像、ghost 按钮）。
  final List<Widget>? actions;

  /// 覆盖默认内边距。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final eyebrowText = eyebrow;
    final subtitleText = subtitle;
    final actionsList = actions;
    return Padding(
      padding:
          padding ??
          const EdgeInsets.only(top: BmTokens.s4, bottom: BmTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrowText != null)
                  Text(
                    eyebrowText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                const SizedBox(height: BmTokens.s1 / 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.display.copyWith(color: colors.textPrimary),
                ),
                if (subtitleText != null) ...[
                  const SizedBox(height: BmTokens.s1),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (actionsList != null && actionsList.isNotEmpty) ...[
            const SizedBox(width: BmTokens.s3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actionsList.length; i++) ...[
                  if (i > 0) const SizedBox(width: BmTokens.s2),
                  actionsList[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
