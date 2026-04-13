import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/search_result.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 搜索结果卡片组件 - 用于展示非Music类型的搜索结果
class SearchResultCard extends StatefulWidget {
  final SearchResult result;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final double? width;

  const SearchResultCard({
    super.key,
    required this.result,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.width,
  });

  @override
  State<SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<SearchResultCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

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
    final screenSize = ResponsiveHelper.getScreenSize(context);

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
          onLongPress: () => _showContextMenu(context),
          child: _buildCardContent(context, screenSize),
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, ScreenSize screenSize) {
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

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverImage(cardWidth, cardWidth),
          const SizedBox(height: 6),
          Text(
            widget.result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            widget.result.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletCard(BuildContext context) {
    final cardWidth = widget.width ?? 140.0;

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverImage(cardWidth, cardWidth),
          const SizedBox(height: 8),
          Text(
            widget.result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            widget.result.subtitle,
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: cardWidth,
      margin: const EdgeInsets.all(8.0),
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
                _buildCoverImage(cardWidth, cardWidth * 0.7),
                // 类型标签
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getTypeIcon(widget.result.type),
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getTypeLabel(widget.result.type),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
                  widget.result.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isHovered ? Theme.of(context).primaryColor : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.result.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(double width, double height) {
    final borderRadius = ResponsiveHelper.responsiveValue(
      context: context,
      mobile: 8.0,
      tablet: 10.0,
      desktop: 12.0,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: widget.result.coverUrl.isNotEmpty
            ? widget.result.coverUrl
            : 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png',
        httpHeaders: Map<String, String>.from(NetworkConfig.biliHeaders),
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
          child: Icon(
            _getTypeIcon(widget.result.type),
            color: Colors.grey[400],
            size: 32,
          ),
        ),
        fit: BoxFit.cover,
        width: width,
        height: height,
        cacheManager: imageCacheManager,
      ),
    );
  }

  IconData _getTypeIcon(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return Icons.music_note;
      case SearchResultType.album:
        return Icons.album;
      case SearchResultType.author:
        return Icons.person;
      case SearchResultType.bangumi:
        return Icons.tv;
      case SearchResultType.topic:
        return Icons.tag;
      case SearchResultType.upuser:
        return Icons.account_circle;
    }
  }

  String _getTypeLabel(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return '单曲';
      case SearchResultType.album:
        return '专辑';
      case SearchResultType.author:
        return 'UP主';
      case SearchResultType.bangumi:
        return '番剧';
      case SearchResultType.topic:
        return '话题';
      case SearchResultType.upuser:
        return '用户';
    }
  }

  void _showContextMenu(BuildContext context) {
    if (widget.result.type == SearchResultType.video) {
      final music = widget.result.toMusic();
      showModalBottomSheet(
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(16.0),
          child: LongPressMenu(
            music: music,
            playerManager: widget.playerManager,
            playlistManager: widget.playlistManager,
          ),
        ),
      );
    }
  }
}

/// 搜索结果网格组件
class SearchResultsGrid extends StatelessWidget {
  final List<SearchResult> results;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final Function(SearchResult) onResultTap;
  final double? itemWidth;

  const SearchResultsGrid({
    super.key,
    required this.results,
    required this.playerManager,
    this.playlistManager,
    required this.onResultTap,
    this.itemWidth,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);
    final columns = ResponsiveHelper.responsiveGridColumns(context);
    final spacing = ResponsiveHelper.responsiveSpacing(context);

    return GridView.builder(
      padding: EdgeInsets.all(spacing),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing * 1.5,
        childAspectRatio: screenSize == ScreenSize.mobile ? 0.75 : 0.8,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return SearchResultCard(
          result: result,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: () => onResultTap(result),
          width: itemWidth,
        );
      },
    );
  }
}
