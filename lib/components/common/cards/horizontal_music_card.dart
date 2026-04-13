import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 水平布局的音乐卡片（用于列表视图）
class HorizontalMusicCard extends StatefulWidget {
  final Music music;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final bool showCover;
  final bool showDetails;

  const HorizontalMusicCard({
    super.key,
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.showCover = true,
    this.showDetails = true,
  });

  @override
  State<HorizontalMusicCard> createState() => _HorizontalMusicCardState();
}

class _HorizontalMusicCardState extends State<HorizontalMusicCard> {
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
                if (widget.showCover)
                  AnimatedContainer(
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
                          child: Icon(
                            Icons.music_note,
                            color: Colors.grey[400],
                            size: 24,
                          ),
                        ),
                        fit: BoxFit.cover,
                        cacheManager: imageCacheManager,
                        cacheKey: widget.music.id,
                      ),
                    ),
                  ),
                if (widget.showDetails)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.music.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _isHovered
                                ? Theme.of(context).primaryColor
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.music.artist} - ${widget.music.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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
