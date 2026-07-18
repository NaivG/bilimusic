import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/theme/lucent_theme.dart';

/// 通用音乐列表项组件
/// 悬停/选中时背景和圆角边框从透明渐变至半透明(alpha: 0 -> 0.2)
class CommonMusicListTile extends StatefulWidget {
  final Music music;
  final PlayerCoordinator playerCoordinator;
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
  final bool showIndex;

  const CommonMusicListTile({
    super.key,
    required this.music,
    required this.playerCoordinator,
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
    this.showIndex = false,
  });

  @override
  State<CommonMusicListTile> createState() => _CommonMusicListTileState();
}

class _CommonMusicListTileState extends State<CommonMusicListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: LucentTokens.standardDuration,
        curve: Curves.easeOutCubic,
        height: 64,
        decoration: BoxDecoration(
          color: _isHovered
              ? LucentTokens.surfaceHover(brightness)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(LucentTokens.radiusSm),
        ),
        child: ContextMenuWidget(
          menuProvider: (_) => buildMusicContextMenu(
            context: context,
            music: widget.music,
            playerCoordinator: widget.playerCoordinator,
            playlistManager: widget.playlistManager,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap ?? () => _playMusic(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 16.0,
                ),
                child: Row(
                  children: [
                    if (widget.showIndex && widget.index != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: SizedBox(
                          width: 24,
                          child: Text(
                            '${widget.index! + 1}',
                            style: TextStyle(
                              fontSize: 14,
                              color: _isHovered
                                  ? theme.primaryColor
                                  : Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    if (widget.showCover) _buildCover(context),
                    if (widget.showDetails)
                      Expanded(child: _buildDetails(context)),
                    if (widget.showPageIndicator && widget.music.isSeries)
                      _buildPageIndicator(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
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
    final theme = Theme.of(context);

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
            color: _isHovered ? theme.primaryColor : null,
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
    final theme = Theme.of(context);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isHovered ? 1.0 : 0.7,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${widget.music.pages.length}P',
          style: TextStyle(
            fontSize: 11,
            color: theme.primaryColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Future<void> _playMusic(BuildContext context) async {
    final detailedMusic = await widget.music.getVideoDetails();
    widget.playerCoordinator.playMusic(detailedMusic);
  }
}
