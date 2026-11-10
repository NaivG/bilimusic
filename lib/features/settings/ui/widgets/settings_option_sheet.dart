import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/overlay/bm_sheet.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 设置项的单选条目。
@immutable
class BmSettingsOption<T> {
  const BmSettingsOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

/// 底部单选列表；返回选中值，直接关闭时返回 null。
Future<T?> showSettingsOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<BmSettingsOption<T>> options,
  required T selected,
}) {
  return showBmSheet<T>(
    context: context,
    builder: (sheetContext) {
      final colors = sheetContext.bmColors;
      final type = sheetContext.bmType;
      return BmSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: BmTokens.s2,
                bottom: BmTokens.s2,
              ),
              child: Text(
                title,
                style: type.title.copyWith(color: colors.textPrimary),
              ),
            ),
            for (final option in options)
              _OptionRow<T>(
                option: option,
                selected: option.value == selected,
                onTap: () => Navigator.of(sheetContext).pop(option.value),
              ),
          ],
        ),
      );
    },
  );
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final BmSettingsOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final subtitle = option.subtitle;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r14All,
      selected: selected,
      selectedColor: colors.accentSoft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: BmTokens.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s3,
            vertical: BmTokens.s1,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      style: type.body.copyWith(
                        color: selected
                            ? colors.accentDeep
                            : colors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: BmTokens.icon,
                  color: colors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
