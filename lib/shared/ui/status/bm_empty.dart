import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Theater 空态 / 错误态：图标 + 标题 + 说明 + 可选动作。
///
/// 页面级空态用 `large`（图标 48），区块内空态用 `small`（图标 32）。
class BmEmptyState extends StatelessWidget {
  const BmEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Widget? action;

  /// 紧凑档：用于分区内部的空态。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final iconData = icon;
    final messageText = message;
    final actionWidget = action;
    final glyph = compact ? BmTokens.s8 : BmTokens.s8 * 2;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: BmTokens.s6,
          vertical: compact ? BmTokens.s5 : BmTokens.s8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              Container(
                width: glyph,
                height: glyph,
                decoration: BoxDecoration(
                  color: colors.bgDeep,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  iconData,
                  size: glyph * 0.5,
                  color: colors.textTertiary,
                ),
              ),
              SizedBox(height: compact ? BmTokens.s2 : BmTokens.s4),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: (compact ? type.bodyStrong : type.section).copyWith(
                color: colors.textPrimary,
              ),
            ),
            if (messageText != null) ...[
              const SizedBox(height: BmTokens.s1),
              Text(
                messageText,
                textAlign: TextAlign.center,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
            if (actionWidget != null) ...[
              const SizedBox(height: BmTokens.s4),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }
}
