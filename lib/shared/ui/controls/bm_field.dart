import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Lucent 输入框。
///
/// 高 [BmTokens.controlLg]，圆角 [BmTokens.r10All]，`surfaceSunken` 填充，
/// 静息无外边框；focus 时 2px `accentBorder`，错误时 `danger` 边框并在
/// 输入框下方给 `caption` 提示。label 在输入框上方，[leading] / [trailing]
/// 传未定尺寸的 [Icon] 时按 [BmTokens.icon] 渲染。
///
/// ```dart
/// BmField(
///   hintText: '搜索',
///   leading: const Icon(Icons.search),
///   onSubmitted: search,
/// )
/// ```
class BmField extends StatelessWidget {
  const BmField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.label,
    this.errorText,
    this.leading,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.width,
    this.textInputAction,
    this.keyboardType,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;

  /// 输入框上方的标题，`label` 13/18。
  final String? label;

  /// 错误提示：非空时输入框走 `danger` 边框，并在下方显示 12/16 文案。
  final String? errorText;

  /// 行首控件；通常传未定尺寸的 [Icon]。
  final Widget? leading;

  /// 行尾控件；通常传未定尺寸的 [Icon] 或 BmIconButton。
  final Widget? trailing;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;

  /// 固定宽度；为 null 时按父级约束自适应。
  final double? width;

  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;

  /// 40 高的输入框里，图标区域不能吃 Material 默认的 48 最小触摸尺寸。
  static const BoxConstraints _iconConstraints = BoxConstraints(
    minWidth: BmTokens.controlLg,
    minHeight: BmTokens.controlLg,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final hasError = errorText != null;

    const idleBorder = OutlineInputBorder(
      borderRadius: BmTokens.r10All,
      borderSide: BorderSide.none,
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: BmTokens.r10All,
      borderSide: BorderSide(color: colors.danger),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BmTokens.r10All,
      borderSide: BorderSide(color: colors.accentBorder, width: 2),
    );
    final focusedErrorBorder = OutlineInputBorder(
      borderRadius: BmTokens.r10All,
      borderSide: BorderSide(color: colors.danger, width: 2),
    );

    final field = SizedBox(
      height: BmTokens.controlLg,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        style: type.body.copyWith(color: colors.textPrimary),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.surfaceSunken,
          isDense: true,
          hintText: hintText,
          hintStyle: type.body.copyWith(color: colors.textTertiary),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s3,
            vertical: BmTokens.s2,
          ),
          // 错误提示由 BmField 自己画在输入框下方，40 高不被撑开；
          // 错误态边框按 errorText 直接选，保证不依赖 InputDecorator 的错误行。
          border: hasError ? errorBorder : idleBorder,
          enabledBorder: hasError ? errorBorder : idleBorder,
          disabledBorder: idleBorder,
          focusedBorder: hasError ? focusedErrorBorder : focusedBorder,
          errorBorder: errorBorder,
          focusedErrorBorder: focusedErrorBorder,
          prefixIcon: _icon(leading, colors),
          suffixIcon: _icon(trailing, colors),
          prefixIconConstraints: _iconConstraints,
          suffixIconConstraints: _iconConstraints,
        ),
      ),
    );

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.label.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: BmTokens.s1),
          ],
          field,
          if (errorText != null) ...[
            const SizedBox(height: BmTokens.s1),
            Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget? _icon(Widget? icon, BmColors colors) {
    if (icon == null) return null;
    return IconTheme(
      data: IconThemeData(size: BmTokens.icon, color: colors.textSecondary),
      child: icon,
    );
  }
}
