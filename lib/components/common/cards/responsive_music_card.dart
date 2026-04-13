import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 响应式音乐卡片组件 - 支持悬停和触摸动效
class ResponsiveMusicCard extends StatefulWidget {
  final Music music;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final bool showArtist;
  final bool showAlbum;
  final double? width;
  final double? height;

  const ResponsiveMusicCard({
    super.key,
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.showArtist = true,
    this.showAlbum = true,
    this.width,
    this.height,
  });

  @override
  State<ResponsiveMusicCard> createState() => _ResponsiveMusicCardState();
}

class _ResponsiveMusicCardState extends State<ResponsiveMusicCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _liftAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _liftAnimation = Tween<double>(begin: 0.0, end: -4.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _animationController.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: GestureDetector(
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          onLongPress: () => _showLongPressMenu(context),
          onSecondaryTap: () => _showLongPressDialog(context),
          child: _buildCardContent(context),
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return _buildMobileCard(context);
      case ScreenSize.tablet:
        return _buildTabletCard(context);
      case ScreenSize.desktop:
        return _buildDesktopCard(context);
    }
  }

  Widget _buildMobileCard(BuildContext context) {
    final cardWidth = widget.width ?? 120.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverImage(context, cardWidth, cardWidth),
          const SizedBox(height: 6),
          Text(
            widget.music.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          if (widget.showArtist || widget.showAlbum)
            Text(
              _buildSubtitleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _buildTabletCard(BuildContext context) {
    final cardWidth = widget.width ?? 120.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverImage(context, cardWidth, cardWidth),
          const SizedBox(height: 6),
          Text(
            widget.music.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (widget.showArtist || widget.showAlbum)
            Text(
              _buildSubtitleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopCard(BuildContext context) {
    final cardWidth = widget.width ?? 200.0;
    final borderRadius = 12.0;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _liftAnimation.value),
          child: Transform.scale(scale: _scaleAnimation.value, child: child),
        );
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.15),
              spreadRadius: _isHovered ? 2 : 0,
              blurRadius: _isHovered ? 12 : 8,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(borderRadius),
              ),
              child: Stack(
                children: [
                  _buildCoverImage(context, cardWidth, cardWidth * 0.7),
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isHovered ? 1.0 : 0.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(borderRadius),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.4),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.9),
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.music.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _isHovered ? Theme.of(context).primaryColor : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (widget.showArtist || widget.showAlbum)
                    Text(
                      _buildSubtitleText(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, double width, double height) {
    final borderRadius = ResponsiveHelper.responsiveValue(
      context: context,
      mobile: 8.0,
      tablet: 10.0,
      desktop: 12.0,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: widget.music.safeCoverUrl,
        httpHeaders: NetworkConfig.biliHeaders,
        placeholder: (context, url) => Container(
          color: Colors.grey[200],
          width: width,
          height: height,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[400],
              ),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[200],
          width: width,
          height: height,
          child: Icon(Icons.music_note, color: Colors.grey[400], size: 32),
        ),
        fit: BoxFit.cover,
        width: width,
        height: height,
        cacheManager: imageCacheManager,
        cacheKey: widget.music.id,
      ),
    );
  }

  String _buildSubtitleText() {
    final parts = <String>[];
    if (widget.showArtist && widget.music.artist.isNotEmpty) {
      parts.add(widget.music.artist);
    }
    if (widget.showAlbum && widget.music.album.isNotEmpty) {
      parts.add(widget.music.album);
    }
    return parts.join(' - ');
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
