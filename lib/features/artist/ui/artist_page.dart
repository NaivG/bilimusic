import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/features/artist/artist_service.dart';
import 'package:bilimusic/features/artist/widgets/artist_header.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_song_list.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 歌手页（UP 页）：页头 + TA 的投稿列表。
///
/// 列表滚到底自动续下一页；「播放全部 / 随机播放」另外按上限攒一份队列。
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({super.key, required this.up});

  final UpProfile up;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  /// 距底部多远开始预取下一页（列表滚动时触发）。
  static const double _loadMoreThreshold = 400;

  final ScrollController _scrollController = ScrollController();
  final List<Music> _songs = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _total = 0;
  int _page = 0;

  /// 正在攒队列（播放全部 / 随机播放）
  bool _isCollecting = false;

  /// 攒队列的进度文案（如「已取 30 / 218 首」）
  String? _collectHint;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant ArtistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // shell 对同一页面给的 key 不变，换 UP 主时 State 会被复用：整份重来，别串数据
    if (oldWidget.up.mid != widget.up.mid) _refresh();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  ArtistService get _service => ref.read(artistServiceProvider);

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() => _isLoading = true);

    final result = await _service.fetchSubmissionsPage(
      mid: widget.up.mid,
      upName: widget.up.displayName,
    );
    if (!mounted) return;

    setState(() {
      _songs
        ..clear()
        ..addAll(result.songs);
      _total = result.total;
      _page = 1;
      // 不满一页就是最后一面；接口在「翻到底」时回的是空页，同样是 false。
      _hasMore = result.songs.length >= ArtistService.submissionPageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    final result = await _service.fetchSubmissionsPage(
      mid: widget.up.mid,
      upName: widget.up.displayName,
      page: _page + 1,
    );
    if (!mounted) return;

    setState(() {
      _songs.addAll(result.songs);
      // total 只在接口真给了数时覆盖：翻页失败回的 0 不该把表头的数字抹掉。
      if (result.total > 0) _total = result.total;
      _page += 1;
      _hasMore = result.songs.length >= ArtistService.submissionPageSize;
      _isLoadingMore = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _songs.clear();
      _hasMore = false;
      _page = 0;
      _total = 0;
    });
    await _loadFirstPage();
  }

  /// 攒一份整队列播放的曲目表；攒的过程中顶部显示进度，失败返回 null。
  Future<List<Music>?> _collect() async {
    if (_isCollecting) return null;

    setState(() {
      _isCollecting = true;
      _collectHint = '正在整理投稿…';
    });

    try {
      return await _service.collectSubmissions(
        mid: widget.up.mid,
        upName: widget.up.displayName,
        onProgress: (loaded, total) {
          if (!mounted) return;
          setState(() {
            _collectHint = total > 0 ? '已取 $loaded / $total 首' : '已取 $loaded 首';
          });
        },
      );
    } catch (e) {
      debugPrint('[ArtistPage] 加载投稿失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载投稿失败：$e')));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isCollecting = false;
          _collectHint = null;
        });
      }
    }
  }

  /// 播放全部 / 随机播放：都是先攒队列再整份替换播放列表。
  Future<void> _playCollected({required bool shuffle}) async {
    final collected = await _collect();
    if (!mounted || collected == null) return;

    if (collected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有取到投稿：可能撞上风控，或 TA 还没有可播的稿件')),
      );
      return;
    }

    final songs = shuffle
        ? (List<Music>.from(collected)..shuffle(Random()))
        : collected;

    // 两个命令 notifier 在第一个 await 之前取出来：页面中途被 pop 掉也不会用到已释放的 ref
    final playback = ref.read(playbackCommandsProvider.notifier);
    final playlist = ref.read(playlistCommandsProvider.notifier);

    await playback.clearPlaylist();
    await playlist.addAllToPlaylist(songs);
    await playback.playMusic(songs.first);
  }

  Future<void> _playSong(Music music) async {
    await ref.read(playlistCommandsProvider.notifier).addToPlaylist(music);
    await ref.read(playbackCommandsProvider.notifier).playMusic(music);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            if (_isCollecting) _buildCollectBanner(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// 攒队列期间的顶部进度条：要翻好几页投稿，没有反馈会让人以为点了没反应。
  Widget _buildCollectBanner() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _collectHint ?? '正在整理投稿…',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isLandscape = LandscapeBreakpoints.isLandscapeMode(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: ArtistHeader(
              up: widget.up,
              submissionCount: _total > 0 ? _total : _songs.length,
              isBusy: _isCollecting,
              onPlayAll: () => _playCollected(shuffle: false),
              onShufflePlay: () => _playCollected(shuffle: true),
            ),
          ),
          SliverToBoxAdapter(
            child: Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outline,
              indent: 24,
              endIndent: 24,
            ),
          ),
          if (_songs.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
          else ...[
            PlaylistSongList(
              songs: _songs,
              currentPlayingMusic: ref.watch(currentMusicProvider),
              onSongTap: _playSong,
              isLandscape: isLandscape,
            ),
            if (_hasMore) SliverToBoxAdapter(child: _buildFooter()),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '没有取到投稿',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '可能撞上风控，或 TA 还没有可播的稿件',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                '上滑加载更多',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}
