import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/providers/lyrics_providers.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/services/lyrics_service.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/pages/detail/portrait_detail_page.dart';
import 'package:bilimusic/pages/detail/landscape_detail_page.dart';
import 'package:bilimusic/pages/detail/square_detail_page.dart';

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

  // 歌词渲染状态 (来自 LyricsService,本地只做驱动)
  final LyricController _lyricController = LyricController();
  bool _showLyrics = false;

  // 背景颜色
  Color? _dominantColor;

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    final currentMusic =
        ref.read(playerCoordinatorProvider).currentMusic ??
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
    final commands = ref.read(playbackCommandsProvider.notifier);
    if (commands.isFavorite(_music)) {
      await commands.removeFromFavorites(_music);
    } else {
      await commands.addToFavorites(_music);
    }
    setState(() {
      _music = _music.copyWith(isFavorite: !commands.isFavorite(_music));
    });
  }

  void _shareMusic() {
    final String shareText =
        '由 BiliMusic 分享：${_music.title}\n'
        'https://b23.tv/${_music.id}';
    SharePlus.instance.share(
      ShareParams(
        text: shareText,
        sharePositionOrigin: Rect.fromCenter(
          center: Offset.zero,
          width: 100,
          height: 100,
        ),
      ),
    );
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
    // 切源 —— 由 currentMusicLyricsProvider 监听 selectedLyricSourceProvider 自动重取
    ref.read(selectedLyricSourceProvider.notifier).state = id;
  }

  /// 根据当前 music + lyrics 状态推导出 (sources, selected, loading)。
  ({List<LyricSource> sources, String? selected, bool loading}) _resolveLyrics(
    AsyncValue<LyricsPayload?> lyricsAsync,
    List<LyricSource> sources,
  ) {
    final selected = ref.watch(selectedLyricSourceProvider);
    return (
      sources: sources,
      selected: selected ?? lyricsAsync.value?.sourceId,
      loading:
          lyricsAsync.isLoading || (sources.isEmpty && lyricsAsync.isLoading),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = LandscapeBreakpoints.isLandscapeMode(context);
    if (isLandscape) {
      return const LandscapeDetailPage();
    }

    ref.watch(currentIndexProvider);
    final position = ref.watch(positionProvider);
    final ps = ref.watch(playerStateProvider);
    final mode = ref.watch(playModeProvider);

    final liveMusic = ref.read(playerCoordinatorProvider).currentMusic;
    final musicChanged = liveMusic != null && liveMusic.id != _music.id;
    if (musicChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _updateBackgroundColor(liveMusic.coverUrl);
      });
      _music = liveMusic;
      _duration = liveMusic.duration;
      _lastAppliedModel = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lyricController.loadLyricModel(_placeholderModel(_music.title));
        _lyricController.setProgress(Duration.zero);
      });
    }

    _position = position;

    final lyricsAsync = ref.watch(currentMusicLyricsProvider);
    final sources = ref.watch(currentMusicLyricSourcesProvider);
    final resolved = _resolveLyrics(lyricsAsync, sources);
    final payload = lyricsAsync.value;

    // 应用最新 payload 到 lyricController
    if (payload != null && payload.mainModel != _lastAppliedModel) {
      _lastAppliedModel = payload.mainModel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lyricController.loadLyricModel(payload.mainModel);
        _lyricController.setProgress(_position);
      });
    }

    final isPlaying = ps is PlayerPlaying;
    final fading = ps is PlayerPlaying && ps.fadeCountdown != null;
    final icon = switch (mode) {
      PlayMode.sequential => Icons.repeat,
      PlayMode.loop => Icons.repeat_one,
      PlayMode.shuffle => Icons.shuffle,
    };

    final isSquare = SquareBreakpoints.shouldUseSquareLayout(context);
    void togglePlayMode() =>
        ref.read(playbackCommandsProvider.notifier).togglePlayMode();

    if (isSquare) {
      return SquareDetailPage(
        music: _music,
        position: _position,
        duration: _duration,
        isPlaying: isPlaying,
        showLyrics: _showLyrics,
        lyricSources: resolved.sources,
        selectedLyricId: resolved.selected,
        lyricController: _lyricController,
        isLoadingLyrics: resolved.loading,
        dominantColor: _dominantColor,
        playModeIcon: icon,
        isTransitioning: fading,
        onToggleFavorite: _toggleFavorite,
        onShare: _shareMusic,
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
      showLyrics: _showLyrics,
      lyricSources: resolved.sources,
      selectedLyricId: resolved.selected,
      lyricController: _lyricController,
      isLoadingLyrics: resolved.loading,
      dominantColor: _dominantColor,
      playModeIcon: icon,
      isTransitioning: fading,
      onToggleFavorite: _toggleFavorite,
      onShare: _shareMusic,
      onTogglePlay: _togglePlay,
      onToggleShowLyrics: _toggleShowLyrics,
      onPlaylist: _showPlaylist,
      onLoadLyric: _loadLyric,
      onSeek: _seek,
      onTogglePlayMode: togglePlayMode,
    );
  }

  LyricModel? _lastAppliedModel;
}
