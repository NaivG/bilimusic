import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/discover/discover_providers.dart';
import 'package:bilimusic/features/discover/widgets/discover_music_tile.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/theme/app_palette.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

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

  /// 内容区最大宽度，超出后左右留白居中（桌面端别铺满整屏）。
  static const double _maxContentWidth = 960;

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hot = ref.watch(hotSongsProvider);
    final rank = ref.watch(musicRankProvider);
    final feed = ref.watch(discoverFeedProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth > _maxContentWidth + 64
                ? (constraints.maxWidth - _maxContentWidth) / 2
                : 16.0;
            return RefreshIndicator(
              onRefresh: _refreshAll,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _pad(side, SliverToBoxAdapter(child: _buildHeader(context))),
                  _pad(
                    side,
                    SliverToBoxAdapter(child: _buildHotHeader(context, hot)),
                  ),
                  ..._buildHotRows(context, hot, side),
                  _pad(
                    side,
                    SliverToBoxAdapter(child: _buildRankHeader(context, rank)),
                  ),
                  ..._buildRankRows(context, rank, side),
                  _pad(
                    side,
                    SliverToBoxAdapter(child: _buildFeedHeader(context, feed)),
                  ),
                  ..._buildFeedRows(context, feed, side),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发现',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'B 站平台数据：热歌榜、音乐区排行与推荐流',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新全部',
            onPressed: _refreshingAll ? null : () => unawaited(_refreshAll()),
            icon: _refreshingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 22),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- 热歌榜

  Widget _buildHotHeader(BuildContext context, HotSongsState hot) {
    final parts = <String>[];
    if (hot.period > 0) parts.add('第 ${hot.period} 期');
    final publishedAt = hot.publishedAt;
    if (publishedAt != null) parts.add('${_formatDate(publishedAt)} 发布');
    if (hot.fromCache && !hot.isEmpty) parts.add('缓存');

    return _SectionHeader(
      title: '热歌榜',
      subtitle: parts.isEmpty ? '版权音乐周榜，取当期榜单' : parts.join(' · '),
      trailing: TextButton.icon(
        onPressed: hot.songs.isEmpty
            ? null
            : () => unawaited(_playAllHotSongs(hot.songs)),
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('播放全部'),
      ),
    );
  }

  List<Widget> _buildHotRows(
    BuildContext context,
    HotSongsState hot,
    double side,
  ) {
    if (hot.songs.isEmpty) {
      return [
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

    return [
      _pad(
        side,
        SliverList.builder(
          itemCount: hot.songs.length,
          itemBuilder: (context, index) {
            final song = hot.songs[index];
            return DiscoverMusicTile(
              rank: song.rank,
              title: song.title,
              subtitle: song.subtitleText,
              coverUrl: song.coverUrl,
              cacheKey: 'hot-${song.musicId}',
              enabled: song.isPlayable,
              onTap: () => _playHotSong(song),
              trailing: _buildHotTrailing(context, song),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildHotTrailing(BuildContext context, HotSong song) {
    final theme = Theme.of(context);
    final delta = song.rankDelta;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _formatHeat(song.heat),
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 2),
        if (delta == null)
          Text(
            'NEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          )
        else if (delta == 0)
          Text(
            '—',
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                size: 14,
                color: delta > 0 ? Colors.green : Colors.redAccent,
              ),
              Text(
                '${delta.abs()}',
                style: TextStyle(
                  fontSize: 10,
                  color: delta > 0 ? Colors.green : Colors.redAccent,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------- 音乐区排行

  Widget _buildRankHeader(BuildContext context, MusicRankState rank) {
    final subtitle = rank.note.trim().isNotEmpty ? rank.note : '音乐区稿件综合热度，动态更新';
    return _SectionHeader(
      title: '音乐区排行',
      subtitle: rank.fromCache && !rank.isEmpty ? '$subtitle · 缓存' : subtitle,
      trailing: rank.items.length > _rankPreviewCount
          ? TextButton(
              onPressed: () => setState(() => _rankExpanded = !_rankExpanded),
              child: Text(_rankExpanded ? '收起' : '展开全部'),
            )
          : null,
    );
  }

  List<Widget> _buildRankRows(
    BuildContext context,
    MusicRankState rank,
    double side,
  ) {
    if (rank.items.isEmpty) {
      return [
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
    return [
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
              trailing: _buildDuration(context, music),
            );
          },
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- 推荐流

  Widget _buildFeedHeader(BuildContext context, DiscoverFeedState feed) {
    final parts = <String>['音乐区推荐'];
    if (feed.page > 1) parts.add('第 ${feed.page} 批');
    if (feed.fromCache && !feed.isEmpty) parts.add('缓存');

    return _SectionHeader(
      title: '发现音乐',
      subtitle: parts.join(' · '),
      trailing: TextButton.icon(
        onPressed: feed.isLoading ? null : () => unawaited(_nextBatch()),
        icon: feed.isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.autorenew_rounded, size: 18),
        label: const Text('换一批'),
      ),
    );
  }

  List<Widget> _buildFeedRows(
    BuildContext context,
    DiscoverFeedState feed,
    double side,
  ) {
    if (feed.items.isEmpty) {
      return [
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

    return [
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
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).colorScheme.onSurfaceVariant
            .withValues(alpha: 0.6),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static String _formatHeat(int heat) {
    if (heat <= 0) return '';
    if (heat >= 10000) return '${(heat / 10000).toStringAsFixed(1)}万热度';
    return '$heat 热度';
  }
}

/// 分区标题：主题色竖条 + 标题 + 说明 + 右侧操作。
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    return Container(
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.appPalette.panelSurface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('加载中…', style: TextStyle(fontSize: 12, color: muted)),
              ],
            )
          : errorMessage != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  errorMessage!,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            )
          : Text(emptyText, style: TextStyle(fontSize: 12, color: muted)),
    );
  }
}
