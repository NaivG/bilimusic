import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/player_state.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/services/pip_service.dart';
import 'package:bilimusic/theme/app_palette.dart';
import 'package:bilimusic/theme/app_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端画中画覆盖层
/// 在 PiP 模式下渲染的紧凑播放器控件
class PipOverlay extends ConsumerWidget {
  const PipOverlay({super.key});

  void _togglePlay(PlayerState state, WidgetRef ref) {
    final commands = ref.read(playbackCommandsProvider.notifier);
    if (state is PlayerPlaying) {
      commands.pause();
    } else if (state is PlayerPaused || state is PlayerCompleted) {
      commands.resume();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(playerStateProvider);
    final position = ref.watch(positionProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            _buildBackground(context),
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
                  _buildTopRow(context, currentMusic, playerState),
                  const SizedBox(height: 8),
                  _buildTransportRow(context, playerState, ref),
                  const SizedBox(height: 6),
                  _buildProgressBar(context, position, currentMusic),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    final palette = context.appPalette;
    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: AppTokens.overlayBlurSigma,
        sigmaY: AppTokens.overlayBlurSigma,
      ),
      child: Container(color: palette.surfaceOverlay),
    );
  }

  Widget _buildTopRow(
    BuildContext context,
    Music? currentMusic,
    PlayerState playerState,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurfaceVariant;

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            child: _buildCover(context, currentMusic),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildSongInfo(
              context,
              textPrimary,
              textSecondary,
              currentMusic,
              playerState,
            ),
          ),
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

  Widget _buildSongInfo(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Music? music,
    PlayerState playerState,
  ) {
    final fading =
        playerState is PlayerPlaying && playerState.fadeCountdown != null;
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
                ? _buildTransitionText(context)
                : Text(
                    music.artist,
                    key: const ValueKey('artist'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textSecondary, fontSize: 12),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildTransportRow(
    BuildContext context,
    PlayerState playerState,
    WidgetRef ref,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = colorScheme.primary;
    final textSecondary = colorScheme.onSurfaceVariant;
    final isPlaying = playerState is PlayerPlaying;
    final hasMusic = ref.read(playerCoordinatorProvider).currentMusic != null;
    final commands = ref.read(playbackCommandsProvider.notifier);

    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TransportButton(
            icon: Icons.skip_previous_rounded,
            color: textSecondary,
            onTap: hasMusic ? () => commands.playPrevious() : null,
          ),
          const SizedBox(width: 24),
          _TransportButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: accentColor,
            size: 32,
            onTap: hasMusic ? () => _togglePlay(playerState, ref) : null,
          ),
          const SizedBox(width: 24),
          _TransportButton(
            icon: Icons.skip_next_rounded,
            color: textSecondary,
            onTap: hasMusic ? () => commands.playNext() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    Duration position,
    Music? music,
  ) {
    final palette = context.appPalette;
    final accentColor = Theme.of(context).colorScheme.primary;
    final progressColor = palette.surfaceHover;
    final duration = music?.duration ?? Duration.zero;
    final p = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Container(width: constraints.maxWidth, color: progressColor),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p),
                  duration: AppTokens.standardDuration,
                  curve: AppTokens.standardEasing,
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
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    final textTertiary = colorScheme.onSurfaceVariant;
    final surfaceHover = palette.surfaceHover;

    return Container(
      width: 52,
      height: 52,
      color: surfaceHover,
      child: Icon(Icons.music_note_rounded, color: textTertiary, size: 28),
    );
  }

  Widget _buildTransitionText(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final transitionColor = accent.withValues(alpha: 0.8);

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