import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Lucent 菜单行。
///
/// 桌面浮层菜单与移动端底部菜单共用：高 [BmTokens.menuRow]、左右内边距
/// [BmTokens.s2]；hover / pressed / selected / disabled 四态走 [BmPressable]，
/// 不自己画状态层、不做整行缩放。
///
/// ```dart
/// BmMenuRow(
///   title: '下一首',
///   leading: const Icon(Icons.skip_next),
///   shortcut: 'Ctrl+Right',
///   onTap: playNext,
/// )
/// ```
class BmMenuRow extends StatelessWidget {
  const BmMenuRow({
    super.key,
    required this.title,
    this.leading,
    this.shortcut,
    this.trailing,
    this.showChevron = false,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.height = BmTokens.menuRow,
  });

  /// 行标题。
  final String title;

  /// 行首图标或缩略图；通常传未定尺寸的 [Icon]，行内 [IconTheme] 兜 16。
  final Widget? leading;

  /// 行尾快捷键文案，例如 `Ctrl+C`。
  final String? shortcut;

  /// 行尾自定义控件（勾选标记、小进度等）。
  final Widget? trailing;

  /// 是否画子菜单箭头。
  final bool showChevron;

  final VoidCallback? onTap;

  /// 禁用态：整行降到 38% 且不响应点击。
  final bool enabled;

  /// 选中 / 键盘焦点态：accent 12% 底。
  final bool selected;

  /// 危险操作：文字与图标改用 [BmColors.danger]。
  final bool destructive;

  /// 行高，默认 [BmTokens.menuRow]；触屏菜单传 [BmTokens.touchScreen]。
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final titleColor = destructive ? colors.danger : colors.textPrimary;
    final iconColor = destructive ? colors.danger : colors.textSecondary;

    return BmPressable(
      onTap: onTap,
      enabled: enabled,
      selected: selected,
      borderRadius: BmTokens.r10All,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
          child: IconTheme(
            data: IconThemeData(size: BmTokens.iconMenu, color: iconColor),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: BmTokens.s2),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(color: titleColor),
                  ),
                ),
                if (shortcut != null) ...[
                  const SizedBox(width: BmTokens.s2),
                  Text(
                    shortcut!,
                    maxLines: 1,
                    style: type.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: BmTokens.s2),
                  trailing!,
                ],
                if (showChevron) ...[
                  const SizedBox(width: BmTokens.s2),
                  Icon(
                    Icons.chevron_right,
                    size: BmTokens.iconInline,
                    color: colors.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
