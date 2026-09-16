import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/features/playlist/widgets/playlist_sheet.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart' as model;
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/lyrics/lyrics_providers.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/lyrics/lyrics_service.dart';
import 'package:bilimusic/features/player/now_playing/color_extractor.dart';
import 'package:bilimusic/shared/utils/play_mode_icon.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/shared/utils/share_helpers.dart';
import 'package:bilimusic/features/player/now_playing/portrait_detail_page.dart';
import 'package:bilimusic/features/player/now_playing/landscape_detail_page.dart';
import 'package:bilimusic/features/player/now_playing/square_detail_page.dart';

/// 详情页面
/// 根据屏幕方向路由到竖屏或横屏布局
class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late model.Music _music;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isFavorite = false;

  // 歌词渲染状态 (来自 LyricsService,本地只做驱动)
  final LyricController _lyricController = LyricController();
  bool _showLyrics = false;

  // 背景颜色
  Color? _dominantColor;

  // 上一首主导色 —— 横屏 AnimatedLandscapeBackground 切换渐变用
  Color? _previousDominantColor;

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    final coordinator = ref.read(playerCoordinatorProvider);
    final currentMusic =
        coordinator.currentMusic ??
        model.Music(
          id: '',
          title: '未知标题',
          artist: '未知艺术家',
          album: '未知专辑',
          coverUrl: '',
          duration: Duration.zero,
          audioUrl: '',
          pages: [],
        );
    _music = currentMusic;
    _duration = currentMusic.duration;
    _isFavorite = ref
        .read(playlistCommandsProvider.notifier)
        .isFavorite(_music);

    _extractBackgroundColor(_music.coverUrl);
    _lyricController.loadLyricModel(_placeholderModel(_music.title));
  }

  static LyricModel _placeholderModel(String title) {
    return LyricModel(
      tags: {'ti': title},
      lines: [
        LyricLine(
          start: Duration.zero,
          end: const Duration(seconds: 3),
          text: '暂无本地歌词',
        ),
        LyricLine(
          start: const Duration(seconds: 3),
          end: const Duration(seconds: 6),
          text: '请从歌词来源选择歌词',
        ),
      ],
    );
  }

  void _extractBackgroundColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    final color = await ColorExtractor.extractColorFromUrl(imageUrl);
    if (mounted && color != null) {
      setState(() {
        _dominantColor = color;
      });
    }
  }

  void _updateBackgroundColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    final color = await ColorExtractor.extractColorFromUrl(imageUrl);
    if (mounted && color != null) {
      setState(() {
        _dominantColor = color;
      });
    }
  }

  void _toggleFavorite() async {
    final commands = ref.read(playlistCommandsProvider.notifier);
    if (commands.isFavorite(_music)) {
      await commands.removeFromFavorites(_music);
    } else {
      await commands.addToFavorites(_music);
    }
    if (!mounted) return;
    setState(() {
      _isFavorite = commands.isFavorite(_music);
    });
  }

  void _togglePlay() {
    final commands = ref.read(playbackCommandsProvider.notifier);
    final ps = ref.read(playerStateProvider);
    if (ps is PlayerPlaying) {
      commands.pause();
    } else if (ps is PlayerPaused || ps is PlayerCompleted) {
      commands.resume();
    }
  }

  void _toggleShowLyrics() {
    setState(() => _showLyrics = !_showLyrics);
  }

  void _showPlaylist() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PlaylistSheet(
        onTrackSelect: (index) {
          ref.read(playbackCommandsProvider.notifier).playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _seek(Duration duration) {
    ref.read(playbackCommandsProvider.notifier).seek(duration);
  }

  void _loadLyric(String id) {
    // 切源 —— 由 currentMusicLyricsProvider 监听选择自动重取。
    // 选择绑定到「选中它的那首曲子」：切歌后自动失效，不会漏到下一首。
    final music = ref.read(playerCoordinatorProvider).currentMusic ?? _music;
    ref.read(selectedLyricSourceProvider.notifier).select(music, id);
  }

  /// 根据当前 music + lyrics 状态推导出 (sources, selected, loading)。
  ({List<LyricSource> sources, String? selected, bool loading}) _resolveLyrics(
    AsyncValue<LyricsPayload?> lyricsAsync,
    List<LyricSource> sources,
  ) {
    // 手动来源要按曲目过滤（属于上一首的会被当作没选），载荷自带的 sourceId
    // 是自动选源的结果，作为兜底。
    final selected = ref.watch(currentMusicSelectedLyricSourceProvider);
    return (
      sources: sources,
      selected: selected ?? lyricsAsync.value?.sourceId,
      loading:
          lyricsAsync.isLoading || (sources.isEmpty && lyricsAsync.isLoading),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentIndexProvider);
    final position = ref.watch(positionProvider);
    final ps = ref.watch(playerStateProvider);
    final mode = ref.watch(playModeProvider);

    final liveMusic = ref.read(playerCoordinatorProvider).currentMusic;
    final musicChanged = liveMusic != null && liveMusic.id != _music.id;
    if (musicChanged) {
      _previousDominantColor = _dominantColor;
      _music = liveMusic;
      _duration = liveMusic.duration;
      _isFavorite = ref
          .read(playlistCommandsProvider.notifier)
          .isFavorite(liveMusic);
      _lastAppliedModel = null;
      _placeholderTitle = _music.title;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateBackgroundColor(liveMusic.coverUrl);
        _lyricController.loadLyricModel(_placeholderModel(_music.title));
        _lyricController.setProgress(Duration.zero);
      });
    }

    _position = position;

    final lyricsAsync = ref.watch(currentMusicLyricsProvider);
    final sources = ref.watch(currentMusicLyricSourcesProvider);
    final resolved = _resolveLyrics(lyricsAsync, sources);
    final payload = lyricsAsync.value;

    // 应用最新 payload 到 lyricController。
    //
    // 切歌瞬间 currentMusicLyricsProvider 正在 rebuild，Riverpod 的
    // AsyncValue.value 在 loading 期间返回上一首的旧载荷；且本帧注册的
    // post-frame 回调晚于 musicChanged 的占位词回调，不校验归属就会把
    // 上一首的歌词覆盖掉占位词。
    // 因此：loading 中不应用；payload 必须属于当前曲目（songKey 校验）。
    // 用 liveMusic 而非 _music 取 key：曲中 ensureCid 回填 cid 只改对象
    // 不改 id，_music 靠 id 比对感知不到，liveMusic 始终是最新队列条目。
    final liveMusicKey = liveMusic == null
        ? null
        : LyricsService.songKeyOf(liveMusic);
    final payloadApplies =
        payload != null &&
        liveMusicKey != null &&
        payload.songKey == liveMusicKey;

    if (!lyricsAsync.isLoading &&
        payloadApplies &&
        payload.mainModel != _lastAppliedModel) {
      _lastAppliedModel = payload.mainModel;
      _placeholderTitle = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lyricController.loadLyricModel(payload.mainModel);
        _lyricController.setProgress(_position);
      });
    } else if (!lyricsAsync.isLoading &&
        !payloadApplies &&
        _placeholderTitle != _music.title) {
      // 当前曲目确实没有能用的歌词（用户主动选「本地」，或候选来源都取不到）：
      // 换回占位词。不换的话 lyricController 会一直留着上一个模型。
      _lastAppliedModel = null;
      _placeholderTitle = _music.title;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lyricController.loadLyricModel(_placeholderModel(_music.title));
        _lyricController.setProgress(_position);
      });
    }

    final isPlaying = ps is PlayerPlaying;
    final icon = mode.icon;

    void togglePlayMode() =>
        ref.read(playbackCommandsProvider.notifier).togglePlayMode();

    if (LandscapeBreakpoints.isLandscapeMode(context)) {
      return LandscapeDetailPage(
        music: _music,
        position: _position,
        duration: _duration,
        isPlaying: isPlaying,
        isFavorite: _isFavorite,
        lyricSources: resolved.sources,
        selectedLyricId: resolved.selected,
        lyricController: _lyricController,
        isLoadingLyrics: resolved.loading,
        dominantColor: _dominantColor,
        previousDominantColor: _previousDominantColor,
        playModeIcon: icon,
        onToggleFavorite: _toggleFavorite,
        onShare: () => shareMusic(_music),
        onTogglePlay: _togglePlay,
        onPlaylist: _showPlaylist,
        onLoadLyric: _loadLyric,
        onSeek: _seek,
        onTogglePlayMode: togglePlayMode,
      );
    }

    final isSquare = SquareBreakpoints.shouldUseSquareLayout(context);

    if (isSquare) {
      return SquareDetailPage(
        music: _music,
        position: _position,
        duration: _duration,
        isPlaying: isPlaying,
        isFavorite: _isFavorite,
        showLyrics: _showLyrics,
        lyricSources: resolved.sources,
        selectedLyricId: resolved.selected,
        lyricController: _lyricController,
        isLoadingLyrics: resolved.loading,
        dominantColor: _dominantColor,
        playModeIcon: icon,
        onToggleFavorite: _toggleFavorite,
        onShare: () => shareMusic(_music),
        onTogglePlay: _togglePlay,
        onToggleShowLyrics: _toggleShowLyrics,
        onLoadLyric: _loadLyric,
        onSeek: _seek,
        onTogglePlayMode: togglePlayMode,
      );
    }

    return PortraitDetailPage(
      music: _music,
      position: _position,
      duration: _duration,
      isPlaying: isPlaying,
      isFavorite: _isFavorite,
      showLyrics: _showLyrics,
      lyricSources: resolved.sources,
      selectedLyricId: resolved.selected,
      lyricController: _lyricController,
      isLoadingLyrics: resolved.loading,
      dominantColor: _dominantColor,
      playModeIcon: icon,
      onToggleFavorite: _toggleFavorite,
      onShare: () => shareMusic(_music),
      onTogglePlay: _togglePlay,
      onToggleShowLyrics: _toggleShowLyrics,
      onPlaylist: _showPlaylist,
      onLoadLyric: _loadLyric,
      onSeek: _seek,
      onTogglePlayMode: togglePlayMode,
    );
  }

  LyricModel? _lastAppliedModel;

  /// 当前屏幕上是不是占位词（值为此占位词所属曲名）。
  ///
  /// 占位词每次调用都新建 LyricModel，不能像载荷那样靠对象比对去重：
  /// 位置每 tick 都会重建本 widget，没有这个标记就会每帧重载一次占位词。
  String? _placeholderTitle;
}
