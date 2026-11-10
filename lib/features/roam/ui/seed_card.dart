import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_image.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 单颗种子候选卡（步骤 B）。
///
/// 整块封面 + 底部信息 + 选中描边/光晕。父级负责给高度，卡片自己
/// 处理悬停抬升与选中态。
class SeedCard extends StatefulWidget {
  const SeedCard({
    super.key,
    required this.music,
    required this.selected,
    required this.onTap,
    this.index = 0,
    this.compact = false,
  });

  final Music music;
  final bool selected;
  final VoidCallback onTap;

  /// 从 0 开始的候选序号，用于左上角编号。
  final int index;

  /// 窄列时收紧字号与留白。
  final bool compact;

  @override
  State<SeedCard> createState() => _SeedCardState();
}

class _SeedCardState extends State<SeedCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(20);
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      label: '${widget.music.title}，${widget.music.artist.displayName}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : Colors.white.withValues(alpha: 0.14),
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
                if (selected)
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.32),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(theme),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00000000),
                          Color(0x30000000),
                          Color(0xD9000000),
                        ],
                        stops: [0.18, 0.55, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _IndexBadge(index: widget.index + 1),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _SelectionBadge(selected: selected),
                  ),
                  Positioned(
                    left: widget.compact ? 12 : 14,
                    right: widget.compact ? 12 : 14,
                    bottom: widget.compact ? 12 : 14,
                    child: _buildInfo(theme),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onTap,
                        borderRadius: radius,
                        splashColor: scheme.primary.withValues(alpha: 0.2),
                        highlightColor: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(ThemeData theme) {
    final music = widget.music;
    if (!Music.isValidImageUrl(music.coverUrl)) {
      return _placeholder(theme);
    }

    return CachedNetworkImage(
      imageUrl: biliSquareUrl(music.safeCoverUrl, 384),
      cacheKey: music.id.isEmpty ? null : '${music.id}_384',
      memCacheWidth: 384,
      cacheManager: imageCacheManager,
      httpHeaders: NetworkConfig.biliHeaders,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 260),
      placeholder: (_, _) => _placeholder(theme),
      errorWidget: (_, _, _) => _placeholder(theme),
    );
  }

  Widget _placeholder(ThemeData theme) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.68),
            scheme.tertiary.withValues(alpha: 0.86),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 42,
          color: scheme.onPrimary.withValues(alpha: 0.64),
        ),
      ),
    );
  }

  Widget _buildInfo(ThemeData theme) {
    final compact = widget.compact;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.music.title.isEmpty ? '(无标题)' : widget.music.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 13 : 15,
            height: 1.22,
            fontWeight: FontWeight.w600,
            shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.music.artist.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: compact ? 11 : 12,
            shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
          ),
        ),
      ],
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        index.toString().padLeft(2, '0'),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.34),
        border: Border.all(
          color: selected
              ? scheme.primary
              : Colors.white.withValues(alpha: 0.28),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.45),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Icon(
          selected ? Icons.check_rounded : Icons.add_rounded,
          key: ValueKey(selected),
          size: 17,
          color: selected
              ? scheme.onPrimary
              : Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
