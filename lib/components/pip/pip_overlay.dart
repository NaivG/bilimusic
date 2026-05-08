import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/pip_service.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端画中画覆盖层
/// 在 PiP 模式下渲染的紧凑播放器控件
class PipOverlay extends StatefulWidget {
  const PipOverlay({super.key});

  @override
  State<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends State<PipOverlay> {
  AudioState? _audioState;
  Music? _currentMusic;
  Duration _position = Duration.zero;
  int _crossfadeCountdown = -1;

  @override
  void initState() {
    super.initState();
    _audioState = sl.playerManager.currentState;
    _currentMusic = sl.playerManager.currentMusic;

    sl.playerManager.addStateListener(_updateAudioState);
    sl.playerManager.addPositionListener(_updatePosition);
    sl.playerManager.addMusicListener(_updateMusic);
    sl.playerManager.addCountdownListener(_updateCountdown);
  }

  @override
  void dispose() {
    sl.playerManager.removeStateListener(_updateAudioState);
    sl.playerManager.removePositionListener(_updatePosition);
    sl.playerManager.removeMusicListener(_updateMusic);
    sl.playerManager.removeCountdownListener(_updateCountdown);
    super.dispose();
  }

  void _updateAudioState(AudioState state) {
    if (mounted) setState(() => _audioState = state);
  }

  void _updatePosition(Duration position) {
    if (mounted) setState(() => _position = position);
  }

  void _updateMusic(Music? music) {
    if (mounted) setState(() => _currentMusic = music);
  }

  void _updateCountdown(int countdown) {
    if (mounted) setState(() => _crossfadeCountdown = countdown);
  }

  void _togglePlay() {
    if (_audioState == AudioState.playing) {
      sl.playerManager.pause();
    } else {
      sl.playerManager.resume();
    }
  }

  double get _progress {
    final duration = _currentMusic?.duration;
    if (duration == null || duration.inMilliseconds == 0) return 0.0;
    return (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = View.of(context).platformDispatcher.platformBrightness;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // 毛玻璃背景
            _buildBackground(brightness),
            // 拖拽手柄（覆盖整个区域，排除关闭按钮区域）
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: Container(),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // 上栏：专辑封面 + 文字 + 关闭按钮
                  _buildTopRow(brightness),
                  const SizedBox(height: 8),
                  // 传输控件行
                  _buildTransportRow(brightness),
                  const SizedBox(height: 6),
                  // 进度条
                  _buildProgressBar(brightness),
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

  Widget _buildTopRow(Brightness brightness) {
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
          // 专辑封面
          ClipRRect(
            borderRadius: BorderRadius.circular(LucentTokens.radiusMd),
            child: _currentMusic != null
                ? CachedNetworkImage(
                    imageUrl: _currentMusic!.safeCoverUrl,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _buildCoverPlaceholder(),
                    errorWidget: (context, url, error) =>
                        _buildCoverPlaceholder(),
                    cacheManager: imageCacheManager,
                    cacheKey: _currentMusic!.id,
                  )
                : _buildCoverPlaceholder(),
          ),
          const SizedBox(width: 12),
          // 歌曲信息
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentMusic?.title ?? 'Not Playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_currentMusic != null) ...[
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _crossfadeCountdown > 0
                        ? _buildTransitionText()
                        : Text(
                            _currentMusic!.artist,
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
            ),
          ),
          // 关闭按钮
          GestureDetector(
            onTap: () => PipService().exitPipMode(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: Icon(
                Icons.close,
                size: 18,
                color: textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportRow(Brightness brightness) {
    final accentColor = LucentTokens.accentPrimary;
    final textSecondary = brightness == Brightness.dark
        ? LucentTokens.darkTextSecondary
        : LucentTokens.lightTextSecondary;

    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一首
          _TransportButton(
            icon: Icons.skip_previous_rounded,
            color: textSecondary,
            onTap: _currentMusic != null
                ? () => sl.playerManager.playPrevious()
                : null,
          ),
          const SizedBox(width: 24),
          // 播放/暂停
          _TransportButton(
            icon: _audioState == AudioState.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: accentColor,
            size: 32,
            onTap: _currentMusic != null ? _togglePlay : null,
          ),
          const SizedBox(width: 24),
          // 下一首
          _TransportButton(
            icon: Icons.skip_next_rounded,
            color: textSecondary,
            onTap: _currentMusic != null
                ? () => sl.playerManager.playNext()
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(Brightness brightness) {
    final progressColor = brightness == Brightness.dark
        ? LucentTokens.darkSurfaceHover
        : LucentTokens.lightSurfaceHover;
    final accentColor = LucentTokens.accentPrimary;

    return SizedBox(
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // 背景轨道
                Container(width: constraints.maxWidth, color: progressColor),
                // 进度填充
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _progress),
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

  Widget _buildCoverPlaceholder() {
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
      child: Icon(
        Icons.music_note_rounded,
        color: textTertiary,
        size: 28,
      ),
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
