import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';

/// 歌单头部组件
/// 水平布局：左侧封面 + 右侧信息 + 下方控制按钮
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCover(context),
            const SizedBox(width: 16),
            Expanded(child: _buildInfoColumn(context)),
          ],
        ),
        const SizedBox(height: 16),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildCover(BuildContext context) {
    final coverSize = 140.0;
    final coverUrl = playlist.safeCoverUrl;
    final systemIcon = playlist.systemPlaylistIcon;
    final systemIconColor = playlist.systemPlaylistIconColor;

    return Hero(
      tag: 'playlist_cover_${playlist.id}',
      child: Container(
        width: coverSize,
        height: coverSize,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (systemIcon != null)
                Container(
                  color: systemIconColor?.withValues(alpha: 0.15),
                  child: Center(
                    child: Icon(
                      systemIcon,
                      size: coverSize * 0.4,
                      color: systemIconColor ?? Colors.grey,
                    ),
                  ),
                )
              else if (coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  httpHeaders: NetworkConfig.biliHeaders,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[800],
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.music_note, size: 48, color: Colors.white54),
                  ),
                  fit: BoxFit.cover,
                  cacheManager: imageCacheManager,
                )
              else
                Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.music_note, size: 48, color: Colors.white54),
                ),
              if (songs.isNotEmpty)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow, color: Colors.white, size: 14),
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

  Widget _buildInfoColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 歌单名称 + 系统图标
        Row(
          children: [
            if (playlist.systemPlaylistIcon != null) ...[
              Icon(
                playlist.systemPlaylistIcon,
                size: 20,
                color: playlist.systemPlaylistIconColor ?? Colors.grey,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                playlist.displayName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 描述
        if (playlist.hasDescription) ...[
          Text(
            playlist.description!,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
        ],
        // 属性信息
        Text(
          _buildInfoText(),
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  String _buildInfoText() {
    final parts = <String>[];
    parts.add('${songs.length}首歌曲');
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

  Widget _buildActionButtons(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
            padding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }
}
