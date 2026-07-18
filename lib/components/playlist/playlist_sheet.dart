import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/components/playlist/playlist_item.dart';
import 'package:bilimusic/theme/lucent_theme.dart';

/// 播放列表弹出组件
/// 支持可调整高度的底部弹窗、拖拽排序和流畅动画
class PlaylistSheet extends ConsumerStatefulWidget {
  final Function(int) onTrackSelect;

  const PlaylistSheet({super.key, required this.onTrackSelect});

  @override
  ConsumerState<PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends ConsumerState<PlaylistSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    // ReorderableListView 在 newIndex 大于 oldIndex 时需要减 1
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    await ref
        .read(playbackCommandsProvider.notifier)
        .moveInPlaylist(oldIndex, newIndex);
    // moveInPlaylist 会触发通知，无需手动 setState
  }

  void _showDeleteConfirmation(BuildContext context, Music music, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌曲'),
        content: Text('确定要从播放列表中移除"${music.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(playbackCommandsProvider.notifier)
                  .removeFromPlaylist(music);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentIndexProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentIndex = ref.watch(currentIndexProvider) ?? -1;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.25,
          maxChildSize: 0.9,
          snap: true,
          snapSizes: const [0.25, 0.5, 0.75, 0.9],
          builder: (context, scrollController) {
            final sheetTheme = Theme.of(context);
            final sheetBrightness = sheetTheme.brightness;
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(LucentTokens.radiusLg),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: LucentTokens.glassBlurSigma,
                  sigmaY: LucentTokens.glassBlurSigma,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: LucentTokens.surfaceOverlay(sheetBrightness),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(LucentTokens.radiusLg),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDragHandle(isDark),
                      _buildHeader(context, isDark),
                      Expanded(
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildPlaylist(
                            context,
                            scrollController,
                            currentIndex,
                            isDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDragHandle(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[600] : Colors.grey[400],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    final playlistLength = ref.watch(currentPlaylistProvider).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.queue_music, size: 24),
          const SizedBox(width: 8),
          const Text(
            '播放列表',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '$playlistLength 首歌曲',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const Spacer(),
          if (playlistLength > 0)
            TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清空播放列表'),
                    content: const Text('确定要清空当前播放列表吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          ref
                              .read(playbackCommandsProvider.notifier)
                              .clearPlaylist();
                        },
                        child: const Text(
                          '清空',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('清空'),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylist(
    BuildContext context,
    ScrollController scrollController,
    int currentIndex,
    bool isDark,
  ) {
    final playlist = ref.watch(currentPlaylistProvider);

    if (playlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.queue_music,
              size: 64,
              color: isDark ? Colors.grey[700] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '播放列表为空',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '添加歌曲开始播放',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      scrollController: scrollController,
      itemCount: playlist.length,
      onReorder: _handleReorder,
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final scale = Tween<double>(begin: 1.0, end: 1.05)
                .animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                )
                .value;
            return Transform.scale(
              scale: scale,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
                child: child,
              ),
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final music = playlist[index];
        final isPlaying = index == currentIndex;

        return PlaylistItem(
          key: ValueKey(index),
          music: music,
          index: index,
          isPlaying: isPlaying,
          isFavorite: ref
              .read(playbackCommandsProvider.notifier)
              .isFavorite(music),
          onTap: () {
            widget.onTrackSelect(index);
          },
          onFavoriteToggle: () async {
            final commands = ref.read(playbackCommandsProvider.notifier);
            if (commands.isFavorite(music)) {
              await commands.removeFromFavorites(music);
            } else {
              await commands.addToFavorites(music);
            }
            setState(() {});
          },
          onDelete: () => _showDeleteConfirmation(context, music, index),
        );
      },
    );
  }
}
