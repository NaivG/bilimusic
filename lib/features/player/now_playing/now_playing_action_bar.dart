import 'package:flutter/material.dart';

import 'package:bilimusic/features/player/widgets/playback_buttons.dart';

/// 播放详情页底部的三<s>兄贵</s>按钮操作条：同步 / 定时 / 歌词。
class NowPlayingActionBar extends StatelessWidget {
  static const double _buttonSize = 48;
  static const double _iconSize = 26;

  final bool lyricsActive;
  final VoidCallback onSync;
  final VoidCallback onTimer;
  final VoidCallback onToggleLyrics;

  const NowPlayingActionBar({
    super.key,
    required this.lyricsActive,
    required this.onSync,
    required this.onTimer,
    required this.onToggleLyrics,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          PlaybackControlButton(
            icon: Icons.cast_rounded,
            size: _buttonSize,
            iconSize: _iconSize,
            iconColor: Colors.white.withValues(alpha: 0.7),
            semanticLabel: '同步',
            onTap: onSync,
          ),
          PlaybackControlButton(
            icon: Icons.timer_outlined,
            size: _buttonSize,
            iconSize: _iconSize,
            iconColor: Colors.white.withValues(alpha: 0.7),
            semanticLabel: '定时',
            onTap: onTimer,
          ),
          PlaybackControlButton(
            icon: lyricsActive ? Icons.lyrics : Icons.lyrics_outlined,
            size: _buttonSize,
            iconSize: _iconSize,
            iconColor: lyricsActive
                ? Colors.white
                : Colors.white.withValues(alpha: 0.7),
            semanticLabel: '歌词',
            onTap: onToggleLyrics,
          ),
        ],
      ),
    );
  }
}
