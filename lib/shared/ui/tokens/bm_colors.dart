import 'package:flutter/material.dart';

import 'package:bilimusic/shared/theme/app_palette.dart';

/// Theater 颜色角色。
///
/// 主题文件只负责「角色 → 色值」（[ColorScheme] + [AppPalette]），
/// [BmColors.resolve] 负责「色值 → 用途角色」；组件只读角色，不写色值。
/// 透明度只用 [BmAlpha] 里的固定值。
@immutable
class BmColors extends ThemeExtension<BmColors> {
  // ===== 表面 =====
  /// 页面底（暖纸白）。
  final Color bg;

  /// 内容面。Theater 下与 [bg] 同值，语义留给后续分层。
  final Color surface;

  /// 卡片、行、白卡。
  final Color surfaceRaised;

  /// 输入框、搜索框。
  final Color surfaceSunken;

  /// 次级面：占位图、输入槽、次级舞台。
  final Color bgDeep;

  /// 贴边栏（标题栏 / 图标轨 / 播放底栏）：底 + 82%。
  final Color chrome;

  /// 关闭模糊时的贴边栏底（`surface @ 96%`）。
  final Color chromeOpaque;

  /// 浮块（浮动 Dock / 迷你播放器 / 浮卡）：白底 + 82%。
  final Color chromeRaised;

  /// 关闭模糊时的浮块底（`surfaceRaised @ 96%`）。
  final Color chromeRaisedOpaque;

  /// 浮层（菜单 / 对话框 / Sheet / Tooltip / Toast）。
  final Color floating;

  // ===== 文字 =====
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // ===== 主色 =====
  final Color accent;
  final Color onAccent;

  /// 选中文字 / 图标底色用的深 accent。
  final Color accentDeep;

  /// 选中底：`accent @ 11%`。
  final Color accentSoft;

  /// 强选中底：`accent @ 18%`（Dock 选中胶囊、队列当前项）。
  final Color accentSoftStrong;

  /// 选中描边 / 指示条：`accent @ 24%`。
  final Color accentBorder;

  /// 舞台高亮（金）。少量强调：徽标点、进度高亮、当前舞台标签。
  final Color highlight;

  // ===== 线与状态层 =====
  /// 0.5px 分割线。
  final Color hairline;

  /// 强分割线 / 卡片边界（`onSurface @ 14%`）。
  final Color lineStrong;

  final Color stateHover;
  final Color statePressed;
  final Color stateSelected;

  // ===== 语义 =====
  final Color danger;
  final Color onDanger;
  final Color warning;
  final Color success;

  // ===== Stage（详情页）=====
  final Color stageText;
  final Color stageTextSecondary;
  final Color stageControlFill;
  final Color stageBorder;

  // ===== 阴影 / 遮罩 =====
  final Color shadow;
  final Color shadowStrong;
  final Color scrim;

  /// 页面切换时压暗被覆盖页。
  final Color dim;

  const BmColors({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.bgDeep,
    required this.chrome,
    required this.chromeOpaque,
    required this.chromeRaised,
    required this.chromeRaisedOpaque,
    required this.floating,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentDeep,
    required this.accentSoft,
    required this.accentSoftStrong,
    required this.accentBorder,
    required this.highlight,
    required this.hairline,
    required this.lineStrong,
    required this.stateHover,
    required this.statePressed,
    required this.stateSelected,
    required this.danger,
    required this.onDanger,
    required this.warning,
    required this.success,
    required this.stageText,
    required this.stageTextSecondary,
    required this.stageControlFill,
    required this.stageBorder,
    required this.shadow,
    required this.shadowStrong,
    required this.scrim,
    required this.dim,
  });

  /// 从当前主题派生全部角色。
  ///
  /// 这是「角色 → 色值」的唯一出口：新增主题只需给 [ColorScheme] 与
  /// [AppPalette]，不需要再动组件。
  factory BmColors.resolve(ColorScheme scheme, AppPalette palette) {
    final onSurface = scheme.onSurface;
    final white = Colors.white;
    final black = Colors.black;
    return BmColors(
      bg: scheme.surface,
      surface: scheme.surface,
      surfaceRaised: palette.panelSurface,
      surfaceSunken: palette.searchField,
      bgDeep: scheme.surfaceContainer,
      chrome: scheme.surface.withValues(alpha: BmAlpha.chrome),
      chromeOpaque: scheme.surface.withValues(alpha: BmAlpha.chromeOpaque),
      chromeRaised: palette.panelSurface.withValues(alpha: BmAlpha.chrome),
      chromeRaisedOpaque: palette.panelSurface.withValues(
        alpha: BmAlpha.chromeOpaque,
      ),
      floating: scheme.surfaceContainerHigh.withValues(alpha: BmAlpha.floating),
      textPrimary: onSurface,
      textSecondary: scheme.onSurfaceVariant,
      textTertiary: scheme.onSurfaceVariant.withValues(
        alpha: BmAlpha.textTertiary,
      ),
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      accentDeep: scheme.secondary,
      accentSoft: scheme.primary.withValues(alpha: BmAlpha.selected),
      accentSoftStrong: scheme.primary.withValues(
        alpha: BmAlpha.selectedStrong,
      ),
      accentBorder: scheme.primary.withValues(alpha: BmAlpha.border),
      highlight: scheme.tertiary,
      hairline: scheme.outlineVariant,
      lineStrong: scheme.outline,
      stateHover: onSurface.withValues(alpha: BmAlpha.hover),
      statePressed: onSurface.withValues(alpha: BmAlpha.pressed),
      stateSelected: scheme.primary.withValues(alpha: BmAlpha.selected),
      danger: scheme.error,
      onDanger: scheme.onError,
      warning: palette.warning,
      success: palette.success,
      stageText: white,
      stageTextSecondary: white.withValues(alpha: BmAlpha.stageTextSecondary),
      stageControlFill: white.withValues(alpha: BmAlpha.stageFill),
      stageBorder: white.withValues(alpha: BmAlpha.stageBorder),
      shadow: black.withValues(alpha: BmAlpha.shadow),
      shadowStrong: black.withValues(alpha: BmAlpha.shadowStrong),
      scrim: black.withValues(alpha: BmAlpha.scrim),
      dim: black.withValues(alpha: BmAlpha.dim),
    );
  }

  /// 取当前主题注入的颜色角色；未注入时按当前 Theme 现算，
  /// 保证预览页 / 测试不依赖主题工厂也读得到完整角色。
  static BmColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<BmColors>() ??
        BmColors.resolve(theme.colorScheme, context.appPalette);
  }

  @override
  BmColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? bgDeep,
    Color? chrome,
    Color? chromeOpaque,
    Color? chromeRaised,
    Color? chromeRaisedOpaque,
    Color? floating,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentDeep,
    Color? accentSoft,
    Color? accentSoftStrong,
    Color? accentBorder,
    Color? highlight,
    Color? hairline,
    Color? lineStrong,
    Color? stateHover,
    Color? statePressed,
    Color? stateSelected,
    Color? danger,
    Color? onDanger,
    Color? warning,
    Color? success,
    Color? stageText,
    Color? stageTextSecondary,
    Color? stageControlFill,
    Color? stageBorder,
    Color? shadow,
    Color? shadowStrong,
    Color? scrim,
    Color? dim,
  }) {
    return BmColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      bgDeep: bgDeep ?? this.bgDeep,
      chrome: chrome ?? this.chrome,
      chromeOpaque: chromeOpaque ?? this.chromeOpaque,
      chromeRaised: chromeRaised ?? this.chromeRaised,
      chromeRaisedOpaque: chromeRaisedOpaque ?? this.chromeRaisedOpaque,
      floating: floating ?? this.floating,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentSoft: accentSoft ?? this.accentSoft,
      accentSoftStrong: accentSoftStrong ?? this.accentSoftStrong,
      accentBorder: accentBorder ?? this.accentBorder,
      highlight: highlight ?? this.highlight,
      hairline: hairline ?? this.hairline,
      lineStrong: lineStrong ?? this.lineStrong,
      stateHover: stateHover ?? this.stateHover,
      statePressed: statePressed ?? this.statePressed,
      stateSelected: stateSelected ?? this.stateSelected,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      stageText: stageText ?? this.stageText,
      stageTextSecondary: stageTextSecondary ?? this.stageTextSecondary,
      stageControlFill: stageControlFill ?? this.stageControlFill,
      stageBorder: stageBorder ?? this.stageBorder,
      shadow: shadow ?? this.shadow,
      shadowStrong: shadowStrong ?? this.shadowStrong,
      scrim: scrim ?? this.scrim,
      dim: dim ?? this.dim,
    );
  }

  @override
  BmColors lerp(ThemeExtension<BmColors>? other, double t) {
    if (other is! BmColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return BmColors(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      bgDeep: mix(bgDeep, other.bgDeep),
      chrome: mix(chrome, other.chrome),
      chromeOpaque: mix(chromeOpaque, other.chromeOpaque),
      chromeRaised: mix(chromeRaised, other.chromeRaised),
      chromeRaisedOpaque: mix(chromeRaisedOpaque, other.chromeRaisedOpaque),
      floating: mix(floating, other.floating),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentDeep: mix(accentDeep, other.accentDeep),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentSoftStrong: mix(accentSoftStrong, other.accentSoftStrong),
      accentBorder: mix(accentBorder, other.accentBorder),
      highlight: mix(highlight, other.highlight),
      hairline: mix(hairline, other.hairline),
      lineStrong: mix(lineStrong, other.lineStrong),
      stateHover: mix(stateHover, other.stateHover),
      statePressed: mix(statePressed, other.statePressed),
      stateSelected: mix(stateSelected, other.stateSelected),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      stageText: mix(stageText, other.stageText),
      stageTextSecondary: mix(stageTextSecondary, other.stageTextSecondary),
      stageControlFill: mix(stageControlFill, other.stageControlFill),
      stageBorder: mix(stageBorder, other.stageBorder),
      shadow: mix(shadow, other.shadow),
      shadowStrong: mix(shadowStrong, other.shadowStrong),
      scrim: mix(scrim, other.scrim),
      dim: mix(dim, other.dim),
    );
  }
}

extension BmColorsContext on BuildContext {
  BmColors get bmColors => BmColors.of(this);
}

/// Theater 允许的固定透明度（不再逐处 `withValues(alpha: 随机值)`）。
abstract class BmAlpha {
  /// hover 状态层。
  static const double hover = 0.06;

  /// pressed 状态层。
  static const double pressed = 0.10;

  /// selected 状态层 / accent 选中底（设计稿 `--accent-soft`）。
  static const double selected = 0.11;

  /// 强选中底（设计稿 `--accent-soft-2`）。
  static const double selectedStrong = 0.18;

  /// accent 描边 / 指示条。
  static const double border = 0.24;

  /// 贴边栏 / 浮块底色（设计稿 topbar 82%、Dock 80%）。
  static const double chrome = 0.82;

  /// 关闭模糊时的贴边栏底色。
  static const double chromeOpaque = 0.96;

  /// 浮层底色。
  static const double floating = 0.96;

  /// 迷你播放器的整条进度填充（设计稿 `rgba(31,138,148,.16)`）。
  static const double miniFill = 0.16;

  /// 次要文字（`onSurfaceVariant @ 60%`）。
  static const double textTertiary = 0.60;

  /// 禁用态。
  static const double disabled = 0.38;

  /// Stage 次要文字。
  static const double stageTextSecondary = 0.72;

  /// Stage 控件填充。
  static const double stageFill = 0.12;

  /// Stage 控件描边。
  static const double stageBorder = 0.20;

  /// Stage 封面虚化纹理的透明度（AM 式背景的主层）。
  static const double stageCover = 0.70;

  /// 浮层阴影。
  static const double shadow = 0.12;

  /// 强阴影（封面 / 大浮块）。
  static const double shadowStrong = 0.20;

  /// 遮罩。
  static const double scrim = 0.32;

  /// 页面切换时压暗被覆盖页。
  static const double dim = 0.15;
}
