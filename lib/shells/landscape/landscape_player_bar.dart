import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/color_extractor.dart';
import 'package:flutter/foundation.dart';

/// 横屏/桌面模式底部播放器条 - 仿网易云音乐风格
class LandscapePlayerBar extends StatefulWidget {
  final VoidCallback onExpand;
  final VoidCallback onPlayList;

  const LandscapePlayerBar({
    super.key,
    required this.onExpand,
    required this.onPlayList,
  });

  @override
  State<LandscapePlayerBar> createState() => _LandscapePlayerBarState();
}

class _LandscapePlayerBarState extends State<LandscapePlayerBar> {
  // 网易云音乐品牌红色
  static const Color neteaseRed = Color(0xFFEC407A);

  AudioState? _audioState;
  model.Music? _currentMusic;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayMode _playMode = PlayMode.sequential;
  Color? _backgroundColor;

  @override
  void initState() {
    super.initState();
    _audioState = sl.playerManager.currentState;
    _currentMusic = sl.playerManager.currentMusic;
    _playMode = sl.playerManager.playMode;

    sl.playerManager.addStateListener(_updateAudioState);
    sl.playerManager.addPositionListener(_updatePosition);
    sl.playerManager.addPlayModeListener(_updatePlayMode);

    _extractBackgroundColor();
  }

  void _extractBackgroundColor() async {
    final music = sl.playerManager.currentMusic;
    if (music == null || music.coverUrl.isEmpty) return;
    if (!sl.settingsManager.blurEffect) {
      setState(() => _backgroundColor = null);
      return;
    }
    final color = await ColorExtractor.extractColorFromUrl(music.coverUrl);
    if (mounted) {
      setState(() {
        _backgroundColor = color != null ? color.withValues(alpha: 0.3) : null;
      });
    }
  }

  void _updatePlayMode(PlayMode mode) => setState(() => _playMode = mode);

  void _updateAudioState(AudioState state) {
    setState(() {
      _audioState = state;
      if (sl.playerManager.currentMusic?.id != _currentMusic?.id) {
        _currentMusic = sl.playerManager.currentMusic;
        _extractBackgroundColor();
      }
    });
  }

  void _updatePosition(Duration pos) => setState(() => _position = pos);

  @override
  void dispose() {
    sl.playerManager.removeStateListener(_updateAudioState);
    sl.playerManager.removePositionListener(_updatePosition);
    sl.playerManager.removePlayModeListener(_updatePlayMode);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _togglePlay() async {
    if (_audioState == AudioState.playing) {
      await sl.playerManager.pause();
    } else {
      await sl.playerManager.resume();
    }
  }

  IconData _playModeIcon() {
    switch (_playMode) {
      case PlayMode.sequential:
        return Icons.repeat;
      case PlayMode.loop:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  double get _progress {
    final d = _duration.inMilliseconds;
    return d > 0 ? _position.inMilliseconds / d : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentMusic == null && sl.playerManager.currentMusic == null) {
      return const SizedBox(height: 0);
    }

    // 当音乐变化时重新提取背景颜色并更新_currentMusic
    if (sl.playerManager.currentMusic != null &&
        sl.playerManager.currentMusic?.id != _currentMusic?.id) {
      setState(() {
        _currentMusic = sl.playerManager.currentMusic;
      });
      _extractBackgroundColor();
    }

    final music = _currentMusic ?? sl.playerManager.currentMusic;
    _duration = music?.duration ?? Duration.zero;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 网易云音乐风格：深色背景配红色点缀
    Color baseColor;
    if (sl.settingsManager.blurEffect && _backgroundColor != null) {
      baseColor = _backgroundColor!;
    } else {
      baseColor = isDark ? const Color(0xFF1f1f1f) : const Color(0xFF2a2a2a);
    }

    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.98),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
          bottom: BorderSide(width: 12, style: BorderStyle.none),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            // 左侧：封面 + 歌曲信息
            Expanded(flex: 4, child: _buildLeftSection(music, theme)),
            // 中间：播放控制 + 进度条
            Expanded(flex: 6, child: _buildCenterSection(theme)),
            // 右侧：音量 + 播放列表
            Expanded(flex: 3, child: _buildRightSection(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSection(model.Music? music, ThemeData theme) {
    return Row(
      children: [
        // 封面
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: GestureDetector(
            onTap: widget.onExpand,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: music != null
                  ? CachedNetworkImage(
                      imageUrl: music.safeCoverUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 56,
                        height: 56,
                        color: Colors.white24,
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white70,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: Colors.white24,
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.white70,
                        ),
                      ),
                      cacheManager: imageCacheManager,
                      cacheKey: music.id,
                    )
                  : Container(width: 56, height: 56, color: Colors.white24),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 歌曲信息
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                music?.title ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                music?.artist ?? '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterSection(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 控制按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconBtn(
              icon: _playModeIcon(),
              size: 18,
              onTap: () => sl.playerManager.togglePlayMode(),
              color: Colors.white54,
            ),
            const SizedBox(width: 20),
            _IconBtn(
              icon: Icons.skip_previous,
              size: 24,
              onTap: sl.playerManager.playPrevious,
              color: Colors.white,
            ),
            const SizedBox(width: 16),
            // 播放/暂停大按钮 - 网易云音乐红色
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: neteaseRed,
                ),
                child: Icon(
                  _audioState == AudioState.playing
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 16),
            _IconBtn(
              icon: Icons.skip_next,
              size: 24,
              onTap: sl.playerManager.playNext,
              color: Colors.white,
            ),
            const SizedBox(width: 20),
            _IconBtn(
              icon: Icons.playlist_play,
              size: 18,
              onTap: widget.onPlayList,
              color: Colors.white54,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 进度条
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 4,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 8,
                    ),
                    activeTrackColor: neteaseRed,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: neteaseRed.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _progress.clamp(0.0, 1.0),
                    onChanged: (v) {
                      final newPos = Duration(
                        milliseconds: (v * _duration.inMilliseconds).round(),
                      );
                      sl.playerManager.seek(newPos);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightSection(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IconBtn(
          icon: Icons.volume_up,
          size: 16,
          onTap: () {},
          color: Colors.white54,
        ),
        const SizedBox(width: 24),
        _IconBtn(
          icon: Icons.fullscreen,
          size: 16,
          onTap: widget.onExpand,
          color: Colors.white54,
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;

  const _IconBtn({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}
