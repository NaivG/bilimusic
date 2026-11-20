import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_image.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/playlist.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 共享漫游歌单选择器。
///
/// 提供：
/// - 顶部 banner（介绍 + 警告）
/// - 歌单卡片（favorites + 用户自建）
/// - 空状态
///
/// 通过 [onPlaylistSelected] 回调让调用方决定选中后的行为，避免本组件直接耦合
/// 到 PlayerCoordinator。
class RoamPlaylistPicker extends ConsumerWidget {
  const RoamPlaylistPicker({
    super.key,
    this.showTitle = true,
    this.showBanner = true,
    this.scrollController,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    required this.onPlaylistSelected,
  });

  /// 是否显示 "选择漫游种子歌单" 标题。
  final bool showTitle;

  /// 是否显示顶部介绍/警告横幅。
  final bool showBanner;

  /// 滚动控制器，用于接入 DraggableScrollableSheet 的拖拽行为。
  final ScrollController? scrollController;

  /// 列表内边距；onboarding 的面板会自己收紧。
  final EdgeInsetsGeometry padding;

  /// 用户点选歌单后的回调。
  final void Function(String playlistId, String playlistName, int songCount)
  onPlaylistSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final userPlaylists = ref.watch(userPlaylistsProvider);
    final scheme = Theme.of(context).colorScheme;

    final cards = <Widget>[
      if (favorites.isNotEmpty)
        _PlaylistCard(
          playlistId: 'favorites',
          name: DefaultPlaylists.favorites.name,
          songCount: favorites.length,
          // 取封面数量，后端有做多个封面渲染的逻辑，根据口味可修改，但是取一个完事了管他呢
          coverSongs: favorites.take(1).toList(),
          fallbackIcon: Icons.favorite_rounded,
          accent: Colors.red,
          onTap: onPlaylistSelected,
        ),
      for (final playlist in userPlaylists)
        _PlaylistCard(
          playlistId: playlist.id,
          name: playlist.name,
          songCount: playlist.songCount,
          coverUrl: playlist.coverUrl,
          coverSongs: playlist.songs.take(1).toList(),
          fallbackIcon: Icons.queue_music_rounded,
          accent: scheme.primary,
          onTap: onPlaylistSelected,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择漫游种子歌单',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        if (showBanner) const RoamBanner(),
        if (showBanner) const SizedBox(height: 8),
        Expanded(
          child: cards.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  controller: scrollController,
                  padding: padding,
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => cards[index],
                ),
        ),
      ],
    );
  }
}

/// 介绍 + 警告横幅：提醒 "将清空当前队列"。
class RoamBanner extends StatelessWidget {
  const RoamBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(
          color: scheme.secondary.withValues(alpha: 0.24),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '全新功能：漫游模式',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '基于所选歌单，无限发现相似音乐。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '进入后将清空当前播放队列',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHigh,
              ),
              child: Icon(
                Icons.library_music_outlined,
                size: 30,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有可漫游的歌单',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '先收藏几首歌，或创建一个歌单再回来',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatefulWidget {
  const _PlaylistCard({
    required this.playlistId,
    required this.name,
    required this.songCount,
    required this.fallbackIcon,
    required this.accent,
    required this.onTap,
    this.coverUrl,
    this.coverSongs = const [],
  });

  final String playlistId;
  final String name;
  final int songCount;
  final String? coverUrl;
  final List<Music> coverSongs;
  final IconData fallbackIcon;
  final Color accent;
  final void Function(String playlistId, String playlistName, int songCount)
  onTap;

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.songCount > 0;
    final radius = BorderRadius.circular(AppTokens.radiusMd + 4);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedScale(
        scale: _hovered ? 1.012 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.primaryContainer.withValues(alpha: 0.22)
                : scheme.surface.withValues(alpha: 0.42),
            borderRadius: radius,
            border: Border.all(
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.55)
                  : scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled
                  ? () => widget.onTap(
                      widget.playlistId,
                      widget.name,
                      widget.songCount,
                    )
                  : null,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    _PlaylistThumb(
                      coverUrl: widget.coverUrl,
                      coverSongs: widget.coverSongs,
                      fallbackIcon: widget.fallbackIcon,
                      accent: widget.accent,
                      enabled: enabled,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: enabled
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            enabled ? '${widget.songCount} 首歌曲 · 可以漫游' : '空歌单',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hovered && enabled
                            ? scheme.primary
                            : scheme.surfaceContainerHigh,
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: _hovered && enabled
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistThumb extends StatelessWidget {
  const _PlaylistThumb({
    required this.coverUrl,
    required this.coverSongs,
    required this.fallbackIcon,
    required this.accent,
    required this.enabled,
  });

  final String? coverUrl;
  final List<Music> coverSongs;
  final IconData fallbackIcon;
  final Color accent;
  final bool enabled;

  static const double _size = 54;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urls = <String>[];

    if (Music.isValidImageUrl(coverUrl)) {
      urls.add(coverUrl!);
    } else {
      for (final music in coverSongs) {
        if (!Music.isValidImageUrl(music.coverUrl)) continue;
        urls.add(music.safeCoverUrl);
        if (urls.length >= 4) break;
      }
    }

    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: SizedBox(
        width: _size,
        height: _size,
        child: urls.isEmpty
            ? _placeholder(scheme)
            : urls.length >= 4
            ? _mosaic(urls)
            : _image(urls.first),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: enabled ? 1 : 0.45, child: thumb),
        if (urls.isEmpty)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.92),
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Icon(fallbackIcon, size: 10, color: _contrastOn(accent)),
            ),
          ),
      ],
    );
  }

  Widget _mosaic(List<String> urls) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(urls[0])),
              const SizedBox(width: 1.5),
              Expanded(child: _image(urls[1])),
            ],
          ),
        ),
        const SizedBox(height: 1.5),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _image(urls[2])),
              const SizedBox(width: 1.5),
              Expanded(child: _image(urls[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _image(String url) {
    return CachedNetworkImage(
      imageUrl: biliSquareUrl(url, 128),
      memCacheWidth: 128,
      cacheManager: imageCacheManager,
      httpHeaders: NetworkConfig.biliHeaders,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 220),
      placeholder: (context, _) => _placeholder(Theme.of(context).colorScheme),
      errorWidget: (context, _, _) =>
          _placeholder(Theme.of(context).colorScheme),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.28),
            scheme.primary.withValues(alpha: 0.48),
          ],
        ),
      ),
      child: Icon(fallbackIcon, color: Colors.white.withValues(alpha: 0.9)),
    );
  }
}

Color _contrastOn(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : Colors.black;
}
