import 'package:flutter/material.dart';

import 'lucent_theme.dart';
import 'nocturne_theme.dart';
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
  String? get subtitle => 'iOS 风格 · 暖灰底 · 紫色 accent';

  @override
  ThemeData light() => LucentTheme.lightTheme();
  @override
  ThemeData dark() => LucentTheme.darkTheme();

  @override
  Color paletteAccent(Brightness brightness) => LucentColors.accentPrimary;

  @override
  Color paletteSurface(Brightness brightness) =>
      brightness == Brightness.light
          ? LucentColors.lightSurfaceBase
          : LucentColors.darkSurfaceBase;
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
  Color paletteAccent(Brightness brightness) =>
      brightness == Brightness.light
          ? NocturneColors.primaryLight
          : NocturneColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) =>
      brightness == Brightness.light
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
  Color paletteAccent(Brightness brightness) =>
      brightness == Brightness.light
          ? VerdantColors.primaryLight
          : VerdantColors.primaryDark;

  @override
  Color paletteSurface(Brightness brightness) =>
      brightness == Brightness.light
          ? VerdantColors.surfaceLight
          : VerdantColors.surfaceDark;
}

/// 主题注册表 —— 提供稳定顺序的 [AppThemeDescriptor] 列表。
class ThemeRegistry {
  ThemeRegistry._();

  static final List<AppThemeDescriptor> all = [
    _LucentDescriptor(),
    _NocturneDescriptor(),
    _VerdantDescriptor(),
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