import 'package:flutter/material.dart';

/// Theater 排版 token：8 档字号 / 字重 / 行高。
///
/// 字体栈用系统默认 + 一组 CJK 友好的 fallback，不自带 CJK 字体。
/// 组件通过 `context.bmType` 读取；[theme] 把 8 档铺满 Material 的 15 个
/// [TextTheme] 槽位，让还没迁移的页面也落到同一套字号上。
///
/// | token | 字号 / 行高 / 字重 | 场景 |
/// |---|---|---|
/// | display | 36 / 42 / 800 | 页面大标题、问候、设置页标题 |
/// | title | 24 / 30 / 700 | 详情标题、弹层标题、抽屉标题 |
/// | section | 21 / 27 / 700 | 分区标题 |
/// | body | 15 / 21 / 400 | 正文、列表主标题、设置行 |
/// | bodyStrong | 15 / 21 / 600 | 强调、当前播放 |
/// | label | 13 / 19 / 500 | 曲目行、按钮、Tab |
/// | caption | 12 / 17 / 400 | 副标题、说明 |
/// | micro | 10.5 / 15 / 500 | 时间、badge、脚注 |
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

  /// 页面大标题 / 问候 36/42 w800。
  static TextStyle display(Color? color) =>
      _style(color, 36, 42, FontWeight.w800, -1.6);

  /// 详情标题、弹层标题、抽屉标题 24/30 w700。
  static TextStyle title(Color? color) =>
      _style(color, 24, 30, FontWeight.w700, -0.7);

  /// 分区标题 21/27 w700。
  static TextStyle section(Color? color) =>
      _style(color, 21, 27, FontWeight.w700, -0.5);

  /// 正文、列表主标题、设置行 15/21 w400。
  static TextStyle body(Color? color) =>
      _style(color, 15, 21, FontWeight.w400, -0.1);

  /// 强调、当前播放 15/21 w600。
  static TextStyle bodyStrong(Color? color) =>
      _style(color, 15, 21, FontWeight.w600, -0.1);

  /// 曲目行、按钮、Tab 13/19 w500。
  static TextStyle label(Color? color) =>
      _style(color, 13, 19, FontWeight.w500, 0);

  /// 副标题、说明 12/17 w400。
  static TextStyle caption(Color? color) =>
      _style(color, 12, 17, FontWeight.w400, 0);

  /// 时间、badge、脚注 10.5/15 w500。
  static TextStyle micro(Color? color) =>
      _style(color, 10.5, 15, FontWeight.w500, 0.1);

  /// 把 8 档铺进 Material 的 15 个槽位。
  static TextTheme theme(ColorScheme scheme) {
    final primary = scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;
    final displayStyle = display(primary);
    final titleStyle = title(primary);
    final sectionStyle = section(primary);
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
      headlineSmall: sectionStyle,
      titleLarge: sectionStyle,
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
    double letterSpacing,
  ) {
    return TextStyle(
      fontSize: fontSize,
      height: lineHeight / fontSize,
      fontWeight: weight,
      letterSpacing: letterSpacing,
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
  final TextStyle section;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle micro;

  const BmTypographySet({
    required this.display,
    required this.title,
    required this.section,
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
      section: BmTypography.section(primary),
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
