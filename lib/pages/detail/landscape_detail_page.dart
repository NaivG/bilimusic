import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'package:bilimusic/utils/netease_music_api.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/landscape/background.dart';
import 'package:bilimusic/components/landscape/album_section.dart';
import 'package:bilimusic/components/landscape/controls_bar.dart';
import 'package:bilimusic/components/lyric/lyric_section.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';
import 'package:bilimusic/components/playlist/playlist_sheet.dart';

/// 横屏详情页主容器
/// Apple Music 风格的左右分栏布局
class LandscapeDetailPage extends StatefulWidget {
  const LandscapeDetailPage({super.key});

  @override
  State<LandscapeDetailPage> createState() => _LandscapeDetailPageState();
}

class _LandscapeDetailPageState extends State<LandscapeDetailPage>
    with TickerProviderStateMixin {
  late model.Music _music;
  String? _previousMusicId;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isPlaying = true;
  bool _isFavorite = false;
  int _crossfadeCountdown = -1;

  // 背景颜色
  Color? _dominantColor;
  Color? _previousDominantColor;

  // 歌词相关
  List<LyricSource> _lyricSources = [];
  String? _selectedLyricId;
  LyricParser? _lyricParser;
  bool _isLoadingLyrics = false;

  // 播放模式
  IconData _playModeIcon = Icons.repeat;

  // 监听器
  late Function(AudioState) _stateListener;
  late Function(Duration) _positionListener;
  late Function(PlayMode) _playModeListener;
  late Function(int) _countdownListener;

  @override
  void initState() {
    super.initState();

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
    _isFavorite = sl.playerManager.isFavorite(_music);

    // 提取背景颜色
    _extractBackgroundColor(_music.coverUrl);

    // 初始化歌词选项
    _initLyricOptions();

    // 设置监听器
    _setupListeners();
  }

  void _setupListeners() {
    _stateListener = (state) {
      if (!mounted) return;

      final updatedMusic = sl.playerManager.currentMusic;
      if (updatedMusic == null) return;

      final musicChanged = _previousMusicId != updatedMusic.id;

      if (musicChanged) {
        _previousMusicId = updatedMusic.id;
        _previousDominantColor = _dominantColor;
        _updateBackgroundColor(updatedMusic.coverUrl);

        // 重新加载歌词
        _initLyricOptions();

        setState(() {
          _isPlaying = state == AudioState.playing;
          _music = updatedMusic;
          _duration = updatedMusic.duration;
          _isFavorite = sl.playerManager.isFavorite(_music);
        });
      } else {
        setState(() {
          _isPlaying = state == AudioState.playing;
        });
      }
    };

    _positionListener = (position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    };

    _playModeListener = (playMode) {
      if (mounted) {
        setState(() {
          switch (playMode) {
            case PlayMode.sequential:
              _playModeIcon = Icons.repeat;
            case PlayMode.loop:
              _playModeIcon = Icons.repeat_one;
            case PlayMode.shuffle:
              _playModeIcon = Icons.shuffle;
          }
        });
      }
    };

    _countdownListener = (countdown) {
      if (mounted) {
        setState(() {
          _crossfadeCountdown = countdown;
        });
      }
    };

    sl.playerManager.addStateListener(_stateListener);
    sl.playerManager.addPositionListener(_positionListener);
    sl.playerManager.addPlayModeListener(_playModeListener);
    sl.playerManager.addCountdownListener(_countdownListener);
  }

  Future<void> _initLyricOptions() async {
    setState(() => _isLoadingLyrics = true);

    try {
      final localOption = LyricSource(id: 'local', name: _music.title);
      final neteaseOptions = await NeteaseMusicApi.searchMusic(_music.title);

      if (mounted) {
        setState(() {
          _lyricSources = [
            localOption,
            ...neteaseOptions.map(
              (info) => LyricSource(id: info.id, name: info.name),
            ),
          ];
          _isLoadingLyrics = false;
        });

        // 自动加载本地歌词
        _loadLyric('local');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyricSources = [LyricSource(id: 'local', name: _music.title)];
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
        setState(() {
          _lyricParser = LyricParser.parse(lyric!);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lyricParser = LyricParser.parse('[00:00.00]加载歌词失败');
        });
      }
    }
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
    if (sl.playerManager.isFavorite(_music)) {
      await sl.playerManager.removeFromFavorites(_music);
    } else {
      await sl.playerManager.addToFavorites(_music);
    }
    setState(() {
      _isFavorite = sl.playerManager.isFavorite(_music);
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
    if (_isPlaying) {
      sl.playerManager.pause();
    } else {
      sl.playerManager.resume();
    }
  }

  void _showPlaylist() {
    // 显示播放列表
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PlaylistSheet(
        onTrackSelect: (index) {
          sl.playerManager.playAtIndex(index);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    sl.playerManager.removeStateListener(_stateListener);
    sl.playerManager.removePositionListener(_positionListener);
    sl.playerManager.removePlayModeListener(_playModeListener);
    sl.playerManager.removeCountdownListener(_countdownListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leftRatio = LandscapeBreakpoints.getLeftSectionRatio(context);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 动态背景
          AnimatedLandscapeBackground(
            coverUrl: _music.coverUrl,
            previousColor: _previousDominantColor,
            newColor: _dominantColor,
            child: const SizedBox.expand(),
          ),
          // 主内容
          Column(
            children: [
              // 顶部导航栏
              _buildAppBar(context),
              // 主内容区
              Expanded(
                child: Row(
                  children: [
                    // 左侧封面区域
                    SizedBox(
                      width: MediaQuery.of(context).size.width * leftRatio,
                      child: AnimatedLandscapeAlbumSection(
                        coverUrl: _music.coverUrl,
                        title: _music.title,
                        artist: _music.artist,
                        album: _music.album,
                        dominantColor: _dominantColor,
                        isFavorite: _isFavorite,
                        trackId: _music.id,
                        onFavoritePressed: _toggleFavorite,
                        onSharePressed: _shareMusic,
                      ),
                    ),
                    // 右侧歌词区域
                    Expanded(
                      child: LyricSection(
                        title: _music.title,
                        artist: _music.artist,
                        album: _music.album,
                        lyricParser: _lyricParser,
                        position: _position,
                        lyricSources: _lyricSources,
                        selectedLyricId: _selectedLyricId,
                        isLoadingLyrics: _isLoadingLyrics,
                        onLyricSourceChanged: _loadLyric,
                        onLyricTap: (duration) {
                          sl.playerManager.seek(duration);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // 底部控制条
              LandscapeControlsBar(
                position: _position,
                duration: _duration,
                isPlaying: _isPlaying,
                playModeIcon: _playModeIcon,
                onPlayPause: _togglePlay,
                onPrevious: () => sl.playerManager.playPrevious(),
                onNext: () => sl.playerManager.playNext(),
                onPlayModeToggle: () => sl.playerManager.togglePlayMode(),
                onPlaylist: _showPlaylist,
                onSeek: (duration) => sl.playerManager.seek(duration),
                isTransitioning: _crossfadeCountdown > 0,
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
            // 返回按钮
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
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            // 标题
            Text(
              '正在播放',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // 更多按钮
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
