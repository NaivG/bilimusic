import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Lucent 组件主题工厂。
///
/// 所有几何/颜色/字号都从 [BmTokens] / [BmColors] / [BmTypographySet] 取，
/// 6 套主题只需提供 [ColorScheme] + `AppPalette`，不再逐主题手写样式。
abstract class BmComponentThemes {
  /// AppBar：去掉 M3 的 surfaceTint，标题落到 `headline`。
  static AppBarThemeData appBar(BmColors colors, BmTypographySet type) {
    return AppBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: type.headline,
      iconTheme: IconThemeData(color: colors.textPrimary, size: BmTokens.icon),
      actionsIconTheme: IconThemeData(
        color: colors.textSecondary,
        size: BmTokens.icon,
      ),
    );
  }

  /// 对话框：20 圆角、`floating` 底、标题 headline / 正文 body。
  static DialogThemeData dialog(BmColors colors, BmTypographySet type) {
    return DialogThemeData(
      backgroundColor: colors.floating,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: colors.shadowStrong,
      shape: const RoundedRectangleBorder(borderRadius: BmTokens.r20All),
      titleTextStyle: type.headline,
      contentTextStyle: type.body,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s6,
        vertical: BmTokens.s6,
      ),
      barrierColor: colors.scrim,
    );
  }

  /// 底部单：顶部 20 圆角、36×4 handle、内容内边距 16/20。
  static BottomSheetThemeData sheet(BmColors colors) {
    return BottomSheetThemeData(
      backgroundColor: colors.floating,
      modalBackgroundColor: colors.floating,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(BmTokens.r20)),
      ),
      dragHandleColor: colors.textTertiary,
      dragHandleSize: const Size(36, 4),
      showDragHandle: false,
      modalBarrierColor: colors.scrim,
    );
  }

  /// 卡片：`surfaceRaised` + 10 圆角 + 无 elevation。
  static CardThemeData card(BmColors colors) {
    return CardThemeData(
      color: colors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BmTokens.r10All),
    );
  }

  static FilledButtonThemeData filledButton(
    BmColors colors,
    BmTypographySet type,
  ) {
    return FilledButtonThemeData(
      style: _buttonStyle(
        colors: colors,
        type: type,
        background: colors.accent,
        foreground: colors.onAccent,
      ),
    );
  }

  static TextButtonThemeData textButton(BmColors colors, BmTypographySet type) {
    return TextButtonThemeData(
      style: _buttonStyle(
        colors: colors,
        type: type,
        background: Colors.transparent,
        foreground: colors.accent,
        padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton(
    BmColors colors,
    BmTypographySet type,
  ) {
    return OutlinedButtonThemeData(
      style: _buttonStyle(
        colors: colors,
        type: type,
        background: Colors.transparent,
        foreground: colors.textPrimary,
        side: BorderSide(color: colors.hairline, width: 0.5),
      ),
    );
  }

  /// 过渡期兼容：页面里还有 44 处 `ElevatedButton`，风格先统一，
  /// 由 P2/P4 逐个换成 `BmButton`。
  static ElevatedButtonThemeData elevatedButton(
    BmColors colors,
    BmTypographySet type,
  ) {
    return ElevatedButtonThemeData(
      style: _buttonStyle(
        colors: colors,
        type: type,
        background: colors.surfaceRaised,
        foreground: colors.textPrimary,
        side: BorderSide(color: colors.hairline, width: 0.5),
      ),
    );
  }

  /// Chip：28 高胶囊、`surfaceRaised` 底 + hairline。
  static ChipThemeData chip(BmColors colors, BmTypographySet type) {
    return ChipThemeData(
      backgroundColor: colors.surfaceRaised,
      selectedColor: colors.accentSoft,
      disabledColor: colors.surfaceSunken,
      checkmarkColor: colors.accent,
      labelStyle: type.label.copyWith(color: colors.textPrimary),
      secondaryLabelStyle: type.label.copyWith(color: colors.textSecondary),
      side: BorderSide(color: colors.hairline, width: 0.5),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3, vertical: 0),
      labelPadding: const EdgeInsets.symmetric(horizontal: BmTokens.s1),
    );
  }

  /// Tooltip：Chrome 浮层，不再是系统的黑底直角。
  static TooltipThemeData tooltip(BmColors colors, BmTypographySet type) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.floating,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: BmTokens.s4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: type.caption.copyWith(color: colors.textPrimary),
      padding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s2,
        vertical: BmTokens.s1 + 2,
      ),
      waitDuration: const Duration(milliseconds: 500),
    );
  }

  /// 导航栏：高 56、`chrome` 底、选中 accent 12% 胶囊。
  static NavigationBarThemeData navBar(BmColors colors, BmTypographySet type) {
    return NavigationBarThemeData(
      height: 56,
      backgroundColor: colors.chrome,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: colors.accentSoft,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BmTokens.r10All,
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: BmTokens.icon,
          color: selected ? colors.accent : colors.textSecondary,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return type.micro.copyWith(
          color: selected ? colors.accent : colors.textSecondary,
        );
      }),
    );
  }

  /// 输入框：`surfaceSunken` 底、10 圆角、无外边框、focus 2px accentBorder。
  static InputDecorationThemeData input(BmColors colors, BmTypographySet type) {
    const radius = BmTokens.r10All;
    return InputDecorationThemeData(
      filled: true,
      fillColor: colors.surfaceSunken,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s3,
        vertical: 9,
      ),
      hintStyle: type.body.copyWith(color: colors.textTertiary),
      labelStyle: type.label.copyWith(color: colors.textSecondary),
      floatingLabelStyle: type.label.copyWith(color: colors.accent),
      errorStyle: type.caption.copyWith(color: colors.danger),
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.accentBorder, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger, width: 2),
      ),
    );
  }

  /// 分割线：0.5px hairline；只在「分组之间」出现。
  static DividerThemeData divider(BmColors colors) {
    return DividerThemeData(color: colors.hairline, thickness: 0.5, space: 0.5);
  }

  /// Slider：4px 轨道、12→16 thumb、已播放 accent / 未播放 hairline。
  static SliderThemeData slider(BmColors colors) {
    return SliderThemeData(
      trackHeight: 4,
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.hairline,
      thumbColor: colors.accent,
      overlayColor: colors.accent.withValues(alpha: BmAlpha.selected),
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 6,
        elevation: 0,
        pressedElevation: 0,
      ),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    );
  }

  static IconThemeData icon(BmColors colors) {
    return IconThemeData(size: BmTokens.icon, color: colors.textSecondary);
  }

  /// 过渡期兼容：`ListTile` 只允许出现在尚未迁移的页面，
  /// 但先把 68 处 `ListTile` 的行内层级（15/12）拉齐。
  static ListTileThemeData listTile(BmTypographySet type) {
    return ListTileThemeData(
      titleTextStyle: type.body,
      subtitleTextStyle: type.caption,
      leadingAndTrailingTextStyle: type.micro,
      minLeadingWidth: BmTokens.s4 + BmTokens.s6,
      contentPadding: const EdgeInsets.symmetric(horizontal: BmTokens.s4),
    );
  }

  /// Toast：浮动 + 圆角 + 四边留白，浮在迷你播放器 / 底部控制栏上方。
  ///
  /// 样式走主题而不是包一层 helper：调用点有上百处，主题能一次性覆盖
  /// 现有和以后所有 `ScaffoldMessenger.showSnackBar`。
  /// [SnackBarThemeData.contentTextStyle] 必须显式给：SnackBar 默认按
  /// `onInverseSurface` 取色，换底后不覆盖会在浅色主题下出现灰字压深底。
  static SnackBarThemeData snackBar(ColorScheme scheme, BmColors colors) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        // P0 保持既有 16 圆角（BmToast 的 14 在 P1 统一收口）
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        side: BorderSide(color: colors.hairline, width: 0.5),
      ),
      // 左右 16 让胶囊不顶边，底部 12 与底栏留一口气
      insetPadding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s4,
        vertical: BmTokens.s3,
      ),
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontFamilyFallback: BmTypography.fontFallback,
      ),
      actionTextColor: colors.accent,
      // 与 cardTheme / 导航栏一致走平面风格，不要高程染色
      elevation: 0,
    );
  }

  static TextSelectionThemeData textSelection(BmColors colors) {
    return TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSoft,
      selectionHandleColor: colors.accent,
    );
  }

  static ProgressIndicatorThemeData progress(BmColors colors) {
    return ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.hairline,
      circularTrackColor: colors.hairline,
    );
  }

  static ButtonStyle _buttonStyle({
    required BmColors colors,
    required BmTypographySet type,
    required Color background,
    required Color foreground,
    BorderSide? side,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: BmTokens.s4),
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(background),
      foregroundColor: WidgetStatePropertyAll(foreground),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return colors.statePressed;
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return colors.stateHover;
        }
        return null;
      }),
      textStyle: WidgetStatePropertyAll(type.label),
      padding: WidgetStatePropertyAll(padding),
      minimumSize: const WidgetStatePropertyAll(Size(0, BmTokens.controlLg)),
      // 40 高控件不再被 Material 的 48 触摸区撑开
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      elevation: const WidgetStatePropertyAll(0),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BmTokens.r10All),
      ),
      side: side == null ? null : WidgetStatePropertyAll(side),
      animationDuration: BmMotion.small,
      splashFactory: NoSplash.splashFactory,
    );
  }
}
