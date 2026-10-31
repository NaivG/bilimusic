import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/hot_song.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/discover/logic/discover_cache.dart';

/// 发现页三个分区共用的落盘缓存。
final discoverCacheProvider = Provider<DiscoverCache>((ref) => DiscoverCache());

/// 热歌榜（版权音乐榜当期）的展示状态。
class HotSongsState {
  final List<HotSong> songs;

  /// 当期榜单 id 与期数，用于页头「第 N 期」。
  final int listId;
  final int period;

  /// 该期发布时间。
  final DateTime? publishedAt;

  final bool isLoading;

  /// 当前展示的是磁盘缓存（页头据此提示「缓存」）。
  final bool fromCache;
  final String? errorMessage;

  /// 上次成功拿到数据的时间，缓存新旧判断都看它。
  final DateTime? updatedAt;

  const HotSongsState({
    this.songs = const [],
    this.listId = 0,
    this.period = 0,
    this.publishedAt,
    this.isLoading = false,
    this.fromCache = false,
    this.errorMessage,
    this.updatedAt,
  });

  bool get isEmpty => songs.isEmpty;

  HotSongsState copyWith({
    List<HotSong>? songs,
    int? listId,
    int? period,
    DateTime? publishedAt,
    bool? isLoading,
    bool? fromCache,
    String? errorMessage,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return HotSongsState(
      songs: songs ?? this.songs,
      listId: listId ?? this.listId,
      period: period ?? this.period,
      publishedAt: publishedAt ?? this.publishedAt,
      isLoading: isLoading ?? this.isLoading,
      fromCache: fromCache ?? this.fromCache,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 发现页 · 热歌榜。
///
/// 接口是两跳（取最新期 → 取当期歌曲），状态挂在这里而不是页面里：
/// 切 tab 回来不会重复拉；冷启动先铺缓存，过期才联网。
class HotSongsNotifier extends Notifier<HotSongsState> {
  /// 上次发起请求的时间（含失败），手动刷新按它节流。
  DateTime? _lastAttemptAt;

  @override
  HotSongsState build() => const HotSongsState();

  /// 页面打开时调用：新鲜就直接用，过期先铺缓存再拉一次。
  Future<void> ensureLoaded() async {
    if (state.isLoading) return;
    if (!state.isEmpty && isCacheFresh(state.updatedAt, hotSongsTtl)) return;

    if (state.isEmpty) {
      final cached = await ref.read(discoverCacheProvider).readHotSongs();
      if (!ref.mounted) return;
      if (cached != null && cached.songs.isNotEmpty) {
        state = state.copyWith(
          songs: cached.songs,
          listId: cached.listId,
          period: cached.period,
          publishedAt: cached.publishedAt,
          updatedAt: cached.fetchedAt,
          fromCache: true,
        );
        if (isCacheFresh(cached.fetchedAt, hotSongsTtl)) return;
      }
    }
    await _fetch();
  }

  /// 手动刷新；返回 false 表示刚拉过、这次被节流。
  Future<bool> refresh() async {
    if (state.isLoading) return false;
    final last = _lastAttemptAt;
    if (last != null &&
        DateTime.now().difference(last) < hotSongsMinRefreshInterval) {
      return false;
    }
    await _fetch();
    return true;
  }

  Future<void> _fetch() async {
    _lastAttemptAt = DateTime.now();
    state = state.copyWith(isLoading: true, clearError: true);

    final ({int listId, int period, DateTime? publishedAt, List<HotSong> songs})
    result;
    try {
      result = await ref.read(apiServiceProvider).fetchHotSongs();
    } catch (e) {
      if (!ref.mounted) return;
      debugPrint('[Discover] 热歌榜加载失败: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isEmpty ? '热歌榜暂时取不到数据' : '刷新失败，显示的是缓存内容',
      );
      return;
    }
    if (!ref.mounted) return;

    if (result.songs.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isEmpty ? '热歌榜暂时取不到数据' : '刷新失败，显示的是缓存内容',
      );
      return;
    }

    final now = DateTime.now();
    state = state.copyWith(
      songs: result.songs,
      listId: result.listId,
      period: result.period,
      publishedAt: result.publishedAt,
      updatedAt: now,
      fromCache: false,
      isLoading: false,
    );
    try {
      await ref
          .read(discoverCacheProvider)
          .writeHotSongs(
            HotSongsCache(
              songs: result.songs,
              fetchedAt: now,
              listId: result.listId,
              period: result.period,
              publishedAt: result.publishedAt,
            ),
          );
    } catch (e) {
      debugPrint('[Discover] 热歌榜缓存写入失败: $e');
    }
  }
}

final hotSongsProvider = NotifierProvider<HotSongsNotifier, HotSongsState>(
  HotSongsNotifier.new,
);

/// 音乐区排行的展示状态。
class MusicRankState {
  final List<Music> items;

  /// 接口给的榜单说明（「根据稿件内容质量…动态更新」）。
  final String note;
  final bool isLoading;
  final bool fromCache;
  final String? errorMessage;
  final DateTime? updatedAt;

  const MusicRankState({
    this.items = const [],
    this.note = '',
    this.isLoading = false,
    this.fromCache = false,
    this.errorMessage,
    this.updatedAt,
  });

  bool get isEmpty => items.isEmpty;

  MusicRankState copyWith({
    List<Music>? items,
    String? note,
    bool? isLoading,
    bool? fromCache,
    String? errorMessage,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return MusicRankState(
      items: items ?? this.items,
      note: note ?? this.note,
      isLoading: isLoading ?? this.isLoading,
      fromCache: fromCache ?? this.fromCache,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 发现页 · 音乐区排行（一次约 150 KB，必须走缓存）。
class MusicRankNotifier extends Notifier<MusicRankState> {
  DateTime? _lastAttemptAt;

  @override
  MusicRankState build() => const MusicRankState();

  Future<void> ensureLoaded() async {
    if (state.isLoading) return;
    if (!state.isEmpty && isCacheFresh(state.updatedAt, musicRankTtl)) return;

    if (state.isEmpty) {
      final cached = await ref.read(discoverCacheProvider).readMusicRank();
      if (!ref.mounted) return;
      if (cached != null && cached.items.isNotEmpty) {
        state = state.copyWith(
          items: cached.items,
          note: cached.note,
          updatedAt: cached.fetchedAt,
          fromCache: true,
        );
        if (isCacheFresh(cached.fetchedAt, musicRankTtl)) return;
      }
    }
    await _fetch();
  }

  Future<bool> refresh() async {
    if (state.isLoading) return false;
    final last = _lastAttemptAt;
    if (last != null &&
        DateTime.now().difference(last) < musicRankMinRefreshInterval) {
      return false;
    }
    await _fetch();
    return true;
  }

  Future<void> _fetch() async {
    _lastAttemptAt = DateTime.now();
    state = state.copyWith(isLoading: true, clearError: true);

    final ({String note, List<Music> items}) result;
    try {
      result = await ref.read(apiServiceProvider).fetchMusicRanking();
    } catch (e) {
      if (!ref.mounted) return;
      debugPrint('[Discover] 排行榜加载失败: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isEmpty ? '排行榜暂时取不到数据' : '刷新失败，显示的是缓存内容',
      );
      return;
    }
    if (!ref.mounted) return;

    if (result.items.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isEmpty ? '排行榜暂时取不到数据' : '刷新失败，显示的是缓存内容',
      );
      return;
    }

    final now = DateTime.now();
    state = state.copyWith(
      items: result.items,
      note: result.note,
      updatedAt: now,
      fromCache: false,
      isLoading: false,
    );
    try {
      await ref
          .read(discoverCacheProvider)
          .writeMusicRank(
            MusicRankCache(
              items: result.items,
              fetchedAt: now,
              note: result.note,
            ),
          );
    } catch (e) {
      debugPrint('[Discover] 排行榜缓存写入失败: $e');
    }
  }
}

final musicRankProvider = NotifierProvider<MusicRankNotifier, MusicRankState>(
  MusicRankNotifier.new,
);

/// 发现流（音乐区推荐流）的展示状态。
class DiscoverFeedState {
  final List<Music> items;

  /// 当前展示的是第几页（`display_id`，从 1 开始）。
  final int page;
  final bool isLoading;
  final bool fromCache;
  final String? errorMessage;
  final DateTime? updatedAt;

  const DiscoverFeedState({
    this.items = const [],
    this.page = 1,
    this.isLoading = false,
    this.fromCache = false,
    this.errorMessage,
    this.updatedAt,
  });

  bool get isEmpty => items.isEmpty;

  DiscoverFeedState copyWith({
    List<Music>? items,
    int? page,
    bool? isLoading,
    bool? fromCache,
    String? errorMessage,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return DiscoverFeedState(
      items: items ?? this.items,
      page: page ?? this.page,
      isLoading: isLoading ?? this.isLoading,
      fromCache: fromCache ?? this.fromCache,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 发现页 · 音乐区推荐流。
class DiscoverFeedNotifier extends Notifier<DiscoverFeedState> {
  DateTime? _lastAttemptAt;

  @override
  DiscoverFeedState build() => const DiscoverFeedState();

  Future<void> ensureLoaded() async {
    if (state.isLoading) return;
    if (!state.isEmpty && isCacheFresh(state.updatedAt, musicFeedTtl)) return;

    if (state.isEmpty) {
      final cached = await ref.read(discoverCacheProvider).readMusicFeed();
      if (!ref.mounted) return;
      if (cached != null && cached.items.isNotEmpty) {
        state = state.copyWith(
          items: cached.items,
          page: cached.page,
          updatedAt: cached.fetchedAt,
          fromCache: true,
        );
        if (isCacheFresh(cached.fetchedAt, musicFeedTtl)) return;
      }
    }
    await _fetchPage(state.page <= 0 ? 1 : state.page);
  }

  /// 下拉刷新：重取当前页。返回 false 表示被节流。
  Future<bool> refresh() async {
    if (state.isLoading) return false;
    final last = _lastAttemptAt;
    if (last != null &&
        DateTime.now().difference(last) < musicFeedMinRefreshInterval) {
      return false;
    }
    await _fetchPage(state.page <= 0 ? 1 : state.page);
    return true;
  }

  /// 「换一批」：翻到下一批；翻到头就回到第 1 页。
  Future<void> nextBatch() async {
    if (state.isLoading) return;
    if (state.isEmpty) {
      await ensureLoaded();
      return;
    }

    final requested = (state.page <= 0 ? 1 : state.page) + 1;
    _lastAttemptAt = DateTime.now();
    state = state.copyWith(isLoading: true, clearError: true);

    final api = ref.read(apiServiceProvider);
    try {
      var page = requested;
      var items = await api.fetchMusicRegionFeed(page: page);
      if (!ref.mounted) return;

      if (items.isEmpty) {
        // 接口只保证前几页互不重复，翻过头就当一轮结束，回到第 1 页
        page = 1;
        items = await api.fetchMusicRegionFeed(page: page);
        if (!ref.mounted) return;
      }

      if (items.isEmpty) {
        state = state.copyWith(isLoading: false, errorMessage: '暂时没有更多内容，稍后再试');
        return;
      }
      await _commit(items, page);
    } catch (e) {
      if (!ref.mounted) return;
      debugPrint('[Discover] 换一批失败: $e');
      state = state.copyWith(isLoading: false, errorMessage: '换一批失败，请稍后重试');
    }
  }

  Future<void> _fetchPage(int page) async {
    _lastAttemptAt = DateTime.now();
    state = state.copyWith(isLoading: true, clearError: true);

    final List<Music> items;
    try {
      items = await ref
          .read(apiServiceProvider)
          .fetchMusicRegionFeed(page: page);
    } catch (e) {
      if (!ref.mounted) return;
      debugPrint('[Discover] 推荐流加载失败: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isEmpty ? '暂时取不到推荐内容' : '刷新失败，显示的是缓存内容',
      );
      return;
    }
    if (!ref.mounted) return;

    if (items.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: state.isEmpty ? '暂时取不到推荐内容' : '刷新失败，显示的是缓存内容',
      );
      return;
    }
    await _commit(items, page);
  }

  /// 数据落地：写状态 + 写缓存（缓存写失败不影响展示）。
  Future<void> _commit(List<Music> items, int page) async {
    final now = DateTime.now();
    state = state.copyWith(
      items: items,
      page: page,
      updatedAt: now,
      fromCache: false,
      isLoading: false,
    );
    try {
      await ref
          .read(discoverCacheProvider)
          .writeMusicFeed(
            MusicFeedCache(items: items, fetchedAt: now, page: page),
          );
    } catch (e) {
      debugPrint('[Discover] 推荐流缓存写入失败: $e');
    }
  }
}

final discoverFeedProvider =
    NotifierProvider<DiscoverFeedNotifier, DiscoverFeedState>(
      DiscoverFeedNotifier.new,
    );
