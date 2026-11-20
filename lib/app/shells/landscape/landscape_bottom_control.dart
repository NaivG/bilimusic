import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/play_mode.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/widgets/crossfade_indicator.dart';
import 'package:bilimusic/features/player/widgets/landscape_seek_strip.dart';
import 'package:bilimusic/features/player/widgets/landscape_volume_control.dart';
import 'package:bilimusic/features/player/widgets/playback_buttons.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/roam/roam_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/controls/bm_controls.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/animations.dart';
import 'package:bilimusic/shared/utils/play_mode_icon.dart';
import 'package:bilimusic/shared/widgets/music_cover.dart';

/// 横屏模式底部播放器控制栏 - Theater 设计语言
///
/// 左当前歌曲、中播放控制、右收藏 + 音量，三段
/// 按 3:6:3 分宽；进度是贴上沿的全宽细线（[LandscapeSeekStrip]），不占三段的
/// 高度。
class LandscapeBottomControl extends ConsumerWidget {
  final VoidCallback? onExpand;
  final VoidCallback onPlayList;

  const LandscapeBottomControl({
    super.key,
    this.onExpand,
    required this.onPlayList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final blurEnabled = ref.watch(
      settingsProvider.select((settings) => settings.blurEffect),
    );

    final currentMusic = ref.watch(currentMusicProvider);
    final playMode = ref.watch(playModeProvider);
    final isRoaming = ref.watch(isRoamingProvider);
    final playerState = ref.watch(playerStateProvider);

    return SizedBox(
      height: BmTokens.playbarHeight,
      child: BmChromeSurface(
        edges: const <BmChromeEdge>{BmChromeEdge.top},
        blur: blurEnabled,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BmTokens.playbarInset,
                  ),
                  child: Row(
                    children: [
                      // Left: current song tile
                      Expanded(
                        flex: 3,
                        child: _buildSongTile(
                          context,
                          colors,
                          currentMusic,
                          playerState,
                        ),
                      ),
                      // Center: play controls
                      Expanded(
                        flex: 4,
                        child: Center(
                          // 极窄窗口下（600 宽再叠侧边安全区）等比缩一点，
                          // 保证单档尺寸不溢出。
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _buildPlayControls(
                              ref,
                              colors,
                              playMode,
                              isRoaming,
                              playerState,
                            ),
                          ),
                        ),
                      ),
                      // Right: favorite + volume
                      Expanded(
                        flex: 3,
                        child: _buildRightControls(ref, colors, currentMusic),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 顶沿进度条
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LandscapeSeekStrip(),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Left Section ====================

  /// 左侧当前歌曲卡片：整块可点开详情页，四态走 [BmPressable]。
  Widget _buildSongTile(
    BuildContext context,
    BmColors colors,
    Music? music,
    PlayerState playerState,
  ) {
    final type = context.bmType;
    final fading = isCrossfading(playerState);

    return BmPressable(
      onTap: onExpand,
      borderRadius: BmTokens.r10All,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s2,
        ),
        child: Row(
          children: [
            MusicCover(music: music, size: 48, radius: BmTokens.r10),
            const SizedBox(width: BmTokens.s3),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music?.title ?? 'Not Playing',
                    style: type.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (music != null)
                    AnimatedSwitcher(
                      duration: BmMotion.medium,
                      transitionBuilder: switcherFadeTransition,
                      child: fading
                          ? const CrossfadeIndicator()
                          : Text(
                              music.artist.displayName,
                              key: const ValueKey('artist'),
                              style: type.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Center Section ====================

  Widget _buildPlayControls(
    WidgetRef ref,
    BmColors colors,
    PlayMode playMode,
    bool isRoaming,
    PlayerState playerState,
  ) {
    const smallSize = BmTokens.controlLg;
    const mainButtonSize = BmTokens.playbarMainButton;
    final isPlaying = playerState is PlayerPlaying;
    final commands = ref.read(playbackCommandsProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PlaybackControlButton(
          icon: playMode.iconFor(isRoaming: isRoaming),
          size: smallSize,
          iconSize: smallSize * 0.78,
          iconColor: colors.textSecondary,
          hoverColor: colors.stateHover,
          // 漫游时底层固定顺序播放，不允许切换
          onTap: isRoaming ? null : commands.togglePlayMode,
        ),
        const SizedBox(width: BmTokens.s3),
        PlaybackControlButton(
          icon: Icons.skip_previous_rounded,
          size: smallSize,
          iconSize: smallSize * 0.78,
          iconColor: colors.textSecondary,
          hoverColor: colors.stateHover,
          onTap: commands.playPrevious,
        ),
        const SizedBox(width: BmTokens.s3),
        PlaybackPlayPauseButton(
          isPlaying: isPlaying,
          size: mainButtonSize,
          iconSize: mainButtonSize * 0.8,
          iconColor: colors.accent,
          hoverColor: colors.stateHover,
          onTap: isPlaying ? commands.pause : commands.resume,
        ),
        const SizedBox(width: BmTokens.s3),
        PlaybackControlButton(
          icon: Icons.skip_next_rounded,
          size: smallSize,
          iconSize: smallSize * 0.78,
          iconColor: colors.textSecondary,
          hoverColor: colors.stateHover,
          onTap: commands.playNext,
        ),
        const SizedBox(width: BmTokens.s3),
        BmIconButton(
          icon: Icons.queue_music,
          tooltip: '播放队列',
          onPressed: onPlayList,
        ),
      ],
    );
  }

  // ==================== Right Section ====================

  Widget _buildRightControls(WidgetRef ref, BmColors colors, Music? music) {
    // 收藏态：跟随当前歌曲（无歌曲时按钮置灰不可点）
    final isFav = music != null && ref.watch(isFavoriteProvider(music));

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        BmIconButton(
          icon: isFav ? Icons.favorite : Icons.favorite_border,
          tooltip: isFav ? '取消收藏' : '收藏',
          color: isFav ? colors.accent : colors.textSecondary,
          onPressed: music == null
              ? null
              : () => ref
                    .read(playlistCommandsProvider.notifier)
                    .toggleFavorite(music),
        ),
        const SizedBox(width: BmTokens.s1),
        const LandscapeVolumeControl(),
      ],
    );
  }
}
