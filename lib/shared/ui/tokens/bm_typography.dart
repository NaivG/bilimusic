import 'package:flutter/material.dart';

/// Lucent 排版 token：8 档字号 / 字重 / 行高。
///
/// 字体栈用系统默认 + 一组 CJK 友好的 fallback，不自带 CJK 字体。
/// 组件通过 `context.bmType` 读取；[theme] 把 8 档铺满 Material 的 15 个
/// [TextTheme] 槽位，让还没迁移的页面也落到同一套字号上。
abstract class BmTypography {
  /// 字体 fallback 栈：与 [ThemeData.fontFamilyFallback] 一致。
  static const List<String> fontFallback = <String>[
    'Segoe UI Variable Text',
    'Segoe UI',
    'HarmonyOS Sans SC',
    'MiSans',
    'Noto Sans CJK SC',
    'Microsoft YaHei UI',
  ];

  /// 舞台大标题（详情页曲名，大屏）28/34 w700。
  static TextStyle display(Color? color) =>
      _style(color, 28, 34, FontWeight.w700);

  /// 详情页曲名、空态标题 22/28 w700。
  static TextStyle title(Color? color) =>
      _style(color, 22, 28, FontWeight.w700);

  /// 页面标题、对话框标题、分组标题 17/24 w600。
  static TextStyle headline(Color? color) =>
      _style(color, 17, 24, FontWeight.w600);

  /// 正文、列表主标题 15/22 w400。
  static TextStyle body(Color? color) => _style(color, 15, 22, FontWeight.w400);

  /// 列表主标题强调、当前播放 15/22 w600。
  static TextStyle bodyStrong(Color? color) =>
      _style(color, 15, 22, FontWeight.w600);

  /// 按钮、Tab、次要操作 13/18 w500。
  static TextStyle label(Color? color) =>
      _style(color, 13, 18, FontWeight.w500);

  /// 次要信息、歌手名、时间 12/16 w400。
  static TextStyle caption(Color? color) =>
      _style(color, 12, 16, FontWeight.w400);

  /// 徽标、HQ、迷你播放器辅助 11/14 w500。
  static TextStyle micro(Color? color) =>
      _style(color, 11, 14, FontWeight.w500);

  /// 把 8 档铺进 Material 的 15 个槽位。
  static TextTheme theme(ColorScheme scheme) {
    final primary = scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;
    final displayStyle = display(primary);
    final titleStyle = title(primary);
    final headlineStyle = headline(primary);
    final bodyStyle = body(primary);
    final bodyStrongStyle = bodyStrong(primary);
    final labelStyle = label(primary);
    final captionStyle = caption(secondary);
    final microStyle = micro(secondary);
    return TextTheme(
      displayLarge: displayStyle,
      displayMedium: displayStyle,
      displaySmall: displayStyle,
      headlineLarge: titleStyle,
      headlineMedium: titleStyle,
      headlineSmall: headlineStyle,
      titleLarge: headlineStyle,
      titleMedium: bodyStrongStyle,
      titleSmall: labelStyle,
      bodyLarge: bodyStyle,
      bodyMedium: bodyStyle,
      bodySmall: captionStyle,
      labelLarge: labelStyle,
      labelMedium: captionStyle,
      labelSmall: microStyle,
    );
  }

  /// 数字等宽：时间、进度、音质码率用，避免跳动。
  static TextStyle numeric(TextStyle style) {
    return style.copyWith(
      fontFeatures: <FontFeature>[
        ...?style.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
    );
  }

  static TextStyle _style(
    Color? color,
    double fontSize,
    double lineHeight,
    FontWeight weight,
  ) {
    return TextStyle(
      fontSize: fontSize,
      height: lineHeight / fontSize,
      fontWeight: weight,
      color: color,
      fontFamilyFallback: fontFallback,
    );
  }
}

/// 一次 build 内复用的 8 档样式（按当前 [ColorScheme] 取色）。
@immutable
class BmTypographySet {
  final TextStyle display;
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle micro;

  const BmTypographySet({
    required this.display,
    required this.title,
    required this.headline,
    required this.body,
    required this.bodyStrong,
    required this.label,
    required this.caption,
    required this.micro,
  });

  factory BmTypographySet.resolve(ColorScheme scheme) {
    final primary = scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;
    return BmTypographySet(
      display: BmTypography.display(primary),
      title: BmTypography.title(primary),
      headline: BmTypography.headline(primary),
      body: BmTypography.body(primary),
      bodyStrong: BmTypography.bodyStrong(primary),
      label: BmTypography.label(primary),
      caption: BmTypography.caption(secondary),
      micro: BmTypography.micro(secondary),
    );
  }
}

extension BmTypographyContext on BuildContext {
  BmTypographySet get bmType =>
      BmTypographySet.resolve(Theme.of(this).colorScheme);
}
