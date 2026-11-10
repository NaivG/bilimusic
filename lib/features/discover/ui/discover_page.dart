import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/discover/discover_providers.dart';
import 'package:bilimusic/features/discover/widgets/discover_music_tile.dart';
import 'package:bilimusic/features/discover/widgets/hot_song_card.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/overlay/bm_toast.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/sections/bm_section_header.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/status/bm_skeleton.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// 发现页：B 站平台数据（热歌榜 / 音乐区排行 / 音乐区推荐流）。
///
/// 这里只放平台侧的数据，不掺个人列表。数据全部走缓存 + 过期重取，
/// 页面切走再回来不会重复请求。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  /// 音乐区排行默认展开的条数（缓存里有 30 条，展开后一次看全）。
  static const int _rankPreviewCount = 20;

  /// 宽屏网格列数（横屏内容区 ≥1200 四列，900–1199 三列）。
  static const int _wideColumns = 4;
  static const int _mediumColumns = 3;

  bool _rankExpanded = false;
  bool _refreshingAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  void _ensureLoaded() {
    if (!mounted) return;
    unawaited(ref.read(hotSongsProvider.notifier).ensureLoaded());
    unawaited(ref.read(musicRankProvider.notifier).ensureLoaded());
    unawaited(ref.read(discoverFeedProvider.notifier).ensureLoaded());
  }

  Future<void> _refreshAll() async {
    if (_refreshingAll) return;
    setState(() => _refreshingAll = true);

    // 顺序刷新
    final hot = await ref.read(hotSongsProvider.notifier).refresh();
    final rank = await ref.read(musicRankProvider.notifier).refresh();
    final feed = await ref.read(discoverFeedProvider.notifier).refresh();
    if (!mounted) return;

    setState(() => _refreshingAll = false);
    final throttled = [hot, rank, feed].where((ok) => !ok).length;
    if (throttled == 3) {
      _showSnack('刚刚刷新过，请稍后再试');
    } else if (throttled > 0) {
      _showSnack('部分数据刚刷新过，其余已更新');
    }
  }

  Future<void> _nextBatch() async {
    await ref.read(discoverFeedProvider.notifier).nextBatch();
    if (!mounted) return;
    final error = ref.read(discoverFeedProvider).errorMessage;
    if (error != null) _showSnack(error);
  }

  Future<void> _playAllHotSongs(List<HotSong> songs) async {
    final playable = songs
        .where((s) => s.isPlayable)
        .map((s) => s.toMusic())
        .toList();
    if (playable.isEmpty) {
      _showSnack('热歌榜暂时没有可播放的稿件');
      return;
    }
    await ref.read(playbackCommandsProvider.notifier).clearPlaylist();
    await ref
        .read(playlistCommandsProvider.notifier)
        .addAllToPlaylist(playable);
    await ref.read(playbackCommandsProvider.notifier).playMusic(playable.first);
  }

  void _playHotSong(HotSong song) {
    if (!song.isPlayable) {
      _showSnack('这首暂时没有可用稿件');
      return;
    }
    ref.read(playbackCommandsProvider.notifier).playMusic(song.toMusic());
  }

  void _playMusic(Music music) {
    ref.read(playbackCommandsProvider.notifier).playMusic(music);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    showBmToast(context, message);
  }

  /// 曲目行的右键 / 长按菜单：与搜索结果、歌单列表共用同一套菜单。
  ///
  /// 菜单在展开时才读取 Provider，页面构建期不会初始化播放器与歌单服务。
  MenuProvider _musicContextMenu(Music music) {
    return (_) => buildMusicContextMenu(
      context: context,
      music: music,
      playerCoordinator: ref.read(playerCoordinatorProvider),
      commands: ref.read(playlistCommandsProvider.notifier),
      playlistService: ref.read(playlistServiceProvider),
      ref: ref,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hot = ref.watch(hotSongsProvider);
    final rank = ref.watch(musicRankProvider);
    final feed = ref.watch(discoverFeedProvider);

    final size = MediaQuery.sizeOf(context);
    final wide =
        LandscapeBreakpoints.shouldUseLandscapeLayout(context) &&
        size.width >= 900;
    final columns = size.width >= 1200 ? _wideColumns : _mediumColumns;
    final side = wide ? BmTokens.contentInset : BmTokens.pageInset;

    return Scaffold(
      // 透出壳层的流体背景；页面本身不再铺一层底色。
      backgroundColor: context.bmColors.bg.withAlpha(0),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth - side * 2;
            final cellWidth =
                (contentWidth - BmTokens.s3 * (columns - 1)) / columns;
            final cardExtent = cellWidth + BmTokens.s8 * 2 + BmTokens.s4;
            final hotExtent = cellWidth < 300
                ? BmTokens.s2 * 2 +
                      BmTokens.controlLg +
                      BmTokens.s2 +
                      BmTokens.controlLg +
                      BmTokens.s2
                : BmTokens.s2 * 2 +
                      BmTokens.row +
                      BmTokens.s2 +
                      BmTokens.row +
                      BmTokens.s2;

            return RefreshIndicator(
              onRefresh: _refreshAll,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _pad(
                    side,
                    SliverToBoxAdapter(
                      child: _buildHeader(context, wide: wide),
                    ),
                  ),
                  ..._buildHotSection(
                    context,
                    hot,
                    side: side,
                    wide: wide,
                    columns: columns,
                    hotExtent: hotExtent,
                  ),
                  ..._buildRankSection(
                    context,
                    rank,
                    side: side,
                    wide: wide,
                    columns: columns,
                    cardExtent: cardExtent,
                  ),
                  ..._buildFeedSection(
                    context,
                    feed,
                    side: side,
                    wide: wide,
                    columns: columns,
                    cardExtent: cardExtent,
                  ),
                  // 给竖屏浮动的迷你播放器 / Dock 让位；横屏该值即底部安全区。
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _pad(double side, Widget sliver) => SliverPadding(
    padding: EdgeInsets.symmetric(horizontal: side),
    sliver: sliver,
  );

  // ---------------------------------------------------------------- 页头

  Widget _buildHeader(BuildContext context, {required bool wide}) {
    return BmPageHeader(
      title: '发现',
      subtitle: 'B 站平台数据：热歌榜、音乐区排行与推荐流',
      padding: EdgeInsets.only(
        top: wide ? BmTokens.contentInsetTop : BmTokens.s4,
        bottom: BmTokens.s2,
      ),
      actions: [
        if (_refreshingAll)
          SizedBox(
            width: BmTokens.touchDesktop,
            height: BmTokens.touchDesktop,
            child: Center(
              child: SizedBox(
                width: BmTokens.s4,
                height: BmTokens.s4,
                child: CircularProgressIndicator(strokeWidth: BmTokens.s1 / 2),
              ),
            ),
          )
        else
          BmIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新全部',
            onPressed: () => unawaited(_refreshAll()),
          ),
      ],
    );
  }

  /// 分区标题：统一走 [BmSectionHeader]，副标题作为标题下方的一行说明。
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final colors = context.bmColors;
    final type = context.bmType;
    final subtitleText = subtitle?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: BmTokens.s6, bottom: BmTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BmSectionHeader(
            title: title,
            trailing: trailing,
            padding: EdgeInsets.zero,
          ),
          if (subtitleText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: BmTokens.s1),
              child: Text(
                subtitleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- 热歌榜

  List<Widget> _buildHotSection(
    BuildContext context,
    HotSongsState hot, {
    required double side,
    required bool wide,
    required int columns,
    required double hotExtent,
  }) {
    final parts = <String>[];
    if (hot.period > 0) parts.add('第 ${hot.period} 期');
    final publishedAt = hot.publishedAt;
    if (publishedAt != null) parts.add('${_formatDate(publishedAt)} 发布');
    if (hot.fromCache && !hot.isEmpty) parts.add('缓存');

    final header = _buildSectionHeader(
      context,
      title: '热歌榜',
      subtitle: parts.isEmpty ? '版权音乐周榜，取当期榜单' : parts.join(' · '),
      trailing: TextButton.icon(
        onPressed: hot.songs.isEmpty
            ? null
            : () => unawaited(_playAllHotSongs(hot.songs)),
        icon: const Icon(Icons.play_arrow_rounded, size: BmTokens.icon),
        label: const Text('播放全部'),
      ),
    );

    if (hot.songs.isEmpty) {
      return [
        _pad(side, SliverToBoxAdapter(child: header)),
        _pad(
          side,
          SliverToBoxAdapter(
            child: _SectionPlaceholder(
              isLoading: hot.isLoading,
              errorMessage: hot.errorMessage,
              emptyText: '热歌榜暂时没有内容',
              onRetry: () =>
                  unawaited(ref.read(hotSongsProvider.notifier).refresh()),
            ),
          ),
        ),
      ];
    }

    if (wide) {
      return [
        _pad(side, SliverToBoxAdapter(child: header)),
        _pad(
          side,
          SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: BmTokens.s3,
              crossAxisSpacing: BmTokens.s3,
              mainAxisExtent: hotExtent,
            ),
            itemCount: hot.songs.length,
            itemBuilder: (context, index) {
              final song = hot.songs[index];
              return HotSongCard(
                song: song,
                onTap: () => _playHotSong(song),
                contextMenuBuilder: _musicContextMenu(song.toMusic()),
              );
            },
          ),
        ),
      ];
    }

    return [
      _pad(side, SliverToBoxAdapter(child: header)),
      _pad(
        side,
        SliverList.builder(
          itemCount: hot.songs.length,
          itemBuilder: (context, index) {
            final song = hot.songs[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: BmTokens.s2),
              child: HotSongCard(
                song: song,
                onTap: () => _playHotSong(song),
                contextMenuBuilder: _musicContextMenu(song.toMusic()),
              ),
            );
          },
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- 音乐区排行

  List<Widget> _buildRankSection(
    BuildContext context,
    MusicRankState rank, {
    required double side,
    required bool wide,
    required int columns,
    required double cardExtent,
  }) {
    final subtitle = rank.note.trim().isNotEmpty ? rank.note : '音乐区稿件综合热度，动态更新';

    final header = _buildSectionHeader(
      context,
      title: '音乐区排行',
      subtitle: rank.fromCache && !rank.isEmpty ? '$subtitle · 缓存' : subtitle,
      trailing: rank.items.length > _rankPreviewCount
          ? TextButton(
              onPressed: () => setState(() => _rankExpanded = !_rankExpanded),
              child: Text(_rankExpanded ? '收起' : '展开全部'),
            )
          : null,
    );

    if (rank.items.isEmpty) {
      return [
        _pad(side, SliverToBoxAdapter(child: header)),
        _pad(
          side,
          SliverToBoxAdapter(
            child: _SectionPlaceholder(
              isLoading: rank.isLoading,
              errorMessage: rank.errorMessage,
              emptyText: '排行榜暂时没有内容',
              onRetry: () =>
                  unawaited(ref.read(musicRankProvider.notifier).refresh()),
            ),
          ),
        ),
      ];
    }

    final items = _rankExpanded
        ? rank.items
        : rank.items.take(_rankPreviewCount).toList();

    if (wide) {
      return [
        _pad(side, SliverToBoxAdapter(child: header)),
        _pad(
          side,
          SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: BmTokens.s3,
              crossAxisSpacing: BmTokens.s3,
              mainAxisExtent: cardExtent,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final music = items[index];
              return DiscoverMusicCard(
                rank: index + 1,
                title: music.title,
                subtitle: music.subtitleText,
                coverUrl: music.safeCoverUrl,
                cacheKey: music.id,
                onTap: () => _playMusic(music),
                contextMenuBuilder: _musicContextMenu(music),
                trailing: _buildDuration(context, music),
              );
            },
          ),
        ),
      ];
    }

    return [
      _pad(side, SliverToBoxAdapter(child: header)),
      _pad(
        side,
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final music = items[index];
            return DiscoverMusicTile(
              rank: index + 1,
              title: music.title,
              subtitle: music.subtitleText,
              coverUrl: music.safeCoverUrl,
              cacheKey: music.id,
              onTap: () => _playMusic(music),
              contextMenuBuilder: _musicContextMenu(music),
              trailing: _buildDuration(context, music),
            );
          },
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- 推荐流

  List<Widget> _buildFeedSection(
    BuildContext context,
    DiscoverFeedState feed, {
    required double side,
    required bool wide,
    required int columns,
    required double cardExtent,
  }) {
    final parts = <String>['音乐区推荐'];
    if (feed.page > 1) parts.add('第 ${feed.page} 批');
    if (feed.fromCache && !feed.isEmpty) parts.add('缓存');

    final header = _buildSectionHeader(
      context,
      title: '发现音乐',
      subtitle: parts.join(' · '),
      trailing: TextButton.icon(
        onPressed: feed.isLoading ? null : () => unawaited(_nextBatch()),
        icon: feed.isLoading
            ? SizedBox(
                width: BmTokens.s4,
                height: BmTokens.s4,
                child: CircularProgressIndicator(strokeWidth: BmTokens.s1 / 2),
              )
            : const Icon(Icons.autorenew_rounded, size: BmTokens.iconMenu),
        label: const Text('换一批'),
      ),
    );

    if (feed.items.isEmpty) {
      return [
        _pad(side, SliverToBoxAdapter(child: header)),
        _pad(
          side,
          SliverToBoxAdapter(
            child: _SectionPlaceholder(
              isLoading: feed.isLoading,
              errorMessage: feed.errorMessage,
              emptyText: '暂时没有推荐内容',
              onRetry: () =>
                  unawaited(ref.read(discoverFeedProvider.notifier).refresh()),
            ),
          ),
        ),
      ];
    }

    if (wide) {
      return [
        _pad(side, SliverToBoxAdapter(child: header)),
        _pad(
          side,
          SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: BmTokens.s3,
              crossAxisSpacing: BmTokens.s3,
              mainAxisExtent: cardExtent,
            ),
            itemCount: feed.items.length,
            itemBuilder: (context, index) {
              final music = feed.items[index];
              return DiscoverMusicCard(
                title: music.title,
                // 推荐流条目没有分区名（album 会兜成「未知专辑」），只显示作者
                subtitle: music.artist.displayName,
                coverUrl: music.safeCoverUrl,
                cacheKey: music.id,
                onTap: () => _playMusic(music),
                contextMenuBuilder: _musicContextMenu(music),
                trailing: _buildDuration(context, music),
              );
            },
          ),
        ),
      ];
    }

    return [
      _pad(side, SliverToBoxAdapter(child: header)),
      _pad(
        side,
        SliverList.builder(
          itemCount: feed.items.length,
          itemBuilder: (context, index) {
            final music = feed.items[index];
            return DiscoverMusicTile(
              title: music.title,
              // 推荐流条目没有分区名（album 会兜成「未知专辑」），只显示作者
              subtitle: music.artist.displayName,
              coverUrl: music.safeCoverUrl,
              cacheKey: music.id,
              onTap: () => _playMusic(music),
              contextMenuBuilder: _musicContextMenu(music),
              trailing: _buildDuration(context, music),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildDuration(BuildContext context, Music music) {
    final duration = music.duration;
    if (duration == null) return const SizedBox.shrink();
    return Text(
      formatDuration(duration),
      style: context.bmType.micro.copyWith(
        color: context.bmColors.textTertiary,
      ),
    );
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}

/// 分区占位：加载中 / 出错（带重试）/ 空。
class _SectionPlaceholder extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final String emptyText;
  final VoidCallback onRetry;

  const _SectionPlaceholder({
    required this.isLoading,
    required this.errorMessage,
    required this.emptyText,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: BmTokens.s4),
        child: BmSkeleton.list(count: 3),
      );
    }

    final error = errorMessage;
    if (error != null) {
      return BmEmptyState(
        compact: true,
        icon: Icons.cloud_off_rounded,
        title: error,
        action: TextButton(onPressed: onRetry, child: const Text('重试')),
      );
    }

    return BmEmptyState(
      compact: true,
      icon: Icons.music_off_rounded,
      title: emptyText,
    );
  }
}
