import 'package:flutter/material.dart';

import '../models/music.dart' as model;

class MusicInfoWidget extends StatelessWidget {
  final model.Music music;
  final bool compact;

  const MusicInfoWidget({super.key, required this.music, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            music.title,
            style: compact
                ? textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  )
                : textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.grey[900],
                  ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (!compact) const SizedBox(height: 12),

          // 艺术家信息
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: compact ? 14 : 16,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  music.artist,
                  style: textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          if (!compact) const SizedBox(height: 8),

          // 专辑信息
          Row(
            children: [
              Icon(
                Icons.album_outlined,
                size: compact ? 14 : 16,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  music.album,
                  style: textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          if (!compact) const SizedBox(height: 16),

          // 元数据标签
          if (!compact)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 时长标签
                Chip(
                  label: Text(
                    _formatDuration(music.duration),
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: Theme.of(
                    context,
                  ).primaryColor.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
                // 来源标签
                Chip(
                  label: const Text('Bilibili', style: TextStyle(fontSize: 12)),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondary.withValues(alpha: 0.1),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
