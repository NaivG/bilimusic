import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/motion.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome_surface.dart';
import 'package:bilimusic/shared/ui/stage/bm_stage_backdrop.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 引导页各分页的微缩界面插画。
///
/// 全部由设计 token 与共享表面组件（[BmChromeSurface] / [BmStageBackdrop]）
/// 构建，颜色统一读取 [BmColors]，切换主题时整组插画实时联动。
const double _glowAlpha = 0.18;
const double _ringAlpha = 0.14;
const double _shadowBlur = 28;
const double _iconRadiusFactor = 0.24;

/// 插画封面用的同色系微调，避免多张卡片并排时撞成同一块纯色。
Color _artTone(
  Color base, {
  double hueShift = 0,
  double lightnessShift = 0,
  double saturationShift = 0,
}) {
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withHue((hsl.hue + hueShift) % 360)
      .withLightness(
        (hsl.lightness + lightnessShift).clamp(0.0, 1.0).toDouble(),
      )
      .withSaturation(
        (hsl.saturation + saturationShift).clamp(0.0, 1.0).toDouble(),
      )
      .toColor();
}

/// 1. 首屏：黑胶声场光环 + 中心应用图标 + 三枚环绕特性徽章。
class OnboardingHeroVisual extends StatelessWidget {
  const OnboardingHeroVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final iconSide = (side * 0.28).clamp(72.0, 118.0).toDouble();
        final discSide = side * 0.62;
        return Center(
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // 主色与舞台金双层柔光
                Container(
                  width: side * 0.94,
                  height: side * 0.94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        colors.accent.withValues(alpha: _glowAlpha),
                        colors.highlight.withValues(alpha: 0.08),
                        colors.accent.withValues(alpha: 0),
                      ],
                      stops: const <double>[0.0, 0.52, 1.0],
                    ),
                  ),
                ),
                // 外围声波细环
                for (final factor in const <double>[0.76, 0.90])
                  Container(
                    width: side * factor,
                    height: side * factor,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.accent.withValues(alpha: _ringAlpha),
                        width: BmTokens.hairlineWidth,
                      ),
                    ),
                  ),
                // 黑胶唱片底座与纹理环
                Container(
                  width: discSide,
                  height: discSide,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceRaised,
                    border: Border.all(
                      color: colors.lineStrong,
                      width: BmTokens.hairlineWidth,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: _shadowBlur,
                        offset: const Offset(0, BmTokens.s2),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Container(
                        width: discSide * 0.88,
                        height: discSide * 0.88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: <Color>[
                              colors.accentSoft,
                              colors.fillMuted,
                              colors.accentSoftStrong,
                              colors.fillMuted,
                              colors.accentSoft,
                            ],
                          ),
                        ),
                      ),
                      for (final groove in const <double>[0.72, 0.58])
                        Container(
                          width: discSide * groove,
                          height: discSide * groove,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.hairline,
                              width: BmTokens.hairlineWidth,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 中心应用图标
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      iconSide * _iconRadiusFactor,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colors.shadowStrong,
                        blurRadius: _shadowBlur,
                        offset: const Offset(0, BmTokens.s3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      iconSide * _iconRadiusFactor,
                    ),
                    child: Image.asset(
                      'assets/ic_launcher.png',
                      width: iconSide,
                      height: iconSide,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                // 环绕特性胶囊
                Positioned(
                  top: side * 0.11,
                  left: side * 0.08,
                  child: const _FloatingBadge(
                    icon: Icons.high_quality_rounded,
                    label: '多档无损音质',
                  ),
                ),
                Positioned(
                  top: side * 0.14,
                  right: side * 0.06,
                  child: const _FloatingBadge(
                    icon: Icons.explore_rounded,
                    label: '智能音乐漫游',
                  ),
                ),
                Positioned(
                  bottom: side * 0.10,
                  child: const _FloatingBadge(
                    icon: Icons.lyrics_outlined,
                    label: '逐字动态歌词',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 首屏环绕的毛玻璃特性徽章。
class _FloatingBadge extends StatelessWidget {
  const _FloatingBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return BmChromeSurface(
      floating: true,
      blur: false,
      tone: BmChromeTone.raised,
      radius: BmTokens.rPillAll,
      padding: const EdgeInsets.symmetric(
        horizontal: BmTokens.s3,
        vertical: BmTokens.s1 + 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: BmTokens.iconInline, color: colors.accent),
          const SizedBox(width: BmTokens.s1),
          Text(
            label,
            style: type.caption.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. 账号与收藏页：B 站收藏夹与关注 UP 主同步卡片。
class OnboardingLoginVisual extends StatelessWidget {
  const OnboardingLoginVisual({super.key});

  static const List<(IconData, String, String, String, double)> _items =
      <(IconData, String, String, String, double)>[
        (Icons.favorite_rounded, '默认收藏夹', '128 首曲目 · 自动跟踪更新', '已同步', 0),
        (Icons.album_rounded, '深夜翻唱与纯音乐', '64 首曲目 · 导入本地歌单', '已同步', 22),
        (Icons.person_pin_rounded, '关注的音乐 UP 主', '16 位创作者 · 投稿主页直达', '常驻', -18),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 318,
          child: BmChromeSurface(
            floating: true,
            tone: BmChromeTone.raised,
            radius: BorderRadius.circular(BmTokens.r26),
            padding: const EdgeInsets.all(BmTokens.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(BmTokens.r10),
                      child: Image.asset(
                        'assets/ic_launcher.png',
                        width: 36,
                        height: 36,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(width: BmTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'B 站账号同步',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.bodyStrong.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            '支持客户端扫码与账号登录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.micro.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _MiniPill(
                      label: '已连接',
                      background: colors.accentSoft,
                      foreground: colors.accentDeep,
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s3),
                for (final (icon, title, subtitle, tag, shift) in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BmTokens.s2),
                    child: Container(
                      padding: const EdgeInsets.all(BmTokens.s2 + 2),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(BmTokens.r14),
                        border: Border.all(
                          color: colors.hairline,
                          width: BmTokens.hairlineWidth,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          _VinylArtwork(
                            size: 38,
                            icon: icon,
                            hueShift: shift,
                            radius: BmTokens.r10,
                          ),
                          const SizedBox(width: BmTokens.s2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.label.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.micro.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: BmTokens.s2),
                          _MiniPill(
                            label: tag,
                            background: colors.fillMuted,
                            foreground: colors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: BmTokens.s1),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.s3,
                    vertical: BmTokens.s2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.fillMuted,
                    borderRadius: BorderRadius.circular(BmTokens.r12),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.headphones_rounded,
                        size: BmTokens.iconInline,
                        color: colors.accent,
                      ),
                      const SizedBox(width: BmTokens.s2),
                      Expanded(
                        child: Text(
                          '免登录亦可直接搜索、播放与管理本地歌单',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.micro.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 3. 发现与漫游页：关键词/BV 搜索 + 三档漫游电台。
class OnboardingFindVisual extends StatelessWidget {
  const OnboardingFindVisual({super.key});

  static const List<(String, String, String)> _roamQueue =
      <(String, String, String)>[
        ('01', '夏日回声', '潮汐电台 · 94% 契合'),
        ('02', '霓虹与海', '白昼梦游 · 同风格推荐'),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 318,
          child: BmChromeSurface(
            floating: true,
            tone: BmChromeTone.raised,
            radius: BorderRadius.circular(BmTokens.r26),
            padding: const EdgeInsets.all(BmTokens.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 搜索框
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BmTokens.rPillAll,
                    border: Border.all(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search_rounded,
                        size: BmTokens.iconMenu,
                        color: colors.accent,
                      ),
                      const SizedBox(width: BmTokens.s2),
                      Expanded(
                        child: Text(
                          '夜航  或  BV1xx411c7mD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      _MiniPill(
                        label: 'BV / 关键词',
                        background: colors.accentSoft,
                        foreground: colors.accentDeep,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BmTokens.s2),
                // 搜索直达结果卡片
                Container(
                  padding: const EdgeInsets.all(BmTokens.s2 + 2),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(BmTokens.r14),
                    border: Border.all(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const _VinylArtwork(
                        size: 40,
                        icon: Icons.music_note_rounded,
                        radius: BmTokens.r10,
                      ),
                      const SizedBox(width: BmTokens.s2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '夜航',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.label.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'UP · 星海录音室 · 03:58',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.micro.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.play_circle_fill_rounded,
                        size: 26,
                        color: colors.accent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BmTokens.s3),
                // 漫游模式面板
                Container(
                  padding: const EdgeInsets.all(BmTokens.s3),
                  decoration: BoxDecoration(
                    color: colors.fillMuted,
                    borderRadius: BorderRadius.circular(BmTokens.r16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.explore_rounded,
                            size: BmTokens.iconMenu,
                            color: colors.accent,
                          ),
                          const SizedBox(width: BmTokens.s1),
                          Expanded(
                            child: Text(
                              '漫游模式',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.label.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const _RoamStylePills(),
                        ],
                      ),
                      const SizedBox(height: BmTokens.s1),
                      Text(
                        '以当前曲目为种子，队列见底时自动续上新歌',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.micro.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(height: BmTokens.s2),
                      for (final (indexLabel, title, meta) in _roamQueue)
                        Padding(
                          padding: const EdgeInsets.only(top: BmTokens.s1),
                          child: Row(
                            children: <Widget>[
                              Text(
                                indexLabel,
                                style: BmTypography.numeric(
                                  type.micro.copyWith(
                                    color: colors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: BmTokens.s2),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.caption.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.micro.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: BmTokens.s2),
                // 发现页入口标签
                Wrap(
                  spacing: BmTokens.s1,
                  runSpacing: BmTokens.s1,
                  children: <Widget>[
                    _MiniPill(
                      label: '热歌榜',
                      background: colors.accentSoft,
                      foreground: colors.accentDeep,
                    ),
                    _MiniPill(
                      label: '音乐排行榜',
                      background: colors.fillMuted,
                      foreground: colors.textSecondary,
                    ),
                    _MiniPill(
                      label: '每日推荐',
                      background: colors.fillMuted,
                      foreground: colors.textSecondary,
                    ),
                    _MiniPill(
                      label: '音乐画像',
                      background: colors.fillMuted,
                      foreground: colors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 漫游风格三档分段胶囊（相似 / 平衡 / 探索）。
class _RoamStylePills extends StatelessWidget {
  const _RoamStylePills();

  static const List<(String, bool)> _styles = <(String, bool)>[
    ('相似', false),
    ('平衡', true),
    ('探索', false),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BmTokens.rPillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (label, active) in _styles)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: BmTokens.s2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: active ? colors.accent : Colors.transparent,
                borderRadius: BmTokens.rPillAll,
              ),
              child: Text(
                label,
                style: type.micro.copyWith(
                  color: active ? colors.onAccent : colors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 4. 播放与音效页：标题自动净化 + 正在播放控制 + 8 段均衡器。
class OnboardingPlayVisual extends StatelessWidget {
  const OnboardingPlayVisual({super.key});

  static const List<double> _eqBands = <double>[
    0.48,
    0.72,
    0.64,
    0.52,
    0.58,
    0.76,
    0.84,
    0.62,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 318,
          child: BmChromeSurface(
            floating: true,
            tone: BmChromeTone.raised,
            radius: BorderRadius.circular(BmTokens.r26),
            padding: const EdgeInsets.all(BmTokens.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 标题自动净化前后对比
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.s3,
                    vertical: BmTokens.s2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.fillMuted,
                    borderRadius: BorderRadius.circular(BmTokens.r12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.auto_fix_high_rounded,
                            size: 13,
                            color: colors.accent,
                          ),
                          const SizedBox(width: BmTokens.s1),
                          Text(
                            '标题杂质自动剥离',
                            style: type.micro.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              'YOASOBI たぶん(Tabun) Official Music Video',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.caption.copyWith(
                                color: colors.textTertiary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: BmTokens.s2,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: colors.accent,
                            ),
                          ),
                          // 干净歌名是本行的结果，优先完整显示；
                          // 但对超宽字体给一个上限，避免把整行撑破。
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              'YOASOBI たぶん(Tabun)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.label.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BmTokens.s3),
                // 封面 + 曲目信息 + 音质徽标
                Row(
                  children: <Widget>[
                    const _VinylArtwork(
                      size: 56,
                      icon: Icons.album_rounded,
                      radius: BmTokens.r14,
                    ),
                    const SizedBox(width: BmTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'YOASOBI たぶん(Tabun)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.section.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Ayase-YOASOBI',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: BmTokens.s1),
                          Wrap(
                            spacing: BmTokens.s1,
                            children: <Widget>[
                              _MiniPill(
                                label: 'Hi-Res 音质',
                                background: colors.accentSoft,
                                foreground: colors.accentDeep,
                              ),
                              _MiniPill(
                                label: '平滑切歌',
                                background: colors.fillMuted,
                                foreground: colors.textSecondary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.favorite_rounded,
                      size: BmTokens.icon,
                      color: colors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s3),
                // 进度条
                ClipRRect(
                  borderRadius: BmTokens.rPillAll,
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      children: <Widget>[
                        ColoredBox(
                          color: colors.fillMuted,
                          child: const SizedBox.expand(),
                        ),
                        FractionallySizedBox(
                          widthFactor: 0.38,
                          child: ColoredBox(
                            color: colors.accent,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: BmTokens.s1),
                Row(
                  children: <Widget>[
                    Text(
                      '01:24',
                      style: BmTypography.numeric(
                        type.micro.copyWith(color: colors.textTertiary),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '192K / DASH',
                      style: type.micro.copyWith(
                        color: colors.accentDeep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '04:24',
                      style: BmTypography.numeric(
                        type.micro.copyWith(color: colors.textTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s2),
                // 播放控制行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    Icon(
                      Icons.shuffle_rounded,
                      size: BmTokens.iconMenu,
                      color: colors.textTertiary,
                    ),
                    Icon(
                      Icons.skip_previous_rounded,
                      size: BmTokens.iconLarge,
                      color: colors.textPrimary,
                    ),
                    _MiniCircle(
                      icon: Icons.pause_rounded,
                      color: colors.accent,
                      iconColor: colors.onAccent,
                      diameter: 40,
                    ),
                    Icon(
                      Icons.skip_next_rounded,
                      size: BmTokens.iconLarge,
                      color: colors.textPrimary,
                    ),
                    Icon(
                      Icons.repeat_rounded,
                      size: BmTokens.iconMenu,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s3),
                // 底部 8 段均衡器与耳机预设条
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.s3,
                    vertical: BmTokens.s2 + 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(BmTokens.r12),
                    border: Border.all(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.equalizer_rounded,
                        size: BmTokens.iconMenu,
                        color: colors.accent,
                      ),
                      const SizedBox(width: BmTokens.s2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '8 段均衡器与音效',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.caption.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Harman 曲线校准 · 独占输出',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.micro.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          for (final level in _eqBands)
                            Padding(
                              padding: const EdgeInsets.only(left: 3),
                              child: Container(
                                width: 4,
                                height: 22 * level,
                                decoration: BoxDecoration(
                                  color: colors.accent,
                                  borderRadius: BmTokens.rPillAll,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 5. 离线缓存页：本地歌单编排与整单离线下载。
class OnboardingOfflineVisual extends StatelessWidget {
  const OnboardingOfflineVisual({super.key});

  static const List<(String, String, bool, double)> _tracks =
      <(String, String, bool, double)>[
        ('夜航', 'Hi-Res · 24.6 MB · 已缓存', true, 0),
        ('夏日回声', '192K HQ · 8.4 MB · 已缓存', true, 18),
        ('霓虹与海', '192K HQ · 9.1 MB · 已缓存', true, -18),
        ('慢半拍', '正在写入本地 · 82%', false, 32),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final duration = motionDuration(context, BmMotion.large);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 320,
          child: BmChromeSurface(
            floating: true,
            tone: BmChromeTone.raised,
            radius: BorderRadius.circular(BmTokens.r26),
            padding: const EdgeInsets.all(BmTokens.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const _VinylArtwork(
                      size: 42,
                      icon: Icons.download_done_rounded,
                      radius: BmTokens.r10,
                    ),
                    const SizedBox(width: BmTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '通勤与旅途歌单',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.bodyStrong.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            '共 24 首 · 本地离线曲库',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.micro.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: BmTokens.s2),
                    _MiniPill(
                      label: '断网可播',
                      background: colors.accentSoft,
                      foreground: colors.accentDeep,
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s3),
                Row(
                  children: <Widget>[
                    Text(
                      '已缓存 23 / 24 首',
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      '96%',
                      style: BmTypography.numeric(
                        type.caption.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s1),
                ClipRRect(
                  borderRadius: BmTokens.rPillAll,
                  child: SizedBox(
                    height: 5,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 0.96),
                      duration: duration,
                      curve: BmMotion.standard,
                      builder: (context, value, _) {
                        return Stack(
                          children: <Widget>[
                            ColoredBox(
                              color: colors.fillMuted,
                              child: const SizedBox.expand(),
                            ),
                            FractionallySizedBox(
                              widthFactor: value,
                              child: ColoredBox(
                                color: colors.accent,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: BmTokens.s3),
                for (final (title, subtitle, done, shift) in _tracks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: BmTokens.s1),
                    child: Row(
                      children: <Widget>[
                        _VinylArtwork(
                          size: 28,
                          icon: Icons.music_note_rounded,
                          hueShift: shift,
                          radius: BmTokens.r9,
                        ),
                        const SizedBox(width: BmTokens.s2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.label.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.micro.copyWith(
                                  color: done
                                      ? colors.textTertiary
                                      : colors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          done
                              ? Icons.check_circle_rounded
                              : Icons.downloading_rounded,
                          size: BmTokens.iconMenu,
                          color: done ? colors.success : colors.accent,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: BmTokens.s2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.s3,
                    vertical: BmTokens.s2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.fillMuted,
                    borderRadius: BorderRadius.circular(BmTokens.r10),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.playlist_add_check_circle_outlined,
                        size: BmTokens.iconInline,
                        color: colors.accent,
                      ),
                      const SizedBox(width: BmTokens.s2),
                      Expanded(
                        child: Text(
                          '支持自由拖拽排序、批量管理与一键缓存整单',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.micro.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 6. 主题外观页：真实竖屏首页缩略图（问候卡 + 推荐货架 + 迷你播放器 + 浮动 Dock）。
class OnboardingTheaterVisual extends StatelessWidget {
  const OnboardingTheaterVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final duration = motionDuration(context, BmMotion.medium);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedContainer(
          duration: duration,
          curve: BmMotion.standard,
          width: 296,
          padding: const EdgeInsets.all(BmTokens.s3),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(BmTokens.r26),
            border: Border.all(
              color: colors.lineStrong,
              width: BmTokens.hairlineWidth,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.shadow,
                blurRadius: _shadowBlur,
                offset: const Offset(0, BmTokens.s3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 顶部问候栏
              Row(
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '晚上好',
                        style: type.section.copyWith(color: colors.textPrimary),
                      ),
                      Text(
                        '今天想听点什么？',
                        style: type.micro.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _MiniCircle(
                    icon: Icons.search_rounded,
                    color: colors.surfaceRaised,
                    iconColor: colors.textSecondary,
                    diameter: 28,
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s2),
              // 舞台问候卡（对齐真实 GreetingCard 的暖纸底 + 双色光晕）
              AnimatedContainer(
                duration: duration,
                curve: BmMotion.standard,
                padding: const EdgeInsets.all(BmTokens.s3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[colors.surfaceRaised, colors.bgDeep],
                  ),
                  borderRadius: BorderRadius.circular(BmTokens.r16),
                  border: Border.all(
                    color: colors.hairline,
                    width: BmTokens.hairlineWidth,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.highlight,
                          ),
                        ),
                        const SizedBox(width: BmTokens.s1),
                        Expanded(
                          child: Text(
                            '继续上次的播放或开启漫游',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.caption.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BmTokens.s2),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BmTokens.s3,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BmTokens.rPillAll,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.shuffle_rounded,
                                size: 12,
                                color: colors.onAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '随便听听',
                                style: type.micro.copyWith(
                                  color: colors.onAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: BmTokens.s2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: BmTokens.s3,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BmTokens.rPillAll,
                            border: Border.all(
                              color: colors.lineStrong,
                              width: BmTokens.hairlineWidth,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.explore_outlined,
                                size: 12,
                                color: colors.accentDeep,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '漫游一下',
                                style: type.micro.copyWith(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BmTokens.s2),
              // 推荐双卡（带黑胶封面与标题，不再是刺眼的大纯色块）
              Row(
                children: <Widget>[
                  const Expanded(
                    child: _MiniMediaCard(
                      title: '夜航',
                      subtitle: '星海录音室',
                      icon: Icons.album_rounded,
                      hueShift: 0,
                    ),
                  ),
                  const SizedBox(width: BmTokens.s2),
                  const Expanded(
                    child: _MiniMediaCard(
                      title: '晚风集',
                      subtitle: '每日精选歌单',
                      icon: Icons.queue_music_rounded,
                      hueShift: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s2),
              // 悬浮迷你播放器（整条进度背景填充）
              ClipRRect(
                borderRadius: BmTokens.rPillAll,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.chromeRaisedOpaque,
                    border: Border.all(
                      color: colors.hairline,
                      width: BmTokens.hairlineWidth,
                    ),
                    borderRadius: BmTokens.rPillAll,
                  ),
                  child: Stack(
                    children: <Widget>[
                      FractionallySizedBox(
                        widthFactor: 0.45,
                        child: ColoredBox(
                          color: colors.accentSoft,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: BmTokens.s2,
                        ),
                        child: Row(
                          children: <Widget>[
                            const _VinylArtwork(
                              size: 24,
                              icon: Icons.music_note_rounded,
                              radius: BmTokens.r9,
                            ),
                            const SizedBox(width: BmTokens.s2),
                            Expanded(
                              child: Text(
                                '夜航 · 星海录音室',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.micro.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.pause_rounded,
                              size: BmTokens.iconMenu,
                              color: colors.accent,
                            ),
                            const SizedBox(width: BmTokens.s1),
                            Icon(
                              Icons.queue_music_rounded,
                              size: BmTokens.iconMenu,
                              color: colors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: BmTokens.s2),
              // 悬浮四项 Dock
              Container(
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BmTokens.rPillAll,
                  border: Border.all(
                    color: colors.hairline,
                    width: BmTokens.hairlineWidth,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    for (final (icon, label, active)
                        in const <(IconData, String, bool)>[
                          (Icons.home_rounded, '首页', true),
                          (Icons.explore_outlined, '发现', false),
                          (Icons.person_outline_rounded, '我的', false),
                          (Icons.settings_outlined, '设置', false),
                        ])
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: active
                                ? colors.accentSoftStrong
                                : Colors.transparent,
                            borderRadius: BmTokens.rPillAll,
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  icon,
                                  size: 13,
                                  color: active
                                      ? colors.accentDeep
                                      : colors.textSecondary,
                                ),
                                if (active) ...<Widget>[
                                  const SizedBox(width: 3),
                                  Text(
                                    label,
                                    style: type.micro.copyWith(
                                      color: colors.accentDeep,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缩略首页里的媒体白卡：上方克制的黑胶封面 + 下方真实曲目文案。
class _MiniMediaCard extends StatelessWidget {
  const _MiniMediaCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.hueShift,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final double hueShift;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.all(BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(BmTokens.r14),
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 68,
            decoration: BoxDecoration(
              color: colors.bgDeep,
              borderRadius: BorderRadius.circular(BmTokens.r10),
            ),
            child: Center(
              child: _VinylArtwork(
                size: 46,
                icon: icon,
                hueShift: hueShift,
                circular: true,
              ),
            ),
          ),
          const SizedBox(height: BmTokens.s1 + 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.caption.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.micro.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 主题选择配件：点击色板实时切换全局主题。
class OnboardingThemePicker extends ConsumerWidget {
  const OnboardingThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final selectedId = ref.watch(settingsProvider.select((s) => s.theme));
    final selected = ThemeRegistry.resolve(selectedId);
    final brightness = Theme.of(context).brightness;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: BmTokens.s1,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final descriptor in ThemeRegistry.all)
              _ThemeSwatch(
                key: ValueKey<String>('whats-new-theme-${descriptor.id}'),
                descriptor: descriptor,
                brightness: brightness,
                selected: descriptor.id == selected.id,
                onTap: () =>
                    ref.read(settingsProvider.notifier).setTheme(descriptor.id),
              ),
          ],
        ),
        const SizedBox(height: BmTokens.s2),
        Text(
          '${selected.label} · ${selected.subtitle ?? ''}',
          textAlign: TextAlign.center,
          style: type.caption.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '浅色与深色模式可在设置中随时切换',
          style: type.micro.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    super.key,
    required this.descriptor,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final AppThemeDescriptor descriptor;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final accent = descriptor.paletteAccent(brightness);
    final surface = descriptor.paletteSurface(brightness);
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.rPillAll,
      semanticLabel: '切换到 ${descriptor.label} 主题',
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: AnimatedContainer(
          duration: motionDuration(context, BmMotion.medium),
          curve: BmMotion.standard,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent,
            border: Border.all(
              color: selected ? colors.textPrimary : colors.hairline,
              width: selected ? 2 : BmTokens.hairlineWidth,
            ),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: BmTokens.s2,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surface,
                border: Border.all(
                  color: colors.hairline,
                  width: BmTokens.hairlineWidth,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 7. 宽屏与桌面布局页：左侧导航栏 + 顶栏搜索 + 内容区 + 右侧播放队列 + 底部播放栏。
class OnboardingLandscapeVisual extends StatelessWidget {
  const OnboardingLandscapeVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: 440,
        height: 286,
        child: Container(
          padding: const EdgeInsets.all(BmTokens.s2),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(BmTokens.r20),
            border: Border.all(
              color: colors.lineStrong,
              width: BmTokens.hairlineWidth,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.shadow,
                blurRadius: _shadowBlur,
                offset: const Offset(0, BmTokens.s2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _MockRail(),
              const SizedBox(width: BmTokens.s2),
              Expanded(
                child: Column(
                  children: <Widget>[
                    const _MockTopBar(),
                    const SizedBox(height: BmTokens.s1),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BmTokens.r12All,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const Expanded(flex: 6, child: _MockHomeContent()),
                            const SizedBox(width: BmTokens.s1),
                            Expanded(
                              flex: 4,
                              child: _MockQueuePanel(
                                background: colors.surfaceRaised,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: BmTokens.s1),
                    const _MockPlaybar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横屏左侧导航栏（对齐真实 LandscapeRail）。
class _MockRail extends StatelessWidget {
  const _MockRail();

  static const List<IconData> _icons = <IconData>[
    Icons.home_rounded,
    Icons.explore_outlined,
    Icons.library_music_outlined,
    Icons.history_rounded,
    Icons.download_outlined,
    Icons.favorite_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      width: 34,
      padding: const EdgeInsets.symmetric(vertical: BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r10All,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Column(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Image.asset(
              'assets/ic_launcher.png',
              width: 16,
              height: 16,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(height: BmTokens.s2),
          for (final icon in _icons)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: icon == Icons.home_rounded
                      ? colors.accentSoftStrong
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  icon,
                  size: 13,
                  color: icon == Icons.home_rounded
                      ? colors.accentDeep
                      : colors.textSecondary,
                ),
              ),
            ),
          const Spacer(),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.success,
            ),
          ),
          const SizedBox(height: 6),
          Icon(Icons.settings_outlined, size: 12, color: colors.textTertiary),
        ],
      ),
    );
  }
}

/// 横屏标题栏（对齐真实 LandscapeTitleBar：页面标题 + 搜索框 + 桌面窗口按钮）。
class _MockTopBar extends StatelessWidget {
  const _MockTopBar();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r9All,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '首页',
            style: type.micro.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: BmTokens.s2),
          Container(
            width: 136,
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BmTokens.rPillAll,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.search_rounded, size: 9, color: colors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '搜索音乐、UP 主、BV 号',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.micro.copyWith(
                      fontSize: 8.5,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Icon(Icons.remove_rounded, size: 10, color: colors.textTertiary),
          const SizedBox(width: 4),
          Icon(Icons.crop_square_rounded, size: 9, color: colors.textTertiary),
          const SizedBox(width: 4),
          Icon(Icons.close_rounded, size: 10, color: colors.textSecondary),
        ],
      ),
    );
  }
}

/// 横屏内容舞台左侧：问候横幅 + 三张唱片推荐卡。
class _MockHomeContent extends StatelessWidget {
  const _MockHomeContent();

  static const List<(String, String, double)> _cards =
      <(String, String, double)>[
        ('每日推荐', '24 首', 0),
        ('深夜电台', '漫游', 20),
        ('热歌精选', '榜单', -20),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.all(BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r10All,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 问候带
          Container(
            padding: const EdgeInsets.all(BmTokens.s2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[colors.bg, colors.bgDeep],
              ),
              borderRadius: BmTokens.r9All,
              border: Border.all(
                color: colors.hairline,
                width: BmTokens.hairlineWidth,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.highlight,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '今天想从哪里开始？',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.micro.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _MiniPill(
                  label: '漫游',
                  background: colors.accent,
                  foreground: colors.onAccent,
                ),
              ],
            ),
          ),
          const SizedBox(height: BmTokens.s2),
          Text(
            '为你推荐',
            style: type.micro.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: BmTokens.s1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < _cards.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BmTokens.r9All,
                        border: Border.all(
                          color: colors.hairline,
                          width: BmTokens.hairlineWidth,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Center(
                              child: _VinylArtwork(
                                size: 34,
                                icon: Icons.album_rounded,
                                hueShift: _cards[i].$3,
                                circular: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _cards[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.micro.copyWith(
                              fontSize: 9.5,
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _cards[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.micro.copyWith(
                              fontSize: 8.5,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 横屏右侧播放队列抽屉：真实曲目列表。
class _MockQueuePanel extends StatelessWidget {
  const _MockQueuePanel({required this.background});

  final Color background;

  static const List<(String, String, bool)> _queue = <(String, String, bool)>[
    ('夜航', '星海录音室', true),
    ('夏日回声', '潮汐电台', false),
    ('霓虹与海', '白昼梦游', false),
    ('慢半拍', '午夜飞行', false),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.all(BmTokens.s2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BmTokens.r10All,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '播放队列',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.micro.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '12 首',
                style: type.micro.copyWith(
                  fontSize: 9,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (title, artist, active) in _queue)
            Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: active ? colors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    active
                        ? Icons.graphic_eq_rounded
                        : Icons.music_note_rounded,
                    size: 11,
                    color: active ? colors.accent : colors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$title · $artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.micro.copyWith(
                        fontSize: 9,
                        color: active ? colors.accentDeep : colors.textPrimary,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 横屏底栏：顶沿全宽细线进度 + 左曲目 / 中控制 / 右音量。
class _MockPlaybar extends StatelessWidget {
  const _MockPlaybar();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r9All,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BmTokens.rPillAll,
            child: SizedBox(
              height: 2,
              child: Stack(
                children: <Widget>[
                  ColoredBox(
                    color: colors.fillMuted,
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: 0.42,
                    child: ColoredBox(
                      color: colors.accent,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                const _VinylArtwork(
                  size: 18,
                  icon: Icons.music_note_rounded,
                  radius: BmTokens.r4,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '夜航 · 星海录音室',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.micro.copyWith(
                      fontSize: 9.5,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.skip_previous_rounded,
                  size: 13,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 17,
                  color: colors.accent,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.skip_next_rounded,
                  size: 13,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: BmTokens.s2),
                Icon(Icons.favorite_rounded, size: 11, color: colors.danger),
                const SizedBox(width: 6),
                Icon(
                  Icons.volume_up_rounded,
                  size: 11,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  child: ClipRRect(
                    borderRadius: BmTokens.rPillAll,
                    child: SizedBox(
                      height: 2,
                      child: Stack(
                        children: <Widget>[
                          ColoredBox(
                            color: colors.fillMuted,
                            child: const SizedBox.expand(),
                          ),
                          FractionallySizedBox(
                            widthFactor: 0.65,
                            child: ColoredBox(
                              color: colors.textSecondary,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 8. 动态歌词页：详情页流体舞台背景 + 逐字点亮歌词 + 双语与声源标识。
class OnboardingLyricVisual extends StatelessWidget {
  const OnboardingLyricVisual({super.key});

  static const List<String> _lines = <String>[
    '穿过傍晚最后一道云层',
    '海面升起零星的灯火',
    '晚风吹过甲板，万籁俱寂',
    '只剩星群在远方闪烁',
  ];

  static const int _currentLine = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final duration = motionDuration(context, BmMotion.hero);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth,
          math.min(336.0, constraints.maxHeight * 0.85),
        );
        final height = width / 0.85;
        return Center(
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BmTokens.r26),
              border: Border.all(
                color: colors.lineStrong,
                width: BmTokens.hairlineWidth,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.shadowStrong,
                  blurRadius: _shadowBlur,
                  offset: const Offset(0, BmTokens.s3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BmTokens.r26),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  BmStageBackdrop(
                    dominantColor: colors.accent,
                    fallbackColor: colors.accent,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(BmTokens.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const _VinylArtwork(
                              size: 36,
                              icon: Icons.album_rounded,
                              radius: BmTokens.r9,
                            ),
                            const SizedBox(width: BmTokens.s2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '夜航',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: type.label.copyWith(
                                      color: colors.stageText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '星海录音室',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: type.micro.copyWith(
                                      color: colors.stageTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: BmTokens.s2,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.stageControlFill,
                                borderRadius: BmTokens.rPillAll,
                                border: Border.all(
                                  color: colors.stageBorder,
                                  width: BmTokens.hairlineWidth,
                                ),
                              ),
                              child: Text(
                                'Hi-Res',
                                style: type.micro.copyWith(
                                  color: colors.stageText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: duration,
                          curve: BmMotion.standard,
                          builder: (context, progress, _) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                for (
                                  var index = 0;
                                  index < _lines.length;
                                  index++
                                )
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: BmTokens.s1 + 2,
                                    ),
                                    child: index == _currentLine
                                        ? _HighlightedLyricLine(
                                            text: _lines[index],
                                            progress: progress,
                                          )
                                        : Text(
                                            _lines[index],
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: type.bodyStrong.copyWith(
                                              color: colors.stageTextSecondary,
                                            ),
                                          ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const Spacer(),
                        Row(
                          children: <Widget>[
                            Text(
                              '01:24',
                              style: BmTypography.numeric(
                                type.micro.copyWith(
                                  color: colors.stageTextSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: BmTokens.s2),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BmTokens.rPillAll,
                                child: SizedBox(
                                  height: 3,
                                  child: Stack(
                                    children: <Widget>[
                                      ColoredBox(
                                        color: colors.stageControlFill,
                                        child: const SizedBox.expand(),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor: 0.38,
                                        child: ColoredBox(
                                          color: colors.stageText,
                                          child: const SizedBox.expand(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: BmTokens.s2),
                            Text(
                              '03:58',
                              style: BmTypography.numeric(
                                type.micro.copyWith(
                                  color: colors.stageTextSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: BmTokens.s2),
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.translate_rounded,
                              size: BmTokens.iconInline,
                              color: colors.stageTextSecondary,
                            ),
                            const SizedBox(width: BmTokens.s2),
                            Icon(
                              Icons.lyrics_outlined,
                              size: BmTokens.iconInline,
                              color: colors.stageText,
                            ),
                            const Spacer(),
                            Text(
                              '逐字高亮 · 多源自动匹配',
                              style: type.micro.copyWith(
                                color: colors.stageTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 当前歌词行：从左到右逐字点亮，亮字带柔和辉光。
class _HighlightedLyricLine extends StatelessWidget {
  const _HighlightedLyricLine({required this.text, required this.progress});

  final String text;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final litCount = (text.length * progress).floor();
    final baseStyle = type.section.copyWith(
      fontSize: 22,
      color: colors.stageTextSecondary,
      fontWeight: FontWeight.w800,
    );
    final litStyle = baseStyle.copyWith(
      color: colors.stageText,
      shadows: <Shadow>[
        Shadow(
          color: colors.accent.withValues(alpha: 0.55),
          blurRadius: BmTokens.s4,
        ),
      ],
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (var index = 0; index < text.length; index++)
            TextSpan(
              text: text[index],
              style: index < litCount ? litStyle : baseStyle,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 9. 局域网多设备同步页：mDNS 自动发现 + 跨设备队列同步与遥控。
class OnboardingSyncVisual extends StatelessWidget {
  const OnboardingSyncVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 320,
          child: BmChromeSurface(
            floating: true,
            tone: BmChromeTone.raised,
            radius: BorderRadius.circular(BmTokens.r26),
            padding: const EdgeInsets.all(BmTokens.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.wifi_tethering_rounded,
                      size: BmTokens.icon,
                      color: colors.accent,
                    ),
                    const SizedBox(width: BmTokens.s2),
                    Expanded(
                      child: Text(
                        '局域网设备互联',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _MiniPill(
                      label: 'mDNS 已配对',
                      background: colors.accentSoft,
                      foreground: colors.accentDeep,
                    ),
                  ],
                ),
                const SizedBox(height: BmTokens.s3),
                // 主控桌面端卡片
                _DeviceNodeCard(
                  icon: Icons.desktop_windows_rounded,
                  title: '桌面端 · 书房电脑',
                  subtitle: '正在播放《夜航》 · 01:24 / 03:58',
                  badge: '当前发声',
                  highlighted: true,
                ),
                // 同步桥接指示
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: BmTokens.s2),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: BmTokens.s3),
                      Icon(
                        Icons.sync_alt_rounded,
                        size: BmTokens.iconMenu,
                        color: colors.accent,
                      ),
                      const SizedBox(width: BmTokens.s2),
                      Expanded(
                        child: Text(
                          '播放状态、24 首队列与进度实时双向同步',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.micro.copyWith(
                            color: colors.accentDeep,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 协同移动端与穿戴端
                const _DeviceNodeCard(
                  icon: Icons.phone_android_rounded,
                  title: '移动端 · 随身手机',
                  subtitle: '已同步当前播放队列 · 可随时接力或遥控',
                  badge: '已连接',
                  highlighted: false,
                ),
                const SizedBox(height: BmTokens.s2),
                const _DeviceNodeCard(
                  icon: Icons.tablet_rounded,
                  title: '移动端 · 平板',
                  subtitle: '未连接至群组',
                  badge: '离线',
                  highlighted: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceNodeCard extends StatelessWidget {
  const _DeviceNodeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.highlighted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.all(BmTokens.s3),
      decoration: BoxDecoration(
        color: highlighted ? colors.accentSoft : colors.surface,
        borderRadius: BorderRadius.circular(BmTokens.r14),
        border: Border.all(
          color: highlighted ? colors.accentBorder : colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: highlighted ? colors.accent : colors.fillMuted,
              borderRadius: BorderRadius.circular(BmTokens.r10),
            ),
            child: Icon(
              icon,
              size: BmTokens.iconMenu,
              color: highlighted ? colors.onAccent : colors.textSecondary,
            ),
          ),
          const SizedBox(width: BmTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.label.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.micro.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: BmTokens.s2),
          _MiniPill(
            label: badge,
            background: highlighted ? colors.surface : colors.fillMuted,
            foreground: highlighted ? colors.accentDeep : colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// 10. 性能页：新旧版本的内存与页面切换帧耗时对比。
///
/// 上半是常驻内存的两条填充条，下半是切页帧耗时的成对柱状图（竖柱）：
/// 同一版本内「实心 = 平均帧、描边 = p95」，两根版本柱并排在同一把
/// 0–40 ms 的尺子上，再画一条 16.7 ms 的 60fps 预算线，一眼就能看出
/// 旧版 p95 破了预算、新版整段都在预算内。
class OnboardingPerformanceVisual extends StatelessWidget {
  const OnboardingPerformanceVisual({super.key});

  static const double _oldMb = 549;
  static const double _newMb = 310;

  /// 页面切换帧耗时：切到「首页」的 3 秒过渡窗口，Dart VM timeline 采样。
  /// 平均值 / p95 的单位是 ms；掉帧率按 16.7 ms 的 60fps 预算统计。
  static const double _oldAvgMs = 13.77;
  static const double _newAvgMs = 6.20;
  static const double _oldP95Ms = 37.9;
  static const double _newP95Ms = 8.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Center(
      child: SizedBox(
        width: 340,
        child: BmChromeSurface(
          floating: true,
          tone: BmChromeTone.raised,
          radius: BorderRadius.circular(BmTokens.r26),
          padding: const EdgeInsets.all(BmTokens.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '常驻内存',
                    style: type.section.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s3),
              _MemoryBar(
                label: '旧版',
                value: '~549 MB',
                fraction: 1,
                color: colors.lineStrong,
              ),
              const SizedBox(height: BmTokens.s2),
              _MemoryBar(
                label: '1.12',
                value: '~310 MB',
                fraction: _newMb / _oldMb,
                color: colors.accent,
              ),
              const SizedBox(height: BmTokens.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '-43%',
                    style: type.display.copyWith(
                      fontSize: 46,
                      height: 1,
                      color: colors.accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.6,
                    ),
                  ),
                  const SizedBox(width: BmTokens.s2),
                  Text(
                    '少了 239 MB',
                    style: type.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s4),
              Container(height: BmTokens.hairlineWidth, color: colors.hairline),
              const SizedBox(height: BmTokens.s4),
              Row(
                children: <Widget>[
                  Text(
                    '页面切换帧耗时（ms）',
                    style: type.label.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _MiniPill(
                    label: '首页',
                    background: colors.fillMuted,
                    foreground: colors.textSecondary,
                  ),
                  const Spacer(),
                  _ChartLegendItem(
                    label: '平均',
                    color: colors.textSecondary,
                    filled: true,
                  ),
                  const SizedBox(width: BmTokens.s2),
                  _ChartLegendItem(
                    label: 'p95',
                    color: colors.textSecondary,
                    filled: false,
                  ),
                ],
              ),
              const SizedBox(height: BmTokens.s3),
              const _PageSwitchChart(
                oldAvg: _oldAvgMs,
                newAvg: _newAvgMs,
                oldP95: _oldP95Ms,
                newP95: _newP95Ms,
              ),
              const SizedBox(height: BmTokens.s3),
              Row(
                children: <Widget>[
                  Text(
                    '掉帧率 12% → 0%',
                    style: type.caption.copyWith(
                      color: colors.accentDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: BmTokens.s2),
                  Expanded(
                    child: Text(
                      '同机同数据实测',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.micro.copyWith(color: colors.textTertiary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryBar extends StatelessWidget {
  const _MemoryBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BmTokens.rPillAll,
            child: SizedBox(
              height: 10,
              child: Stack(
                children: <Widget>[
                  ColoredBox(
                    color: colors.fillMuted,
                    child: const SizedBox.expand(),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: color,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: BmTokens.s2),
        SizedBox(
          width: 58,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.label.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 页面切换帧耗时的竖柱图。
///
/// 两版并排，每版两根柱子（实心平均 / 描边 p95），共用 0–40 ms 的尺子。
/// 顶部留出数值标签的位置，底部是版本标签；60fps 预算线横穿整张图，
/// 旧版的 p95 柱子穿过这条线、新版全部落在下方——这是这张图要讲的事。
class _PageSwitchChart extends StatelessWidget {
  const _PageSwitchChart({
    required this.oldAvg,
    required this.newAvg,
    required this.oldP95,
    required this.newP95,
  });

  final double oldAvg;
  final double newAvg;
  final double oldP95;
  final double newP95;

  static const double _height = 122;
  static const double _barArea = 72;
  static const double _baseline = 20;
  static const double _maxMs = 40;
  static const double _barWidth = 40;
  static const double _barGap = 8;
  static const double _groupGap = 40;
  static const double _groupWidth = _barWidth * 2 + _barGap;
  static const double _budgetMs = 1000 / 60;

  double _barHeight(double ms) => (_barArea * ms / _maxMs).clamp(0, _barArea);

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final oldAvgColor = colors.textSecondary.withValues(alpha: 0.5);
    final oldP95Color = colors.textSecondary;
    final newColor = colors.accent;
    final budgetY = _baseline + _barHeight(_budgetMs);

    return SizedBox(
      height: _height,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: budgetY,
            height: 1,
            child: CustomPaint(
              painter: _DashedRulePainter(
                colors.textSecondary.withValues(alpha: 0.30),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: budgetY + 2,
            child: Text(
              '60 fps',
              style: type.micro.copyWith(color: colors.textSecondary),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _baseline,
            height: BmTokens.hairlineWidth,
            child: ColoredBox(color: colors.hairline),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: _baseline,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _ChartGroup(
                  bars: <Widget>[
                    _ChartColumn(
                      value: oldAvg,
                      height: _barHeight(oldAvg),
                      color: oldAvgColor,
                      labelColor: colors.textSecondary,
                      filled: true,
                    ),
                    _ChartColumn(
                      value: oldP95,
                      height: _barHeight(oldP95),
                      color: oldP95Color,
                      labelColor: colors.textSecondary,
                      filled: false,
                    ),
                  ],
                ),
                const SizedBox(width: _groupGap),
                _ChartGroup(
                  bars: <Widget>[
                    _ChartColumn(
                      value: newAvg,
                      height: _barHeight(newAvg),
                      color: newColor,
                      labelColor: colors.textPrimary,
                      filled: true,
                    ),
                    _ChartColumn(
                      value: newP95,
                      height: _barHeight(newP95),
                      color: newColor,
                      labelColor: colors.textPrimary,
                      filled: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _ChartGroupLabel(label: '旧版', colors: colors),
                const SizedBox(width: _groupGap),
                _ChartGroupLabel(label: '1.12', colors: colors),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一组柱子：两根柱 + 柱间留白，固定组宽让上下两行的版本标签对齐。
class _ChartGroup extends StatelessWidget {
  const _ChartGroup({required this.bars});

  final List<Widget> bars;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _PageSwitchChart._groupWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          bars[0],
          const SizedBox(width: _PageSwitchChart._barGap),
          bars[1],
        ],
      ),
    );
  }
}

/// 一根柱子：数值标签贴在柱顶，实心 / 描边区分平均与 p95。
class _ChartColumn extends StatelessWidget {
  const _ChartColumn({
    required this.value,
    required this.height,
    required this.color,
    required this.labelColor,
    required this.filled,
  });

  final double value;
  final double height;
  final Color color;
  final Color labelColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final type = context.bmType;
    return SizedBox(
      width: _PageSwitchChart._barWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value.toStringAsFixed(1),
            maxLines: 1,
            style: type.micro.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: height,
            decoration: BoxDecoration(
              color: filled ? color : color.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
              border: filled ? null : Border.all(color: color, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 柱子下方的版本标签，宽度跟 [_ChartGroup] 一致，保证居中。
class _ChartGroupLabel extends StatelessWidget {
  const _ChartGroupLabel({required this.label, required this.colors});

  final String label;
  final BmColors colors;

  @override
  Widget build(BuildContext context) {
    final type = context.bmType;
    return SizedBox(
      width: _PageSwitchChart._groupWidth,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: type.caption.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// 图例：实心方块 = 平均，空心方块 = p95。
class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({
    required this.label,
    required this.color,
    required this.filled,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(2),
            border: filled ? null : Border.all(color: color, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: type.micro.copyWith(color: colors.textTertiary)),
      ],
    );
  }
}

/// 60fps 预算线：3px 实线 + 3px 空隙的虚线。
class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dash = 3.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + dash, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRulePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 11. 收尾页：黑胶播放主按钮 + 四枚核心体验胶囊。
class OnboardingStartVisual extends StatelessWidget {
  const OnboardingStartVisual({super.key});

  static const List<(IconData, String)> _features = <(IconData, String)>[
    (Icons.library_music_outlined, 'B 站曲库'),
    (Icons.explore_outlined, '智能漫游'),
    (Icons.lyrics_outlined, '逐字歌词'),
    (Icons.devices_rounded, '多端互联'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final button = (side * 0.25).clamp(64.0, 92.0).toDouble();
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: side * 0.56,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Container(
                      width: side * 0.54,
                      height: side * 0.54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: <Color>[
                            colors.accent.withValues(alpha: _glowAlpha),
                            colors.highlight.withValues(alpha: 0.08),
                            colors.accent.withValues(alpha: 0),
                          ],
                          stops: const <double>[0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                    for (final factor in const <double>[0.38, 0.48])
                      Container(
                        width: side * factor,
                        height: side * factor,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.accent.withValues(alpha: _ringAlpha),
                            width: BmTokens.hairlineWidth,
                          ),
                        ),
                      ),
                    Container(
                      width: button,
                      height: button,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: colors.accent.withValues(alpha: 0.35),
                            blurRadius: BmTokens.s5,
                            offset: const Offset(0, BmTokens.s2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: button * 0.5,
                        color: colors.onAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BmTokens.s4),
              Wrap(
                spacing: BmTokens.s2,
                runSpacing: BmTokens.s2,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final (icon, label) in _features)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BmTokens.s3,
                        vertical: BmTokens.s1 + 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius: BmTokens.rPillAll,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(icon, size: 13, color: colors.accentDeep),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: type.label.copyWith(
                              color: colors.accentDeep,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 精致的微缩黑胶/专辑封面组件：带同心纹路与温润层次，避免刺眼的大块纯色。
class _VinylArtwork extends StatelessWidget {
  const _VinylArtwork({
    required this.size,
    required this.icon,
    this.hueShift = 0,
    this.radius = BmTokens.r10,
    this.circular = false,
  });

  final double size;
  final IconData icon;
  final double hueShift;
  final double radius;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final primaryTone = _artTone(
      colors.accent,
      hueShift: hueShift,
      lightnessShift: -0.04,
      saturationShift: -0.08,
    );
    final deepTone = _artTone(
      colors.accentDeep,
      hueShift: hueShift * 0.6,
      lightnessShift: -0.08,
    );
    final borderRadius = circular ? null : BorderRadius.circular(radius);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[primaryTone, deepTone],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: size * 0.76,
            height: size * 0.76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: BmTokens.hairlineWidth,
              ),
            ),
          ),
          Icon(
            icon,
            size: (size * 0.44).clamp(10.0, 22.0).toDouble(),
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ],
      ),
    );
  }
}

/// 迷你圆形图标底座（插画专用，无交互）。
class _MiniCircle extends StatelessWidget {
  const _MiniCircle({
    required this.icon,
    required this.color,
    required this.iconColor,
    this.diameter = 26,
  });

  final IconData icon;
  final Color color;
  final Color iconColor;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: diameter * 0.56, color: iconColor),
    );
  }
}

/// 迷你状态胶囊（插画专用，无交互）。
class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s2, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BmTokens.rPillAll,
      ),
      child: Text(
        label,
        style: type.micro.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
