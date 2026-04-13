import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/components/common/cards/responsive_music_card.dart';

/// 叠加卡片样式
/// 外观与普通卡片相似，右下角显示"+xxx"表示分P数量
class StackedMusicCard extends StatefulWidget {
  final Music music;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final bool showArtist;
  final bool showAlbum;
  final double? width;
  final double? height;

  /// 叠加数量配置，可覆盖自动计算的分P数量
  final int? overrideCount;

  /// 是否显示徽章
  final bool showBadge;

  const StackedMusicCard({
    super.key,
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.showArtist = true,
    this.showAlbum = true,
    this.width,
    this.height,
    this.overrideCount,
    this.showBadge = true,
  });

  @override
  State<StackedMusicCard> createState() => _StackedMusicCardState();
}

class _StackedMusicCardState extends State<StackedMusicCard> {
  /// 获取分P数量
  int get pageCount => widget.overrideCount ?? widget.music.pages.length;

  /// 是否显示叠加标识
  bool get shouldShowBadge => pageCount > 1 && widget.showBadge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap ?? () => _playMusic(context),
      onLongPress: () => _showLongPressMenu(context),
      onSecondaryTap: () => _showLongPressDialog(context),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    if (!shouldShowBadge) {
      // 单P时复用 ResponsiveMusicCard
      return ResponsiveMusicCard(
        music: widget.music,
        playerManager: widget.playerManager,
        playlistManager: widget.playlistManager,
        onTap: widget.onTap,
        showArtist: widget.showArtist,
        showAlbum: widget.showAlbum,
        width: widget.width,
        height: widget.height,
      );
    }

    final screenSize = ResponsiveHelper.getScreenSize(context);

    switch (screenSize) {
      case ScreenSize.mobile:
        return _buildMobileStackedCard(context);
      case ScreenSize.tablet:
        return _buildTabletStackedCard(context);
      case ScreenSize.desktop:
        return _buildDesktopStackedCard(context);
    }
  }

  Widget _buildPageBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '+${pageCount - 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 桌面端叠加卡片
  Widget _buildDesktopStackedCard(BuildContext context) {
    final cardWidth = widget.width ?? 200.0;
    final borderRadius = 12.0;
    const stackOffset = 10.0;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: cardWidth,
            height: cardWidth * 0.7,
            child: Stack(
              children: [
                Positioned(
                  left: stackOffset,
                  top: stackOffset,
                  child: Container(
                    width: cardWidth - stackOffset * 2,
                    height: cardWidth * 0.7 - stackOffset * 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).primaryColor.withValues(alpha: 0.3),
                          Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: _buildCoverImage(context, cardWidth, cardWidth * 0.7),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _buildPageBadge(context),
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.showArtist || widget.showAlbum) ...[
                  const SizedBox(height: 4),
                  Text(
                    _buildSubtitleText(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 平板端叠加卡片
  Widget _buildTabletStackedCard(BuildContext context) {
    final cardWidth = widget.width ?? 120.0;
    final borderRadius = 10.0;
    const stackOffset = 8.0;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: cardWidth,
            height: cardWidth,
            child: Stack(
              children: [
                Positioned(
                  left: stackOffset,
                  top: stackOffset,
                  child: Container(
                    width: cardWidth - stackOffset * 2,
                    height: cardWidth - stackOffset * 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).primaryColor.withValues(alpha: 0.3),
                          Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: _buildCoverImage(context, cardWidth, cardWidth),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: _buildPageBadge(context),
                ),
              ],
            ),
          ),
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

  /// 移动端叠加卡片
  Widget _buildMobileStackedCard(BuildContext context) {
    final cardWidth = widget.width ?? 120.0;
    final borderRadius = 8.0;
    const stackOffset = 6.0;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: cardWidth,
            height: cardWidth,
            child: Stack(
              children: [
                Positioned(
                  left: stackOffset,
                  top: stackOffset,
                  child: Container(
                    width: cardWidth - stackOffset * 2,
                    height: cardWidth - stackOffset * 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).primaryColor.withValues(alpha: 0.3),
                          Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: _buildCoverImage(context, cardWidth, cardWidth),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: _buildSmallPageBadge(context),
                ),
              ],
            ),
          ),
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

  /// 移动端小徽章
  Widget _buildSmallPageBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '+${pageCount - 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
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
}
