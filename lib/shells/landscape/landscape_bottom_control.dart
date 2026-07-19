import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/play_mode.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/providers/settings_provider.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/platform_helper.dart';
import 'package:bilimusic/components/common/landscape_cover_art.dart';
import 'package:bilimusic/components/common/landscape_seek_bar.dart';
import 'package:bilimusic/components/common/landscape_volume_bar.dart';

/// 横屏模式底部播放器控制栏 - Lucent设计语言
class LandscapeBottomControl extends ConsumerWidget {
  final VoidCallback? onExpand;
  final VoidCallback? onPlayList;

  const LandscapeBottomControl({super.key, this.onExpand, this.onPlayList});

  double _barHeight(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= LandscapeBreakpoints.desktopMin) return 90;
    if (width >= LandscapeBreakpoints.largeTabletMin) return 96;
    return 88;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final isDark = brightness == Brightness.dark;
    final blurEnabled = ref.watch(settingsProvider).blurEffect;

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

    final currentMusic = ref.watch(currentMusicProvider);
    final playMode = ref.watch(playModeProvider);
    final playerState = ref.watch(playerStateProvider);
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
                      child: _buildSongTile(
                        textPrimary,
                        textSecondary,
                        currentMusic,
                        playerState,
                      ),
                    ),
                    // Center: play controls + seek bar
                    Expanded(
                      flex: 4,
                      child: _buildCenterControls(
                        context,
                        ref,
                        iconColor,
                        accentColor,
                        seekBarColor,
                        playMode,
                        playerState,
                      ),
                    ),
                    // Right: lyrics + volume (desktop only)
                    if (PlatformHelper.isDesktop)
                      Expanded(
                        flex: 3,
                        child: _buildRightControls(
                          context,
                          ref,
                          iconColor,
                          volumeBarColor,
                        ),
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

  Widget _buildSongTile(
    Color textPrimary,
    Color textSecondary,
    Music? music,
    PlayerState playerState,
  ) {
    final fading =
        playerState is PlayerPlaying && playerState.fadeCountdown != null;
    return GestureDetector(
      onTap: onExpand,
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
                        child: fading
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
    WidgetRef ref,
    Color iconColor,
    Color accentColor,
    Color seekBarColor,
    PlayMode playMode,
    PlayerState playerState,
  ) {
    final width = MediaQuery.of(context).size.width;
    final showSeekBar = width >= LandscapeBreakpoints.largeTabletMin;
    final mainButtonSize = LandscapeBreakpoints.getMainPlayButtonSize(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPlayButtonRow(
          context,
          ref,
          iconColor,
          accentColor,
          mainButtonSize,
          playMode,
          playerState,
        ),
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
    WidgetRef ref,
    Color iconColor,
    Color accentColor,
    double mainButtonSize,
    PlayMode playMode,
    PlayerState playerState,
  ) {
    final smallSize = 32.0;
    final isPlaying = playerState is PlayerPlaying;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildSmallButton(
          icon: _playModeIcon(playMode),
          size: smallSize,
          iconSize: smallSize * 0.55,
          color: iconColor.withValues(alpha: 0.7),
          onTap: () =>
              ref.read(playbackCommandsProvider.notifier).togglePlayMode(),
        ),
        const SizedBox(width: 16),
        _buildSmallButton(
          icon: Icons.skip_previous_rounded,
          size: smallSize,
          iconSize: smallSize * 0.6,
          color: iconColor.withValues(alpha: 0.85),
          onTap: () =>
              ref.read(playbackCommandsProvider.notifier).playPrevious(),
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
                  ref.read(playbackCommandsProvider.notifier).pause();
                } else {
                  ref.read(playbackCommandsProvider.notifier).resume();
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
          onTap: () => ref.read(playbackCommandsProvider.notifier).playNext(),
        ),
        const SizedBox(width: 16),
        if (onPlayList != null)
          _buildSmallButton(
            icon: Icons.queue_music,
            size: smallSize,
            iconSize: smallSize * 0.55,
            color: iconColor.withValues(alpha: 0.7),
            onTap: onPlayList,
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
        return Icons.repeat_rounded;
      case PlayMode.loop:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  // ==================== Right Section ====================

  Widget _buildRightControls(
    BuildContext context,
    WidgetRef ref,
    Color iconColor,
    Color volumeBarColor,
  ) {
    final volume = ref.watch(volumeProvider);
    final commands = ref.read(playbackCommandsProvider.notifier);
    final isMuted = volume == 0;

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
        const SizedBox(width: 4),
        ScaleOnHover(
          hoverScale: 1.1,
          child: IconButton(
            onPressed: () => commands.toggleMute(),
            icon: Icon(
              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20,
              color: iconColor.withValues(alpha: 0.7),
            ),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
        const SizedBox(width: 4),
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
