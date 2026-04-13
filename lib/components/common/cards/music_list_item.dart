import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 列表样式组件
/// 类似于PlaylistItem，用于单page或单个id-cid实例
class MusicListItem extends StatelessWidget {
  final Music music;
  final int? index;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onDelete;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final bool showCover;
  final bool showDetails;
  final bool showPageIndicator;

  const MusicListItem({
    super.key,
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.index,
    this.isPlaying = false,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteToggle,
    this.onDelete,
    this.showCover = true,
    this.showDetails = true,
    this.showPageIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicListItemWidget(
      music: music,
      playerManager: playerManager,
      playlistManager: playlistManager,
      index: index,
      isPlaying: isPlaying,
      isFavorite: isFavorite,
      onTap: onTap,
      onFavoriteToggle: onFavoriteToggle,
      onDelete: onDelete,
      showCover: showCover,
      showDetails: showDetails,
      showPageIndicator: showPageIndicator,
    );
  }
}

class _MusicListItemWidget extends StatefulWidget {
  final Music music;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final int? index;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onDelete;
  final bool showCover;
  final bool showDetails;
  final bool showPageIndicator;

  const _MusicListItemWidget({
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.index,
    this.isPlaying = false,
    this.isFavorite = false,
    this.onTap,
    this.onFavoriteToggle,
    this.onDelete,
    this.showCover = true,
    this.showDetails = true,
    this.showPageIndicator = true,
  });

  @override
  State<_MusicListItemWidget> createState() => _MusicListItemWidgetState();
}

class _MusicListItemWidgetState extends State<_MusicListItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _isHovered
            ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
            : Colors.transparent,
        child: GestureDetector(
          onTap: widget.onTap ?? () => _playMusic(context),
          onLongPress: () => _showLongPressMenu(context),
          onSecondaryTap: () => _showLongPressDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
            child: Row(
              children: [
                if (widget.index != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: SizedBox(
                      width: 24,
                      child: Text(
                        '${widget.index! + 1}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                if (widget.showCover) _buildCover(context),
                if (widget.showDetails) Expanded(child: _buildDetails(context)),
                if (widget.showPageIndicator && widget.music.isSeries)
                  _buildPageIndicator(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48,
      height: 48,
      margin: const EdgeInsets.only(right: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: widget.music.safeCoverUrl,
          httpHeaders: NetworkConfig.biliHeaders,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey[400],
                ),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey[200],
            child: Icon(Icons.music_note, color: Colors.grey[400], size: 24),
          ),
          fit: BoxFit.cover,
          cacheManager: imageCacheManager,
          cacheKey: widget.music.id,
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.music.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: _isHovered ? Theme.of(context).primaryColor : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.music.artist} - ${widget.music.album}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildPageIndicator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${widget.music.pages.length}P',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _playMusic(BuildContext context) async {
    final detailedMusic = await widget.music.getVideoDetails();
    widget.playerManager.play(detailedMusic);
  }

  void _showLongPressMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: LongPressMenu(
          music: widget.music,
          playerManager: widget.playerManager,
          playlistManager: widget.playlistManager,
        ),
      ),
    );
  }

  void _showLongPressDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(16.0),
          content: LongPressMenu(
            music: widget.music,
            playerManager: widget.playerManager,
            playlistManager: widget.playlistManager,
          ),
        );
      },
    );
  }
}
