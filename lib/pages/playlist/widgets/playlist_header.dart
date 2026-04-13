import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';

/// 歌单头部组件
class PlaylistHeader extends StatelessWidget {
  final Playlist playlist;
  final List<Music> songs;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onFavorite;
  final bool isFavorited;

  const PlaylistHeader({
    super.key,
    required this.playlist,
    this.songs = const [],
    this.onPlayAll,
    this.onShufflePlay,
    this.onFavorite,
    this.isFavorited = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final coverSize = screenWidth * 0.35;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.8),
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 顶部操作栏
              _buildTopBar(context),
              const SizedBox(height: 24),
              // 歌单封面和基本信息
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 歌单封面
                  _buildCover(context, coverSize),
                  const SizedBox(width: 16),
                  // 歌单信息
                  Expanded(child: _buildPlaylistInfo(context)),
                ],
              ),
              const SizedBox(height: 24),
              // 标签展示
              if (playlist.tagIds.isNotEmpty) ...[
                _buildTagChips(context),
                const SizedBox(height: 16),
              ],
              // 操作按钮
              _buildActionButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部操作栏
  Widget _buildTopBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black26,
            foregroundColor: Colors.white,
          ),
        ),
        Text(
          playlist.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showOptionsMenu(context),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black26,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  /// 歌单封面
  Widget _buildCover(BuildContext context, double size) {
    final coverUrl = playlist.safeCoverUrl;
    final systemIcon = playlist.systemPlaylistIcon;
    final systemIconColor = playlist.systemPlaylistIconColor;

    return Hero(
      tag: 'playlist_cover_${playlist.id}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 系统歌单显示特殊图标
              if (systemIcon != null)
                Container(
                  color: systemIconColor?.withValues(alpha: 0.15),
                  child: Center(
                    child: Icon(
                      systemIcon,
                      size: size * 0.4,
                      color: systemIconColor ?? Colors.grey,
                    ),
                  ),
                )
              // 如果有封面URL，显示图片；否则显示图标
              else if (coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  httpHeaders: NetworkConfig.biliHeaders,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.music_note, size: 48),
                  ),
                  fit: BoxFit.cover,
                  cacheManager: imageCacheManager,
                )
              else
                Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.music_note, size: 48),
                ),
              // 封面上的歌曲数量
              if (songs.isNotEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${songs.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  /// 歌单信息
  Widget _buildPlaylistInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          playlist.displayName,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          _buildInfoText(),
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        if (playlist.hasDescription) ...[
          const SizedBox(height: 8),
          Text(
            playlist.description!,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  String _buildInfoText() {
    final parts = <String>[];
    if (playlist.isSystemPlaylist) {
      parts.add('系统歌单');
    } else {
      parts.add('${songs.length}首歌曲');
    }
    if (playlist.formattedDuration.isNotEmpty) {
      parts.add(playlist.formattedDuration);
    }
    if (playlist.playCount > 0) {
      parts.add('${_formatPlayCount(playlist.playCount)}次播放');
    }
    return parts.join(' · ');
  }

  String _formatPlayCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    } else if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return count.toString();
  }

  /// 标签展示
  Widget _buildTagChips(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: playlist.tagIds.map((tagId) {
          final tag = DefaultPlaylistTags.getById(tagId);
          if (tag == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _TagChip(tag: tag),
          );
        }).toList(),
      ),
    );
  }

  /// 操作按钮
  Widget _buildActionButtons(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // 播放全部
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: songs.isNotEmpty ? onPlayAll : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放全部'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 随机播放
        Expanded(
          child: OutlinedButton.icon(
            onPressed: songs.length > 1 ? onShufflePlay : null,
            icon: const Icon(Icons.shuffle),
            label: const Text('随机'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 收藏
        IconButton(
          onPressed: onFavorite,
          icon: Icon(
            isFavorited ? Icons.favorite : Icons.favorite_border,
            color: isFavorited ? Colors.red : null,
          ),
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('分享歌单'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现分享功能
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑歌单'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现编辑功能
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载全部'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现下载功能
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 标签胶囊组件
class _TagChip extends StatelessWidget {
  final PlaylistTag tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tag.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tag.color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, size: 14, color: tag.color),
          const SizedBox(width: 4),
          Text(
            tag.nameCn,
            style: TextStyle(
              color: tag.color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
