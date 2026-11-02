import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/auth/user_providers.dart';

/// 首页顶部的问候卡片。
class GreetingCard extends ConsumerWidget {
  const GreetingCard({super.key, this.onShuffle, this.onStartRoam});

  /// 随机播放一首推荐曲目；为空时不显示该入口。
  final VoidCallback? onShuffle;

  /// 进入漫游模式的入口；为空时不显示该入口。
  final VoidCallback? onStartRoam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final userState = ref.watch(userStateProvider);
    final userName = userState.userInfo?.userName;

    final greeting = _greetingFor(now.hour, userName);
    final dateLabel = _dateLabel(now);

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          return _buildCard(
            scheme: scheme,
            greeting: greeting,
            dateLabel: dateLabel,
            compact: compact,
          );
        },
      ),
    );
  }

  Widget _buildCard({
    required ColorScheme scheme,
    required String greeting,
    required String dateLabel,
    required bool compact,
  }) {
    final accent = scheme.primary;
    final accentAlt = scheme.secondary;
    final glow = Color.lerp(accent, Colors.white, 0.38)!;
    final base = const Color(0xFF0B0D13);
    final deep = Color.alphaBlend(accent.withValues(alpha: 0.42), base);
    final deepAlt = Color.alphaBlend(accentAlt.withValues(alpha: 0.30), base);
    final radius = BorderRadius.circular(compact ? 22 : 26);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 32,
            spreadRadius: -8,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        deep,
                        Color.alphaBlend(
                          accentAlt.withValues(alpha: 0.14),
                          base,
                        ),
                        deepAlt,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: _StaticAurora(
                  primary: accent,
                  secondary: accentAlt,
                  compact: compact,
                ),
              ),
              Positioned(
                top: compact ? -24 : -36,
                right: compact ? -52 : 36,
                child: _Vinyl(
                  size: compact ? 150 : 220,
                  accent: accent,
                  accentAlt: accentAlt,
                  opacity: compact ? 0.55 : 0.92,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 20 : 28,
                  compact ? 18 : 24,
                  compact ? 20 : 28,
                  compact ? 18 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compact ? double.infinity : 560,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _StatusDot(color: glow),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              dateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 16 : 20),
                      Text(
                        greeting,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 30 : 40,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: compact ? -0.6 : -1.0,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '今天想从哪里开始？',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: compact ? 14 : 16,
                          height: 1.4,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (onShuffle != null || onStartRoam != null) ...[
                        SizedBox(height: compact ? 16 : 22),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            if (onShuffle != null)
                              _GreetingAction(
                                icon: Icons.shuffle_rounded,
                                label: '随便听听',
                                emphasized: true,
                                onTap: onShuffle!,
                              ),
                            if (onStartRoam != null)
                              _GreetingAction(
                                icon: Icons.explore_outlined,
                                label: '漫游一下',
                                onTap: onStartRoam!,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String _greetingFor(int hour, [String? userName]) {
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
    return name == null || name.isEmpty ? greeting : '$greeting, $name';
  }

  static String _dateLabel(DateTime now) {
    return '${now.month}月${now.day}日 · 星期${_weekdays[now.weekday - 1]}';
  }
}

/// 静态的双色光晕。
class _StaticAurora extends StatelessWidget {
  const _StaticAurora({
    required this.primary,
    required this.secondary,
    required this.compact,
  });

  final Color primary;
  final Color secondary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -96,
          top: -108,
          child: _GlowOrb(
            size: compact ? 240 : 340,
            color: primary,
            alpha: 0.38,
          ),
        ),
        Positioned(
          right: -84,
          bottom: -152,
          child: _GlowOrb(
            size: compact ? 220 : 320,
            color: secondary,
            alpha: 0.30,
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
    required this.alpha,
  });

  final double size;
  final Color color;
  final double alpha;

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
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * 0.45),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 黑胶唱片。
class _Vinyl extends StatelessWidget {
  const _Vinyl({
    required this.size,
    required this.accent,
    required this.accentAlt,
    required this.opacity,
  });

  final double size;
  final Color accent;
  final Color accentAlt;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF101318),
                    Color(0xFF252A33),
                    Color(0xFF0C0F14),
                    Color(0xFF252A33),
                    Color(0xFF101318),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
            ),
            for (final factor in const [0.88, 0.76, 0.64, 0.52])
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(size * (1 - factor) / 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.04),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, accentAlt],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
            Container(
              width: size * 0.045,
              height: size * 0.045,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0B0D13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期前的状态小点。
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.38),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// 卡片上的玻璃质感快捷入口。
class _GreetingAction extends StatelessWidget {
  const _GreetingAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final foreground = Colors.white.withValues(alpha: emphasized ? 1 : 0.86);

    return Material(
      color: Colors.white.withValues(alpha: emphasized ? 0.18 : 0.08),
      shape: StadiumBorder(
        side: BorderSide(
          color: Colors.white.withValues(alpha: emphasized ? 0.28 : 0.16),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        hoverColor: Colors.white.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
