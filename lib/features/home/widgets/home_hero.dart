import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

import 'home_format.dart';

/// 封面底部遮罩的遮挡档位（设计稿 `.78`）。
const double _veilStrong = 0.78;

/// 首页「继续聆听」大卡。
///
/// 竖屏与横屏共用同一套版式：封面铺满 + 底部遮罩，左下 eyebrow / 标题 /
/// 副标题，右下播放键；宽度跟随内容列，高度取 [BmTokens.homeHeroPortrait]
/// 或 [BmTokens.homeHeroLandscape]。横屏只放大一档标题字号。
class HomeHeroCard extends ConsumerWidget {
  const HomeHeroCard({
    super.key,
    required this.music,
    required this.onTap,
    required this.onTogglePlay,
    this.eyebrow = '继续聆听',
    this.wide = false,
  });

  final Music music;
  final VoidCallback onTap;
  final VoidCallback onTogglePlay;
  final String eyebrow;

  /// 横屏排版：高度更低、标题大一档。
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final playing = ref.watch(playerStateProvider) is PlayerPlaying;
    final titleStyle = wide ? type.title : type.section;

    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r18All,
      pressScale: BmMotion.pressScale,
      semanticLabel: '$eyebrow，${music.title}',
      child: SizedBox(
        width: double.infinity,
        height: wide ? BmTokens.homeHeroLandscape : BmTokens.homeHeroPortrait,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BmTokens.r18All,
            boxShadow: [
              BoxShadow(
                color: colors.shadowStrong,
                blurRadius: BmTokens.s8,
                offset: const Offset(0, BmTokens.s4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BmTokens.r18All,
            child: Stack(
              fit: StackFit.expand,
              children: [
                BmArtImage(url: music.safeCoverUrl, cacheKey: music.id),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.scrim.withValues(alpha: 0),
                          colors.scrim.withValues(alpha: _veilStrong),
                        ],
                        stops: const [0.3, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: BmTokens.s5 - BmTokens.s1 / 2,
                  right: BmTokens.s4 + _PlayCircle.size + BmTokens.s3,
                  bottom: BmTokens.s4,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.micro.copyWith(
                          color: colors.stageTextSecondary,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: BmTokens.s1),
                      Text(
                        music.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle.copyWith(color: colors.stageText),
                      ),
                      const SizedBox(height: BmTokens.s1),
                      Text(
                        heroSubtitle(music),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(
                          color: colors.stageTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: BmTokens.s4,
                  bottom: BmTokens.s4,
                  child: _PlayCircle(
                    playing: playing,
                    semanticLabel: playing ? '暂停' : '播放',
                    onTap: onTogglePlay,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 52 白色播放圆钮。
class _PlayCircle extends StatelessWidget {
  const _PlayCircle({
    required this.playing,
    required this.semanticLabel,
    required this.onTap,
  });

  /// 设计稿 52。
  static const double size = BmTokens.touchScreen + BmTokens.s2;

  final bool playing;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.rPillAll,
      pressScale: BmMotion.pressScale,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surfaceRaised,
          boxShadow: [
            BoxShadow(
              color: colors.shadowStrong,
              blurRadius: BmTokens.s3,
              offset: const Offset(0, BmTokens.s1 + BmTokens.s1 / 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: BmTokens.iconLarge,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}
