import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'package:bilimusic/utils/netease_music_api.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/pages/detail/portrait_detail_page.dart';
import 'package:bilimusic/pages/detail/landscape_detail_page.dart';

/// 详情页面
/// 根据屏幕方向路由到竖屏或横屏布局
class DetailPage extends StatefulWidget {
  const DetailPage({super.key});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with TickerProviderStateMixin {
  late model.Music _music;
  Duration _position = Duration.zero;
  Duration? _duration;

  // 歌词相关变量
  List<LyricInfo> _lyricOptions = [];
  String? _selectedLyricId;
  LyricParser? _lyricParser;
  bool _isLoadingLyrics = false;
  bool _showLyrics = false;

  // 背景颜色相关变量
  Color? _dominantColor;
  Color? _vibrantColor;
  late AnimationController _colorAnimationController;

  @override
  void initState() {
    super.initState();

    _colorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // 初始化音乐信息
    final currentMusic =
        sl.playerManager.currentMusic ??
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

    // 提取初始背景颜色
    _extractBackgroundColor(_music.coverUrl);

    _initLyricOptions();
  }

  void _initLyricOptions() async {
    setState(() => _isLoadingLyrics = true);

    try {
      final localOption = LyricInfo(
        id: 'local',
        name: _music.title,
        artist: _music.artist,
      );
      final neteaseOptions = await NeteaseMusicApi.searchMusic(_music.title);

      if (mounted) {
        setState(() {
          _lyricOptions = [
            localOption,
            ...neteaseOptions.map(
              (info) =>
                  LyricInfo(id: info.id, name: info.name, artist: info.artist),
            ),
          ];
          _isLoadingLyrics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyricOptions = [
            LyricInfo(id: 'local', name: _music.title, artist: _music.artist),
          ];
          _isLoadingLyrics = false;
        });
      }
    }
  }

  void _loadLyric(String id) async {
    setState(() {
      _selectedLyricId = id;
      _lyricParser = null;
    });

    try {
      String? lyric;
      if (id == 'local') {
        lyric = '[00:00.00]暂无本地歌词\n[00:03.00]请从网易云音乐选择歌词';
      } else {
        lyric = await NeteaseMusicApi.getLyric(id);
      }

      if (mounted && lyric != null) {
        final parser = LyricParser.parse(lyric);
        if (mounted) {
          setState(() => _lyricParser = parser);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lyricParser = LyricParser.parse('[00:00.00]加载歌词失败'));
      }
    }
  }

  void _extractBackgroundColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    final color = await ColorExtractor.extractColorFromUrl(imageUrl);
    if (mounted && color != null) {
      setState(() {
        _dominantColor = color;
        _vibrantColor = HSLColor.fromColor(color)
            .withLightness(
              (HSLColor.fromColor(color).lightness + 0.2).clamp(0, 1),
            )
            .toColor();
      });
    }
  }

  void _updateBackgroundColor(String imageUrl) async {
    if (imageUrl.isEmpty) return;
    final color = await ColorExtractor.extractColorFromUrl(imageUrl);
    if (mounted && color != null) {
      setState(() {
        _dominantColor = color;
        _vibrantColor = HSLColor.fromColor(color)
            .withLightness(
              (HSLColor.fromColor(color).lightness + 0.2).clamp(0, 1),
            )
            .toColor();
      });
    }
  }

  void _scrollToCurrentLyric() {
    if (_lyricParser == null || _lyricParser!.lines.isEmpty) return;
    // Lyric scrolling is handled in PortraitDetailPage
  }

  void _toggleFavorite() async {
    if (sl.playerManager.isFavorite(_music)) {
      await sl.playerManager.removeFromFavorites(_music);
    } else {
      await sl.playerManager.addToFavorites(_music);
    }
    setState(() {
      _music = _music.copyWith(
        isFavorite: !sl.playerManager.isFavorite(_music),
      );
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
    final ps = sl.playerManager.playerState.value;
    if (ps is PlayerPlaying) {
      sl.playerManager.pause();
    } else if (ps is PlayerPaused || ps is PlayerCompleted) {
      sl.playerManager.resume();
    }
  }

  void _toggleShowLyrics() {
    setState(() => _showLyrics = !_showLyrics);
  }

  void _seek(Duration duration) {
    sl.playerManager.seek(duration);
  }

  @override
  void dispose() {
    _colorAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 检测是否为横屏模式
    final isLandscape = LandscapeBreakpoints.isLandscapeMode(context);

    // 横屏模式使用横屏布局
    if (isLandscape) {
      return const LandscapeDetailPage();
    }

    return ValueListenableBuilder<int?>(
      valueListenable: sl.playerManager.currentIndexNotifier,
      builder: (context, _, _) {
        // 当前 music / 索引变化时同步本地 _music（用于颜色提取等副作用）
        final liveMusic = sl.playerManager.currentMusic;
        if (liveMusic != null && liveMusic.id != _music.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _updateBackgroundColor(liveMusic.coverUrl);
            _initLyricOptions();
          });
          _music = liveMusic;
          _duration = liveMusic.duration;
        }
        return ValueListenableBuilder<Duration>(
          valueListenable: sl.playerManager.position,
          builder: (context, position, _) {
            _position = position;
            if (_showLyrics) _scrollToCurrentLyric();
            return ValueListenableBuilder<PlayerState>(
              valueListenable: sl.playerManager.playerState,
              builder: (context, ps, _) {
                final isPlaying = ps is PlayerPlaying;
                final fading = ps is PlayerPlaying && ps.fadeCountdown != null;
                return ValueListenableBuilder<PlayMode>(
                  valueListenable: sl.playerManager.playModeValue,
                  builder: (context, mode, _) {
                    final icon = switch (mode) {
                      PlayMode.sequential => Icons.repeat,
                      PlayMode.loop => Icons.repeat_one,
                      PlayMode.shuffle => Icons.shuffle,
                    };
                    return PortraitDetailPage(
                      music: _music,
                      position: _position,
                      duration: _duration,
                      isPlaying: isPlaying,
                      showLyrics: _showLyrics,
                      lyricOptions: _lyricOptions,
                      selectedLyricId: _selectedLyricId,
                      lyricParser: _lyricParser,
                      isLoadingLyrics: _isLoadingLyrics,
                      dominantColor: _dominantColor,
                      vibrantColor: _vibrantColor,
                      playModeIcon: icon,
                      isTransitioning: fading,
                      onToggleFavorite: _toggleFavorite,
                      onShare: _shareMusic,
                      onTogglePlay: _togglePlay,
                      onToggleShowLyrics: _toggleShowLyrics,
                      onLoadLyric: _loadLyric,
                      onSeek: _seek,
                      onTogglePlayMode: () => sl.playerManager.togglePlayMode(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
