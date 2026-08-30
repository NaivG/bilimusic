import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/landscape/background.dart';
import 'package:bilimusic/components/common/album_section.dart';
import 'package:bilimusic/components/lyric/lyric_section.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';
import 'package:bilimusic/providers/lyrics_providers.dart';
import 'package:bilimusic/providers/navigation_providers.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';

/// 横屏详情页主容器
/// Apple Music 风格的左右分栏布局
class LandscapeDetailPage extends ConsumerStatefulWidget {
  const LandscapeDetailPage({super.key});

  @override
  ConsumerState<LandscapeDetailPage> createState() =>
      _LandscapeDetailPageState();
}

class _LandscapeDetailPageState extends ConsumerState<LandscapeDetailPage>
    with TickerProviderStateMixin {
  late model.Music _music;
  String? _previousMusicId;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isFavorite = false;

  // 背景颜色
  Color? _dominantColor;
  Color? _previousDominantColor;

  // 歌词渲染
  final LyricController _lyricController = LyricController();
  LyricModel? _lastAppliedModel;

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
    _isFavorite = coordinator.isFavorite(_music);

    _extractBackgroundColor(_music.coverUrl);
    _lyricController.loadLyricModel(_placeholderModel(_music.title));
  }

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
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
      _isFavorite = commands.isFavorite(_music);
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

  void _loadLyric(String id) {
    ref.read(selectedLyricSourceProvider.notifier).state = id;
  }

  @override
  Widget build(BuildContext context) {
    final leftRatio = LandscapeBreakpoints.getLeftSectionRatio(context);

    ref.watch(currentIndexProvider);
    final position = ref.watch(positionProvider);
    final ps = ref.watch(playerStateProvider);
    final mode = ref.watch(playModeProvider);

    final coordinator = ref.read(playerCoordinatorProvider);
    final liveMusic = coordinator.currentMusic;
    final musicChanged = liveMusic != null && liveMusic.id != _previousMusicId;
    if (musicChanged) {
      _previousMusicId = liveMusic.id;
      _previousDominantColor = _dominantColor;
      _music = liveMusic;
      _duration = liveMusic.duration;
      _isFavorite = ref
          .read(playbackCommandsProvider.notifier)
          .isFavorite(_music);
      _lastAppliedModel = null;
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
    final selectedOverride = ref.watch(selectedLyricSourceProvider);
    final selectedId = selectedOverride ?? lyricsAsync.value?.sourceId;
    final isLoading =
        lyricsAsync.isLoading || (sources.isEmpty && lyricsAsync.isLoading);

    final payload = lyricsAsync.value;
    if (payload != null && payload.mainModel != _lastAppliedModel) {
      _lastAppliedModel = payload.mainModel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lyricController.loadLyricModel(payload.mainModel);
        _lyricController.setProgress(_position);
      });
    }

    final isPlaying = ps is PlayerPlaying;
    final icon = switch (mode) {
      PlayMode.sequential => Icons.repeat,
      PlayMode.loop => Icons.repeat_one,
      PlayMode.shuffle => Icons.shuffle,
    };

    return _buildScaffold(
      context,
      leftRatio,
      isPlaying,
      icon,
      sources,
      selectedId,
      isLoading,
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    double leftRatio,
    bool isPlaying,
    IconData icon,
    List<dynamic> sources,
    String? selectedId,
    bool isLoading,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          AnimatedLandscapeBackground(
            coverUrl: _music.coverUrl,
            previousColor: _previousDominantColor,
            newColor: _dominantColor,
            child: const SizedBox.expand(),
          ),
          Column(
            children: [
              _buildAppBar(context),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width * leftRatio,
                      child: AlbumSection(
                        coverUrl: _music.coverUrl,
                        title: _music.title,
                        artist: _music.artist,
                        album: _music.album,
                        dominantColor: _dominantColor,
                        isFavorite: _isFavorite,
                        trackId: _music.id,
                        onFavoritePressed: _toggleFavorite,
                        onSharePressed: _shareMusic,
                        isPlaying: isPlaying,
                        playModeIcon: icon,
                        onPlayPause: _togglePlay,
                        onPrevious: () => ref
                            .read(playbackCommandsProvider.notifier)
                            .playPrevious(),
                        onNext: () => ref
                            .read(playbackCommandsProvider.notifier)
                            .playNext(),
                        onPlayModeToggle: () => ref
                            .read(playbackCommandsProvider.notifier)
                            .togglePlayMode(),
                        onPlaylist: _showPlaylist,
                      ),
                    ),
                    Expanded(
                      child: LyricSection(
                        title: _music.title,
                        artist: _music.artist,
                        album: _music.album,
                        lyricController: _lyricController,
                        position: _position,
                        lyricSources: sources.cast(),
                        selectedLyricId: selectedId,
                        isLoadingLyrics: isLoading,
                        showHeader: false,
                        onLyricSourceChanged: _loadLyric,
                        onLyricTap: (duration) {
                          ref
                              .read(playbackCommandsProvider.notifier)
                              .seek(duration);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              onPressed: () =>
                  ref.read(shellNavigationProvider.notifier).maybePop(context),
            ),
            const Spacer(),
            Text(
              '正在播放',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.more_horiz,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => _showOptionsSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : Colors.white,
              ),
              title: Text(
                _isFavorite ? '取消收藏' : '收藏',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _toggleFavorite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('分享', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _shareMusic();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showSongInfo();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSongInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('标题', _music.title),
            _infoRow('艺术家', _music.artist),
            _infoRow('专辑', _music.album),
            _infoRow('时长', _formatDuration(_duration ?? Duration.zero)),
            _infoRow('来源', 'Bilibili'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
