import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 色点预览：浅色 accent / 浅色 surface / 暗色 accent。
class ThemePaletteDots extends StatelessWidget {
  const ThemePaletteDots({super.key, required this.descriptor});

  final AppThemeDescriptor descriptor;

  static const double _dot = 9;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(
          color: descriptor.paletteAccent(Brightness.light),
          borderColor: colors.hairline,
        ),
        const SizedBox(width: BmTokens.s1),
        _Dot(
          color: descriptor.paletteSurface(Brightness.light),
          borderColor: colors.hairline,
        ),
        const SizedBox(width: BmTokens.s1),
        _Dot(
          color: descriptor.paletteAccent(Brightness.dark),
          borderColor: colors.hairline,
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ThemePaletteDots._dot,
      height: ThemePaletteDots._dot,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: BmTokens.hairlineWidth),
      ),
    );
  }
}

/// 主题选择对话框；选中后回调主题 id。
Future<void> showThemePicker({
  required BuildContext context,
  required String currentThemeId,
  required ValueChanged<String> onSelected,
}) async {
  final selected = await showBmDialog<String>(
    context: context,
    builder: (dialogContext) => BmDialog(
      title: '选择主题',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final descriptor in ThemeRegistry.all)
            _ThemeOptionTile(
              descriptor: descriptor,
              selected: descriptor.id == currentThemeId,
              onTap: () => Navigator.of(dialogContext).pop(descriptor.id),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
  if (selected != null) onSelected(selected);
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.descriptor,
    required this.selected,
    required this.onTap,
  });

  final AppThemeDescriptor descriptor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final subtitle = descriptor.subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: BmTokens.s1),
      child: BmPressable(
        onTap: onTap,
        borderRadius: BmTokens.r14All,
        selected: selected,
        selectedColor: colors.accentSoft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: BmTokens.settingRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.s3,
              vertical: BmTokens.s2,
            ),
            child: Row(
              children: [
                ThemePaletteDots(descriptor: descriptor),
                const SizedBox(width: BmTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        descriptor.label,
                        style: type.bodyStrong.copyWith(
                          color: selected
                              ? colors.accentDeep
                              : colors.textPrimary,
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
      ),
    );
  }
}
