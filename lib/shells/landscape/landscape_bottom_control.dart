import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/utils/color_infra.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/components/common/landscape_cover_art.dart';
import 'package:bilimusic/components/common/landscape_seek_bar.dart';
import 'package:bilimusic/components/common/landscape_volume_bar.dart';

/// 横屏模式底部播放器控制栏 - 基于ParticleMusic风格
class LandscapeBottomControl extends StatefulWidget {
  final VoidCallback? onExpand;
  final VoidCallback? onPlayList;

  const LandscapeBottomControl({
    super.key,
    this.onExpand,
    this.onPlayList,
  });

  @override
  State<LandscapeBottomControl> createState() => _LandscapeBottomControlState();
}

class _LandscapeBottomControlState extends State<LandscapeBottomControl> {
  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    sl.playerManager.addStateListener(_onStateChanged);
    sl.playerManager.addPositionListener(_onPositionChanged);
  }

  void _onStateChanged(AudioState state) {
    if (mounted) setState(() {});
  }

  void _onPositionChanged(Duration position) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    sl.playerManager.removeStateListener(_onStateChanged);
    sl.playerManager.removePositionListener(_onPositionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
        return Material(
          color: bottomColor,
          child: SizedBox(
            height: 75,
            child: Stack(
              children: [
                _currentSongTile(),
                _playControls(context),
                if (PlatformHelper.isDesktop) _otherControls(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 当前歌曲信息
  Widget _currentSongTile() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 300,
        child: ValueListenableBuilder(
          valueListenable: updateColorNotifier,
          builder: (context, _, _) {
            final currentMusic = sl.playerManager.currentMusic;
            return Theme(
              data: Theme.of(context).copyWith(
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 16),
                leading: LandscapeCoverArt(
                  size: 50,
                  borderRadius: 5,
                  song: currentMusic,
                ),
                title: Text(
                  currentMusic?.title ?? '未播放',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
                subtitle: currentMusic != null
                    ? Text(
                        _getArtistText(currentMusic),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )
                    : null,
                onTap: widget.onExpand,
              ),
            );
          },
        ),
      ),
    );
  }

  String _getArtistText(Music music) {
    final parts = <String>[];
    if (music.artist.isNotEmpty) {
      parts.add(music.artist);
    }
    if (music.album.isNotEmpty) {
      parts.add(music.album);
    }
    return parts.isEmpty ? '未知艺术家' : parts.join(' - ');
  }

  /// 播放控制
  Widget _playControls(BuildContext context) {
    return Stack(
      children: [
        // 播放模式、上一首、播放/暂停、下一首、播放队列
        Positioned(
          top: 0,
          bottom: PlatformHelper.isDesktop ? null : 0,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _playModeButton(25),
                const SizedBox(width: 8),
                _skipPreviousButton(25),
                const SizedBox(width: 8),
                _playPauseButton(35),
                const SizedBox(width: 8),
                _skipNextButton(25),
                const SizedBox(width: 8),
                if (widget.onPlayList != null) _playQueueButton(25),
              ],
            ),
          ),
        ),
        // 进度条
        if (PlatformHelper.isDesktop)
          Positioned(
            top: 35,
            bottom: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                const Spacer(),
                SizedBox(
                  width: 400,
                  child: ValueListenableBuilder(
                    valueListenable: updateColorNotifier,
                    builder: (_, _, _) {
                      return LandscapeSeekBar(
                        widgetHeight: 20,
                        seekBarHeight: 10,
                        color: seekBarColor,
                      );
                    },
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
      ],
    );
  }

  /// 其他控制（桌面端）
  Widget _otherControls() {
    return Row(
      children: [
        const Spacer(),
        IconButton(
          onPressed: () {
            // TODO: 桌面歌词功能
          },
          icon: Icon(
            Icons.lyrics_outlined,
            size: 22,
            color: iconColor.withValues(alpha: 0.7),
          ),
        ),
        SizedBox(
          height: 20,
          width: 120,
          child: ValueListenableBuilder(
            valueListenable: updateColorNotifier,
            builder: (_, _, _) {
              return LandscapeVolumeBar(
                activeColor: volumeBarColor,
              );
            },
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  /// 播放模式按钮
  Widget _playModeButton(double size) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
        final playMode = sl.playerManager.playMode;
        IconData icon;
        switch (playMode) {
          case PlayMode.sequential:
            icon = Icons.queue_music;
            break;
          case PlayMode.loop:
            icon = Icons.repeat;
            break;
          case PlayMode.shuffle:
            icon = Icons.shuffle;
            break;
        }
        return IconButton(
          onPressed: () => sl.playerManager.togglePlayMode(),
          icon: Icon(
            icon,
            size: size * 0.7,
            color: iconColor.withValues(alpha: 0.7),
          ),
        );
      },
    );
  }

  /// 上一首按钮
  Widget _skipPreviousButton(double size) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
        return IconButton(
          onPressed: () => sl.playerManager.playPrevious(),
          icon: Icon(
            Icons.skip_previous_rounded,
            size: size,
            color: iconColor.withValues(alpha: 0.85),
          ),
        );
      },
    );
  }

  /// 播放/暂停按钮
  Widget _playPauseButton(double size) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
        final isPlaying = sl.playerManager.isPlaying;
        return IconButton(
          onPressed: () {
            if (isPlaying) {
              sl.playerManager.pause();
            } else {
              sl.playerManager.resume();
            }
          },
          icon: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selectedItemColor,
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: size * 0.7,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  /// 下一首按钮
  Widget _skipNextButton(double size) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
        return IconButton(
          onPressed: () => sl.playerManager.playNext(),
          icon: Icon(
            Icons.skip_next_rounded,
            size: size,
            color: iconColor.withValues(alpha: 0.85),
          ),
        );
      },
    );
  }

  /// 播放队列按钮
  Widget _playQueueButton(double size) {
    return ValueListenableBuilder(
      valueListenable: updateColorNotifier,
      builder: (context, _, _) {
        return IconButton(
          onPressed: widget.onPlayList,
          icon: Icon(
            Icons.queue_music,
            size: size,
            color: iconColor.withValues(alpha: 0.7),
          ),
        );
      },
    );
  }
}
