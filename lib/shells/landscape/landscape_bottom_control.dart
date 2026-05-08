import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/components/common/landscape_cover_art.dart';
import 'package:bilimusic/components/common/landscape_seek_bar.dart';
import 'package:bilimusic/components/common/landscape_volume_bar.dart';

/// 横屏模式底部播放器控制栏 - Lucent设计语言
class LandscapeBottomControl extends StatefulWidget {
  final VoidCallback? onExpand;
  final VoidCallback? onPlayList;

  const LandscapeBottomControl({super.key, this.onExpand, this.onPlayList});

  @override
  State<LandscapeBottomControl> createState() => _LandscapeBottomControlState();
}

class _LandscapeBottomControlState extends State<LandscapeBottomControl> {
  AudioState? _audioState;
  Music? _currentMusic;
  PlayMode? _playMode;
  int _crossfadeCountdown = -1;

  @override
  void initState() {
    super.initState();
    _audioState = sl.playerManager.currentState;
    _currentMusic = sl.playerManager.currentMusic;
    _playMode = sl.playerManager.playMode;
    _crossfadeCountdown = sl.playerManager.crossfadeCountdown.value;
    _setupListeners();
  }

  void _setupListeners() {
    sl.playerManager.addStateListener(_onStateChanged);
    sl.playerManager.addMusicListener(_onMusicChanged);
    sl.playerManager.addPlayModeListener(_onPlayModeChanged);
    sl.playerManager.addCountdownListener(_onCountdownChanged);
  }

  void _onStateChanged(AudioState state) {
    if (mounted) setState(() => _audioState = state);
  }

  void _onMusicChanged(Music? music) {
    if (mounted) setState(() => _currentMusic = music);
  }

  void _onPlayModeChanged(PlayMode mode) {
    if (mounted) setState(() => _playMode = mode);
  }

  void _onCountdownChanged(int countdown) {
    if (mounted) setState(() => _crossfadeCountdown = countdown);
  }

  @override
  void dispose() {
    sl.playerManager.removeStateListener(_onStateChanged);
    sl.playerManager.removeMusicListener(_onMusicChanged);
    sl.playerManager.removePlayModeListener(_onPlayModeChanged);
    sl.playerManager.removeCountdownListener(_onCountdownChanged);
    super.dispose();
  }

  double _barHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= LandscapeBreakpoints.desktopMin) return 90;
    if (width >= LandscapeBreakpoints.largeTabletMin) return 96;
    return 88;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;
    final blurEnabled = sl.settingsManager.blurEffect;

    // Lucent design tokens
    final glassColor = isDark
        ? LucentTokens.darkSurfaceOverlay
        : LucentTokens.lightSurfaceOverlay;
    final textPrimary = LucentTokens.textPrimary(brightness);
    final textSecondary = LucentTokens.textSecondary(brightness);
    final iconColor = LucentTokens.textSecondary(brightness);
    final accentColor = LucentTokens.accentPrimary;
    final borderColor = LucentTokens.borderSubtle(brightness);
    final seekBarColor = LucentTokens.seekBarActive(brightness);
    final volumeBarColor = LucentTokens.volumeBarActive(brightness);

    final barHeight = _barHeight(context);
    final hPadding = LandscapeBreakpoints.getHorizontalPadding(context);

    return Container(
      height: barHeight,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurEnabled ? LucentTokens.glassBlurSigma : 0,
            sigmaY: blurEnabled ? LucentTokens.glassBlurSigma : 0,
          ),
          child: Container(
            color: glassColor,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPadding),
                child: Row(
                  children: [
                    // Left: current song tile
                    Expanded(
                      flex: 3,
                      child: _buildSongTile(textPrimary, textSecondary),
                    ),
                    // Center: play controls + seek bar
                    Expanded(
                      flex: 4,
                      child: _buildCenterControls(
                        context,
                        iconColor,
                        accentColor,
                        seekBarColor,
                      ),
                    ),
                    // Right: lyrics + volume (desktop only)
                    if (PlatformHelper.isDesktop)
                      Expanded(
                        flex: 3,
                        child: _buildRightControls(iconColor, volumeBarColor),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Left Section ====================

  Widget _buildSongTile(Color textPrimary, Color textSecondary) {
    final music = _currentMusic;
    return GestureDetector(
      onTap: widget.onExpand,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LandscapeCoverArt(
            size: 48,
            borderRadius: LucentTokens.radiusSm,
            song: music,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  music?.title ?? 'Not Playing',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                music?.artist != null
                    ? AnimatedSwitcher(
                        duration: LucentTokens.standardDuration,
                        child: _crossfadeCountdown > 0
                            ? _buildCrossfadeIndicator()
                            : Text(
                                music?.artist ?? 'Unknown Artist',
                                key: const ValueKey('artist'),
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCrossfadeIndicator() {
    return Row(
      key: const ValueKey('transition'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              LucentTokens.accentPrimary.withValues(alpha: 0.8),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '过渡中',
          style: TextStyle(
            color: LucentTokens.accentPrimary.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ==================== Center Section ====================

  Widget _buildCenterControls(
    BuildContext context,
    Color iconColor,
    Color accentColor,
    Color seekBarColor,
  ) {
    final width = MediaQuery.of(context).size.width;
    final showSeekBar = width >= LandscapeBreakpoints.largeTabletMin;
    final mainButtonSize = LandscapeBreakpoints.getMainPlayButtonSize(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPlayButtonRow(context, iconColor, accentColor, mainButtonSize),
        if (showSeekBar) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: 400,
            height: 18,
            child: LandscapeSeekBar(
              widgetHeight: 18,
              seekBarHeight: 6,
              color: seekBarColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlayButtonRow(
    BuildContext context,
    Color iconColor,
    Color accentColor,
    double mainButtonSize,
  ) {
    final smallSize = 32.0;
    final isPlaying = _audioState == AudioState.playing;
    final mode = _playMode ?? sl.playerManager.playMode;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSmallButton(
          icon: _playModeIcon(mode),
          size: smallSize,
          iconSize: smallSize * 0.55,
          color: iconColor.withValues(alpha: 0.7),
          onTap: () => sl.playerManager.togglePlayMode(),
        ),
        const SizedBox(width: 16),
        _buildSmallButton(
          icon: Icons.skip_previous_rounded,
          size: smallSize,
          iconSize: smallSize * 0.6,
          color: iconColor.withValues(alpha: 0.85),
          onTap: () => sl.playerManager.playPrevious(),
        ),
        const SizedBox(width: 16),
        ScaleOnHover(
          hoverScale: 1.05,
          child: Container(
            width: mainButtonSize,
            height: mainButtonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor,
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: IconButton(
              onPressed: () {
                if (isPlaying) {
                  sl.playerManager.pause();
                } else {
                  sl.playerManager.resume();
                }
              },
              icon: AnimatedSwitcher(
                duration: LucentTokens.standardDuration,
                switchInCurve: LucentTokens.standardEasing,
                switchOutCurve: LucentTokens.standardEasing,
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(isPlaying),
                  size: mainButtonSize * 0.5,
                  color: Colors.white,
                ),
              ),
              splashRadius: mainButtonSize * 0.5,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: mainButtonSize,
                minHeight: mainButtonSize,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _buildSmallButton(
          icon: Icons.skip_next_rounded,
          size: smallSize,
          iconSize: smallSize * 0.6,
          color: iconColor.withValues(alpha: 0.85),
          onTap: () => sl.playerManager.playNext(),
        ),
        const SizedBox(width: 16),
        if (widget.onPlayList != null)
          _buildSmallButton(
            icon: Icons.queue_music,
            size: smallSize,
            iconSize: smallSize * 0.55,
            color: iconColor.withValues(alpha: 0.7),
            onTap: widget.onPlayList,
          ),
      ],
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: ScaleOnHover(
        hoverScale: 1.12,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: iconSize, color: color),
          splashRadius: size * 0.5,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size, minHeight: size),
        ),
      ),
    );
  }

  IconData _playModeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequential:
        return Icons.queue_music;
      case PlayMode.loop:
        return Icons.repeat;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  // ==================== Right Section ====================

  Widget _buildRightControls(Color iconColor, Color volumeBarColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ScaleOnHover(
          hoverScale: 1.1,
          child: IconButton(
            onPressed: () {
              // TODO: 桌面歌词功能
            },
            icon: Icon(
              Icons.lyrics_outlined,
              size: 22,
              color: iconColor.withValues(alpha: 0.7),
            ),
            splashRadius: 18,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 20,
          width: 120,
          child: LandscapeVolumeBar(activeColor: volumeBarColor),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
