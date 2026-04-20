import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/color_infra.dart';

/// 歌单卡片组件 - 通用的歌单展示卡片
/// 设计:
/// - 顶层: 封面图片固定在上半部分
/// - 封面左上方: 图标 + 歌单名称
/// - 中间: 直线分割线
/// - 底层: 模糊背景铺满，配合描述文字覆盖
class PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.width,
    this.height,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard>
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
        return _buildMobileCard(context);
      case ScreenSize.tablet:
        return _buildTabletCard(context);
      case ScreenSize.desktop:
        return _buildDesktopCard(context);
    }
  }

  Widget _buildCardBase({
    required double cardWidth,
    required double coverSize,
    required double borderRadius,
    required double cardHeight,
  }) {
    return Container(
      width: widget.width ?? cardWidth,
      height: widget.height ?? cardHeight,
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Column(
          children: [
            // 上半部分：封面图片（占 2/3 高度）
            Expanded(
              flex: 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面图片（正方形，全宽）
                  _buildCoverImage(coverSize, borderRadius),
                  // 左上角图标 + 名称（覆盖在封面上）
                  Positioned(top: 8, left: 4, child: _buildIconBadge()),
                ],
              ),
            ),
            // 分割线（直线，无圆角）
            Container(
              height: 1,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: highlightTextColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
            ),
            // 下半部分：模糊背景 + 描述（占 1/3 高度）
            Expanded(
              flex: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 模糊背景
                  _buildBlurBackground(),
                  // 半透明遮罩
                  Container(color: backgroundBaseColor.withValues(alpha: 0.3)),
                  // 描述文字
                  Positioned.fill(child: _buildDescription()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCard(BuildContext context) {
    const cardWidth = 120.0;
    const coverSize = 100.0;
    const borderRadius = 8.0;
    const cardHeight = 200.0;

    return _buildCardBase(
      cardWidth: cardWidth,
      coverSize: coverSize,
      borderRadius: borderRadius,
      cardHeight: cardHeight,
    );
  }

  Widget _buildTabletCard(BuildContext context) {
    const cardWidth = 160.0;
    const coverSize = 140.0;
    const borderRadius = 10.0;
    const cardHeight = 280.0;

    return _buildCardBase(
      cardWidth: cardWidth,
      coverSize: coverSize,
      borderRadius: borderRadius,
      cardHeight: cardHeight,
    );
  }

  Widget _buildDesktopCard(BuildContext context) {
    const cardWidth = 200.0;
    const coverSize = 180.0;
    const borderRadius = 12.0;
    const cardHeight = 340.0;

    return _buildCardBase(
      cardWidth: cardWidth,
      coverSize: coverSize,
      borderRadius: borderRadius,
      cardHeight: cardHeight,
    );
  }

  /// 构建封面图片
  Widget _buildCoverImage(double size, double borderRadius) {
    final coverUrl = widget.playlist.safeCoverUrl;

    return ClipRRect(
      child: SizedBox.expand(
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
      ),
    );
  }

  /// 构建左上角图标 + 名称徽章
  Widget _buildIconBadge() {
    final icon = widget.playlist.systemPlaylistIcon ?? Icons.queue_music;
    final iconColor = widget.playlist.systemPlaylistIconColor;
    final displayName = widget.playlist.displayName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor ?? Colors.white, size: 14),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建模糊背景层
  Widget _buildBlurBackground() {
    final coverUrl = widget.playlist.songs.isNotEmpty
        ? widget.playlist.songs.first.safeCoverUrl
        : null;

    if (coverUrl == null || coverUrl.isEmpty) {
      return Container(color: backgroundBaseColor);
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: backgroundBaseColor),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: backgroundBaseColor.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  /// 构建描述文本
  Widget _buildDescription() {
    final description = widget.playlist.hasDescription
        ? widget.playlist.description!
        : '共 ${widget.playlist.songCount} 首';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          description,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: highlightTextColor.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}
