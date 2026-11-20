import 'package:flutter/material.dart';

import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/overlay/bm_select_menu.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

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

/// 主题单选浮层的条目：色点 + 名称 + 风格描述。
List<BmSelectOption<String>> themeSelectOptions() {
  return [
    for (final descriptor in ThemeRegistry.all)
      BmSelectOption(
        value: descriptor.id,
        label: descriptor.label,
        subtitle: descriptor.subtitle,
        leading: ThemePaletteDots(descriptor: descriptor),
      ),
  ];
}
