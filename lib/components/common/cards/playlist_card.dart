import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/theme/lucent_theme.dart';

/// 歌单卡片组件 - Apple Music 样式
/// 设计:
/// - 圆角 1:1 封面
/// - 下方跟着歌单名称（无背景）
/// - 可选右下角 "+N" 数量徽章
class PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onTap;

  /// 可选数量，传入时在封面右下角显示 "+N" 徽章
  final int? count;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.count,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard>
    with SingleTickerProviderStateMixin {
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
      onEnter: (_) => _animationController.forward(),
      onExit: (_) => _animationController.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _liftAnimation.value),
            child: Transform.scale(scale: _scaleAnimation.value, child: child),
          );
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
        return _buildCard(cardWidth: 120.0, borderRadius: LucentTokens.radiusMd);
      case _:
        return _buildCard(cardWidth: 160.0, borderRadius: LucentTokens.radiusMd);
    }
  }

  Widget _buildCard({
    required double cardWidth,
    required double borderRadius,
  }) {
    return SizedBox(
      width: cardWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面区域
          SizedBox(
            width: cardWidth,
            height: cardWidth,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: _buildCoverImage(cardWidth, cardWidth),
                ),
                // "+N" 数量
                if (widget.count != null && widget.count! > 0)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _buildCountBadge(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 歌单名称
          Text(
            widget.playlist.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(double width, double height) {
    final coverUrl = widget.playlist.safeCoverUrl;

    return SizedBox.expand(
      child: coverUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: coverUrl,
              httpHeaders: NetworkConfig.biliHeaders,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  Container(color: Colors.grey[800]),
              errorWidget: (context, url, error) =>
                  Container(color: Colors.grey[800]),
              cacheManager: imageCacheManager,
            )
          : Container(color: Colors.grey[800]),
    );
  }

  Widget _buildCountBadge() {
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
        '+${widget.count}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
