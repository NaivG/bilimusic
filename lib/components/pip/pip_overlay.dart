import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/services/pip_service.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端画中画覆盖层
/// 在 PiP 模式下渲染的紧凑播放器控件
class PipOverlay extends ConsumerWidget {
  const PipOverlay({super.key});

  void _togglePlay(PlayerState state) {
    if (state is PlayerPlaying) {
      sl.playerCoordinator.pause();
    } else if (state is PlayerPaused || state is PlayerCompleted) {
      sl.playerCoordinator.resume();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(playerStateProvider);
    final position = ref.watch(positionProvider);
    final brightness = View.of(context).platformDispatcher.platformBrightness;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            _buildBackground(brightness),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: Container(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildTopRow(context, brightness, currentMusic, playerState),
                  const SizedBox(height: 8),
                  _buildTransportRow(brightness, playerState),
                  const SizedBox(height: 6),
                  _buildProgressBar(brightness, position, currentMusic),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(Brightness brightness) {
    final baseColor = brightness == Brightness.dark
        ? LucentTokens.darkSurfaceOverlay
        : LucentTokens.lightSurfaceOverlay;

    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: LucentTokens.overlayBlurSigma,
        sigmaY: LucentTokens.overlayBlurSigma,
      ),
      child: Container(color: baseColor),
    );
  }

  Widget _buildTopRow(BuildContext context, Brightness brightness, Music? currentMusic, PlayerState playerState) {
    final textPrimary = brightness == Brightness.dark
        ? LucentTokens.darkTextPrimary
        : LucentTokens.lightTextPrimary;
    final textSecondary = brightness == Brightness.dark
        ? LucentTokens.darkTextSecondary
        : LucentTokens.lightTextSecondary;

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(LucentTokens.radiusMd),
            child: _buildCover(context, currentMusic),
          ),
          const SizedBox(width: 12),
          Expanded(child: _buildSongInfo(textPrimary, textSecondary, currentMusic, playerState)),
          GestureDetector(
            onTap: () => PipService().exitPipMode(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Icon(Icons.close, size: 18, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context, Music? music) {
    if (music == null) return _buildCoverPlaceholder(context);
    return CachedNetworkImage(
      imageUrl: music.safeCoverUrl,
      width: 52,
      height: 52,
      fit: BoxFit.cover,
      placeholder: (context, url) => _buildCoverPlaceholder(context),
      errorWidget: (context, url, error) => _buildCoverPlaceholder(context),
      cacheManager: imageCacheManager,
      cacheKey: music.id,
    );
  }

  Widget _buildSongInfo(Color textPrimary, Color textSecondary, Music? music, PlayerState playerState) {
    final fading = playerState is PlayerPlaying && playerState.fadeCountdown != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          music?.title ?? 'Not Playing',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (music != null) ...[
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: fading
                ? _buildTransitionText()
                : Text(
                    music.artist,
                    key: const ValueKey('artist'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildTransportRow(Brightness brightness, PlayerState playerState) {
    final accentColor = LucentTokens.accentPrimary;
    final textSecondary = brightness == Brightness.dark
        ? LucentTokens.darkTextSecondary
        : LucentTokens.lightTextSecondary;
    final isPlaying = playerState is PlayerPlaying;
    final hasMusic = sl.playerCoordinator.currentMusic != null;

    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TransportButton(
            icon: Icons.skip_previous_rounded,
            color: textSecondary,
            onTap: hasMusic ? () => sl.playerCoordinator.playPrevious() : null,
          ),
          const SizedBox(width: 24),
          _TransportButton(
            icon: isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: accentColor,
            size: 32,
            onTap: hasMusic ? () => _togglePlay(playerState) : null,
          ),
          const SizedBox(width: 24),
          _TransportButton(
            icon: Icons.skip_next_rounded,
            color: textSecondary,
            onTap: hasMusic ? () => sl.playerCoordinator.playNext() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(Brightness brightness, Duration position, Music? music) {
    final progressColor = brightness == Brightness.dark
        ? LucentTokens.darkSurfaceHover
        : LucentTokens.lightSurfaceHover;
    final accentColor = LucentTokens.accentPrimary;
    final duration = music?.duration ?? Duration.zero;
    final p = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);

    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(
                  width: constraints.maxWidth,
                  color: progressColor,
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p),
                  duration: LucentTokens.standardDuration,
                  curve: LucentTokens.standardEasing,
                  builder: (context, value, child) {
                    return Container(
                      width: constraints.maxWidth * value,
                      color: accentColor,
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTertiary = isDark
        ? LucentTokens.darkTextTertiary
        : LucentTokens.lightTextTertiary;
    final surfaceHover = isDark
        ? LucentTokens.darkSurfaceHover
        : LucentTokens.lightSurfaceHover;

    return Container(
      width: 52,
      height: 52,
      color: surfaceHover,
      child: Icon(Icons.music_note_rounded, color: textTertiary, size: 28),
    );
  }

  Widget _buildTransitionText() {
    final transitionColor = LucentTokens.accentPrimary.withValues(alpha: 0.8);

    return Row(
      key: const ValueKey('transition'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(transitionColor),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '过渡中',
            maxLines: 1,
            style: TextStyle(color: transitionColor, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 传输控件按钮
class _TransportButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  const _TransportButton({
    required this.icon,
    required this.color,
    this.size = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}
