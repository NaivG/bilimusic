import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 首页时段问候：早上好 / 上午好 / 中午好 / 下午好 / 晚上好 / 夜深了。
///
/// [userName] 非空时拼成「晚上好，Akarin」。
String greetingText(int hour, [String? userName]) {
  final greeting = switch (hour) {
    < 5 => '夜深了',
    < 9 => '早上好',
    < 12 => '上午好',
    < 14 => '中午好',
    < 18 => '下午好',
    < 23 => '晚上好',
    _ => '夜深了',
  };
  final name = userName?.trim();
  return name == null || name.isEmpty ? greeting : '$greeting，$name';
}

/// 首页页头 eyebrow：`11月9日 · 星期日`。
String greetingDateLabel(DateTime now) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}';
}

/// 首页问候带：暖纸底 + 湖水青光晕 + 金色舞台灯，圆角 18。
///
/// 高度随内容、宽度随父级；承载「随便听听 / 漫游一下」两个入口，
/// 回调为空时对应入口不显示。
class GreetingCard extends StatelessWidget {
  const GreetingCard({super.key, this.onShuffle, this.onStartRoam});

  /// 随机播放一首推荐曲目。
  final VoidCallback? onShuffle;

  /// 进入漫游模式。
  final VoidCallback? onStartRoam;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final radius = BmTokens.r18All;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: radius,
        border: Border.all(
          color: colors.hairline,
          width: BmTokens.hairlineWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: BmTokens.s5,
            offset: const Offset(0, BmTokens.s1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // 暖纸 → 纸深的底色渐变
            const Positioned.fill(child: _PaperWash()),
            // 湖水青
            Positioned(
              left: -BmTokens.s8,
              top: -BmTokens.s8,
              child: _StageGlow(
                size: BmTokens.s8 * 4,
                color: colors.accent,
                core: BmAlpha.selectedStrong,
              ),
            ),
            // 金色舞台灯
            Positioned(
              right: -BmTokens.s6,
              top: -BmTokens.s6,
              child: _StageGlow(
                size: BmTokens.s8 * 3,
                color: colors.highlight,
                core: BmAlpha.selectedStrong + BmAlpha.hover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BmTokens.s5,
                BmTokens.s4,
                BmTokens.s5,
                BmTokens.s4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _StageLightLabel(),
                  const SizedBox(height: BmTokens.s2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onShuffle != null)
                        _StagePill(
                          icon: Icons.shuffle_rounded,
                          label: '随便听听',
                          primary: true,
                          onTap: onShuffle!,
                        ),
                      if (onShuffle != null && onStartRoam != null)
                        const SizedBox(width: BmTokens.s2),
                      if (onStartRoam != null)
                        _StagePill(
                          icon: Icons.explore_outlined,
                          label: '漫游一下',
                          onTap: onStartRoam!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 暖纸底色：白卡到纸深。
class _PaperWash extends StatelessWidget {
  const _PaperWash();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceRaised, colors.bgDeep],
        ),
      ),
    );
  }
}

/// 舞台灯光晕：中心实、边缘散开的圆形径向渐变。
class _StageGlow extends StatelessWidget {
  const _StageGlow({
    required this.size,
    required this.color,
    required this.core,
  });

  final double size;
  final Color color;

  /// 中心不透明度。
  final double core;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: core),
              color.withValues(alpha: core / 2),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 「今天想从哪里开始？」+ 金色灯珠。
class _StageLightLabel extends StatelessWidget {
  const _StageLightLabel();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: BmTokens.s3 / 2,
          height: BmTokens.s3 / 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.highlight,
            boxShadow: [
              BoxShadow(
                color: colors.highlight.withValues(alpha: BmAlpha.border),
                blurRadius: BmTokens.s2,
                spreadRadius: BmTokens.s1 / 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: BmTokens.s2),
        Flexible(
          child: Text(
            '今天想从哪里开始？',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.bodyStrong.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// 问候带上的胶囊入口：实心（湖水青）与描边两档。
class _StagePill extends StatelessWidget {
  const _StagePill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final foreground = primary ? colors.onAccent : colors.textSecondary;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.rPillAll,
      pressScale: BmMotion.pressScale,
      semanticLabel: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary ? colors.accent : null,
          borderRadius: BmTokens.rPillAll,
          border: primary
              ? null
              : Border.all(
                  color: colors.lineStrong,
                  width: BmTokens.hairlineWidth,
                ),
        ),
        child: SizedBox(
          height: BmTokens.controlLg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: BmTokens.iconMenu,
                  color: primary ? foreground : colors.accentDeep,
                ),
                const SizedBox(width: BmTokens.s1),
                Text(
                  label,
                  style: type.label.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
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
