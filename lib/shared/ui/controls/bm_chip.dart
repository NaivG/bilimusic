import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Theater 胶囊：分类 chip、标签、筛选。
///
/// 高度 [BmTokens.chipHeight]，圆角胶囊；选中态是 `accent` 实底 + 白字，
/// 未选中是 `surfaceRaised` 底 + `hairline` 描边 + 次级文字。
class BmChip extends StatelessWidget {
  const BmChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// 更小的一档（标签行用），高度 21 → 20、字号 micro。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final height = dense ? BmTokens.chipHeight : BmTokens.chipHeight + 7;
    final style = dense ? type.micro : type.caption;
    final iconData = icon;

    return BmPressable(
      onTap: onTap,
      selected: selected,
      borderRadius: BmTokens.rPillAll,
      semanticLabel: label,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: dense ? BmTokens.s2 : BmTokens.s3,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.surfaceRaised,
          borderRadius: BmTokens.rPillAll,
          border: Border.all(
            color: selected ? colors.accent : colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              Icon(
                iconData,
                size: dense ? BmTokens.iconInline : BmTokens.iconMenu,
                color: selected ? colors.onAccent : colors.textSecondary,
              ),
              const SizedBox(width: BmTokens.s1),
            ],
            Text(
              label,
              style: style.copyWith(
                color: selected ? colors.onAccent : colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 只读标签：`accentSoft` 底 + `accentDeep` 字，不可点击。
class BmTag extends StatelessWidget {
  const BmTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      height: BmTokens.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BmTokens.rPillAll,
      ),
      alignment: Alignment.center,
      child: Text(label, style: type.micro.copyWith(color: colors.accentDeep)),
    );
  }
}
