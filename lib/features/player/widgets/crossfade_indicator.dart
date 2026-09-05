import 'package:flutter/material.dart';

import 'package:bilimusic/features/player/models/player_state.dart';

/// 是否处于 crossfade 过渡子态（原 mini bar / PiP / 横屏底栏各写一遍的 fading 判断）。
bool isCrossfading(PlayerState state) =>
    state is PlayerPlaying && state.fadeCountdown != null;

/// crossfade 过渡指示器 —— 10×10 spinner + 「过渡中」。
///
/// 与艺术家文本一起放进 [AnimatedSwitcher] 时，用 [isCrossfading] 选分支即可；
/// ValueKey('transition') 已内置，保证切换动画正确触发。
class CrossfadeIndicator extends StatelessWidget {
  const CrossfadeIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final transitionColor = accent.withValues(alpha: 0.8);

    return Row(
      key: const ValueKey('transition'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10, // 略小于字体高度，保持视觉平衡
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(transitionColor),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '过渡中',
            maxLines: 1,
            style: TextStyle(color: transitionColor, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
