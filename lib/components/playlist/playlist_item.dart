import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';

/// 播放列表中的歌曲项组件
class PlaylistItem extends StatelessWidget {
  final Music music;
  final int index;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onDelete;

  const PlaylistItem({
    super.key,
    required this.music,
    required this.index,
    required this.isPlaying,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey(
        'dismiss_${music.id}_${music.pages.isNotEmpty ? music.pages[0].cid : "0"}',
      ),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        onDelete();
        return false;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isPlaying
                  ? (theme.colorScheme.primary.withValues(alpha: 0.15))
                  : Colors.transparent,
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: isPlaying
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                // 专辑封面
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CachedNetworkImage(
                      imageUrl: music.safeCoverUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: Icon(
                          Icons.music_note,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: Icon(
                          Icons.music_note,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 歌曲信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isPlaying) ...[
                            _PlayingIndicator(color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              music.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isPlaying
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isPlaying
                                    ? theme.colorScheme.primary
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${music.artist} - ${music.album}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isPlaying
                              ? theme.colorScheme.primary.withValues(alpha: 0.7)
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 操作按钮
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 收藏按钮
                    IconButton(
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                        color: isFavorite ? Colors.red : null,
                        size: 22,
                      ),
                      onPressed: onFavoriteToggle,
                      splashRadius: 20,
                    ),
                    // 拖拽手柄
                    ReorderableDragStartListener(
                      index: index,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle,
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                          size: 22,
                        ),
                      ),
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

/// 播放中指示器（音浪动画）
class _PlayingIndicator extends StatefulWidget {
  final Color color;

  const _PlayingIndicator({required this.color});

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((_controller.value + delay) % 1.0);
            return Container(
              width: 3,
              height: 8 + (value * 8),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}
