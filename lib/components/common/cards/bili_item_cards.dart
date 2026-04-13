import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/bili_item.dart';
import 'package:bilimusic/models/music.dart';
// import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

// ============================================================================
// ResponsiveBiliItemCard
// ============================================================================

/// 响应式 BiliItem 卡片 - 用于展示视频级信息
/// 播放时使用 biliItem.pages.first (第一个分P)
class ResponsiveBiliItemCard extends StatefulWidget {
  final BiliItem biliItem;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final bool showOwner;
  final bool showStat;
  final double? width;
  final double? height;

  const ResponsiveBiliItemCard({
    super.key,
    required this.biliItem,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.showOwner = true,
    this.showStat = false,
    this.width,
    this.height,
  });

  @override
  State<ResponsiveBiliItemCard> createState() => _ResponsiveBiliItemCardState();
}

class _ResponsiveBiliItemCardState extends State<ResponsiveBiliItemCard>
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
            widget.biliItem.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          if (widget.showOwner)
            Text(
              widget.biliItem.owner.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          if (widget.biliItem.isSeries) _buildPageBadge(context),
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
            widget.biliItem.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          if (widget.showOwner)
            Text(
              widget.biliItem.owner.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          if (widget.biliItem.isSeries) _buildPageBadge(context),
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
                  if (widget.biliItem.isSeries)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _buildPageBadge(context),
                    ),
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
                    widget.biliItem.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _isHovered ? Theme.of(context).primaryColor : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (widget.showOwner)
                    Text(
                      widget.biliItem.owner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  if (widget.showStat) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${widget.biliItem.stat.formattedView}播放',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
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
        imageUrl: widget.biliItem.safeCoverUrl,
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
          child: Icon(Icons.video_library, color: Colors.grey[400], size: 32),
        ),
        fit: BoxFit.cover,
        width: width,
        height: height,
        cacheManager: imageCacheManager,
        cacheKey: widget.biliItem.bvid,
      ),
    );
  }

  Widget _buildPageBadge(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${widget.biliItem.pages.length}P',
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _playBiliItem(BuildContext context) async {
    // 默认播放第一个分P
    final firstPage = widget.biliItem.pages.first;
    final detailedMusic = await firstPage.getVideoDetails();
    widget.playerManager.play(detailedMusic);
  }
}

// ============================================================================
// HorizontalBiliItemCard
// ============================================================================

/// 水平布局的 BiliItem 卡片（用于列表视图）
class HorizontalBiliItemCard extends StatefulWidget {
  final BiliItem biliItem;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final bool showCover;
  final bool showDetails;
  final bool showStat;

  const HorizontalBiliItemCard({
    super.key,
    required this.biliItem,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.showCover = true,
    this.showDetails = true,
    this.showStat = false,
  });

  @override
  State<HorizontalBiliItemCard> createState() => _HorizontalBiliItemCardState();
}

class _HorizontalBiliItemCardState extends State<HorizontalBiliItemCard> {
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
          onTap: widget.onTap ?? () => _playBiliItem(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 16.0,
            ),
            child: Row(
              children: [
                if (widget.showCover) _buildCover(context),
                if (widget.showDetails) Expanded(child: _buildDetails(context)),
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
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: widget.biliItem.safeCoverUrl,
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
                  Icons.video_library,
                  color: Colors.grey[400],
                  size: 24,
                ),
              ),
              fit: BoxFit.cover,
              cacheManager: imageCacheManager,
              cacheKey: widget.biliItem.bvid,
            ),
            if (widget.biliItem.isSeries)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${widget.biliItem.pages.length}P',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.biliItem.title,
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
          widget.biliItem.owner.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        if (widget.showStat) ...[
          const SizedBox(height: 2),
          Text(
            '${widget.biliItem.stat.formattedView}播放 · ${widget.biliItem.tname}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Future<void> _playBiliItem(BuildContext context) async {
    // 默认播放第一个分P
    final firstPage = widget.biliItem.pages.first;
    final detailedMusic = await firstPage.getVideoDetails();
    widget.playerManager.play(detailedMusic);
  }
}

// ============================================================================
// BiliItemCardFactory
// ============================================================================

/// BiliItem 卡片工厂
class BiliItemCardFactory {
  /// 根据渲染样式创建卡片
  static Widget create({
    required BiliItem biliItem,
    required PlayerManager playerManager,
    PlaylistManager? playlistManager,
    MusicRenderStyle? style,
    VoidCallback? onTap,
    bool showOwner = true,
    bool showStat = false,
    double? width,
    double? height,
  }) {
    final renderStyle = style ?? biliItem.renderStyle;

    switch (renderStyle) {
      case MusicRenderStyle.card:
        return ResponsiveBiliItemCard(
          biliItem: biliItem,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: onTap,
          showOwner: showOwner,
          showStat: showStat,
          width: width,
          height: height,
        );

      case MusicRenderStyle.stacked:
        // 叠加样式也复用 ResponsiveBiliItemCard，由 BiliItem.isSeries 控制徽章显示
        return ResponsiveBiliItemCard(
          biliItem: biliItem,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: onTap,
          showOwner: showOwner,
          showStat: showStat,
          width: width,
          height: height,
        );

      case MusicRenderStyle.list:
        return HorizontalBiliItemCard(
          biliItem: biliItem,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: onTap,
          showCover: true,
          showDetails: true,
          showStat: showStat,
        );
    }
  }
}
