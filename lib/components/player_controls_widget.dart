import 'package:flutter/material.dart';

class PlayerControlsWidget extends StatelessWidget {
  final bool isPlaying;
  final Duration position;
  final Duration? duration;
  final IconData playModeIcon;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayMode;
  final VoidCallback onOpenPlayList;
  final ValueChanged<double> onSeek;
  final bool compact;

  const PlayerControlsWidget({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.playModeIcon,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayMode,
    required this.onOpenPlayList,
    required this.onSeek,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;

    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 进度条和时间显示
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Theme.of(context).primaryColor,
                      inactiveTrackColor: isDark ? Colors.grey[700] : Colors.grey[300],
                      thumbColor: Theme.of(context).primaryColor,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      min: 0,
                      max: (duration?.inSeconds ?? 0).toDouble(),
                      value: position.inSeconds.toDouble(),
                      onChanged: onSeek,
                    ),
                  ),
                ),
              ),
              Text(
                _formatDuration(duration ?? Duration.zero),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          
          SizedBox(height: compact ? 16 : 20),
          
          // 主要控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 播放模式按钮
              IconButton(
                icon: Icon(playModeIcon),
                iconSize: compact ? 20 : (isLargeScreen ? 24 : 22),
                color: Theme.of(context).primaryColor,
                onPressed: onTogglePlayMode,
              ),
              
              // 上一首按钮
              IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: compact ? 24 : (isLargeScreen ? 28 : 26),
                color: Theme.of(context).primaryColor,
                onPressed: onPrevious,
              ),
              
              // 播放/暂停按钮
              Container(
                width: compact ? 50 : (isLargeScreen ? 60 : 55),
                height: compact ? 50 : (isLargeScreen ? 60 : 55),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: compact ? 24 : (isLargeScreen ? 28 : 26),
                  onPressed: onPlayPause,
                ),
              ),
              
              // 下一首按钮
              IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: compact ? 24 : (isLargeScreen ? 28 : 26),
                color: Theme.of(context).primaryColor,
                onPressed: onNext,
              ),
              
              // 播放列表按钮
              IconButton(
                icon: const Icon(Icons.playlist_play),
                iconSize: compact ? 20 : (isLargeScreen ? 24 : 22),
                color: Theme.of(context).primaryColor,
                onPressed: onOpenPlayList,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}