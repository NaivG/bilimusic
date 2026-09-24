import 'package:flutter/material.dart';

import 'gruvbox_theme.dart';
import 'lucent_theme.dart';
import 'nocturne_theme.dart';
import 'nord_theme.dart';
import 'solarized_theme.dart';
import 'verdant_theme.dart';

/// 主题描述符 —— 在设置页选择器中渲染色板预览,以及给 [MaterialApp] 提供
/// light/dark ThemeData。
abstract class AppThemeDescriptor {
  String get id;
  String get label;
  String? get subtitle;

  ThemeData light();
  ThemeData dark();

  /// 用于设置页色板预览:浅色模式下的主 accent。
  Color paletteAccent(Brightness brightness);

  /// 用于设置页色板预览:浅色/暗色模式下的 surface。
  Color paletteSurface(Brightness brightness);
}

class _LucentDescriptor extends AppThemeDescriptor {
  @override
  String get id => 'lucent';
  @override
  String get label => 'Lucent (默认)';
  @override
  String? get subtitle => 'iOS 风格 · 暖灰底 · 湖水青 accent';

  @override
  ThemeData light() => LucentTheme.lightTheme();
  @override
  ThemeData dark() => LucentTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => brightness == Brightness.light
      ? LucentColors.primaryLight
      : LucentColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) => brightness == Brightness.light
      ? LucentColors.surfaceLight
      : LucentColors.surfaceDark;
}

class _NocturneDescriptor extends AppThemeDescriptor {
  @override
  String get id => 'nocturne';
  @override
  String get label => 'Nocturne';
  @override
  String? get subtitle => '极简风格 · 真黑底 · 深空蓝 accent';

  @override
  ThemeData light() => NocturneTheme.lightTheme();
  @override
  ThemeData dark() => NocturneTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => brightness == Brightness.light
      ? NocturneColors.primaryLight
      : NocturneColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) => brightness == Brightness.light
      ? NocturneColors.surfaceLight
      : NocturneColors.surfaceDark;
}

class _VerdantDescriptor extends AppThemeDescriptor {
  @override
  String get id => 'verdant';
  @override
  String get label => 'Verdant';
  @override
  String? get subtitle => '自然风格 · 米纸底 · 青竹绿 accent';

  @override
  ThemeData light() => VerdantTheme.lightTheme();
  @override
  ThemeData dark() => VerdantTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => brightness == Brightness.light
      ? VerdantColors.primaryLight
      : VerdantColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) => brightness == Brightness.light
      ? VerdantColors.surfaceLight
      : VerdantColors.surfaceDark;
}

class _SolarizedDescriptor extends AppThemeDescriptor {
  @override
  String get id => 'solarized';
  @override
  String get label => 'Solarized';
  @override
  String? get subtitle => '经典调色板 · 米纸底 · 深蓝/亮青 accent';

  @override
  ThemeData light() => SolarizedTheme.lightTheme();
  @override
  ThemeData dark() => SolarizedTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => brightness == Brightness.light
      ? SolarizedColors.primaryLight
      : SolarizedColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) => brightness == Brightness.light
      ? SolarizedColors.surfaceLight
      : SolarizedColors.surfaceDark;
}

class _NordDescriptor extends AppThemeDescriptor {
  @override
  String get id => 'nord';
  @override
  String get label => 'Nord';
  @override
  String? get subtitle => '极地冰雪 · 雪暴白/极夜底 · 冻蓝/冻青 accent';

  @override
  ThemeData light() => NordTheme.lightTheme();
  @override
  ThemeData dark() => NordTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => brightness == Brightness.light
      ? NordColors.primaryLight
      : NordColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) => brightness == Brightness.light
      ? NordColors.surfaceLight
      : NordColors.surfaceDark;
}

class _GruvboxDescriptor extends AppThemeDescriptor {
  @override
  String get id => 'gruvbox';
  @override
  String get label => 'Gruvbox';
  @override
  String? get subtitle => '复古暖调 · 米色/深棕底 · 暖橙 accent';

  @override
  ThemeData light() => GruvboxTheme.lightTheme();
  @override
  ThemeData dark() => GruvboxTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => brightness == Brightness.light
      ? GruvboxColors.primaryLight
      : GruvboxColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) => brightness == Brightness.light
      ? GruvboxColors.surfaceLight
      : GruvboxColors.surfaceDark;
}

/// 主题注册表 —— 提供稳定顺序的 [AppThemeDescriptor] 列表。
class ThemeRegistry {
  ThemeRegistry._();

  static final List<AppThemeDescriptor> all = [
    _LucentDescriptor(),
    _NocturneDescriptor(),
    _VerdantDescriptor(),
    _SolarizedDescriptor(),
    _NordDescriptor(),
    _GruvboxDescriptor(),
  ];

  static final Map<String, AppThemeDescriptor> _byId = {
    for (final t in all) t.id: t,
  };

  static AppThemeDescriptor get defaultTheme => all.first;

  static AppThemeDescriptor resolve(String? id) {
    if (id == null) return defaultTheme;
    return _byId[id] ?? defaultTheme;
  }
}
