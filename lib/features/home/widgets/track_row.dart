import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';

import 'home_format.dart';

/// 首页曲目行：封面 + 标题 + 副标题 + 时长，长按 / 右键出曲目菜单。
///
/// 竖屏行高 58、封面 48；[compact] 是横屏档（56 / 40）。
class HomeTrackRow extends ConsumerWidget {
  const HomeTrackRow({
    super.key,
    required this.music,
    required this.onTap,
    this.compact = false,
  });

  final Music music;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.bmColors;
    final type = context.bmType;
    final coverSize = compact ? BmTokens.controlLg : BmTokens.row;
    final rowHeight = compact ? BmTokens.trackRowCompact : BmTokens.trackRow;

    return AppContextMenu(
      menuProvider: (_) => buildMusicContextMenu(
        context: context,
        music: music,
        playerCoordinator: ref.read(playerCoordinatorProvider),
        commands: ref.read(playlistCommandsProvider.notifier),
        playlistService: ref.read(playlistServiceProvider),
        ref: ref,
      ),
      child: BmPressable(
        onTap: onTap,
        borderRadius: BmTokens.r10All,
        semanticLabel: '${music.title}，${music.artist.displayName}',
        child: SizedBox(
          height: rowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.s1 + BmTokens.s1 / 2,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BmTokens.albumArtRadius,
                  child: SizedBox(
                    width: coverSize,
                    height: coverSize,
                    child: BmArtImage(
                      url: music.safeCoverUrl,
                      cacheKey: music.id,
                    ),
                  ),
                ),
                const SizedBox(width: BmTokens.s3),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.label.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        music.subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: BmTokens.s2),
                Text(
                  formatTrackTime(music.duration),
                  style: BmTypography.numeric(
                    type.micro.copyWith(color: colors.textTertiary),
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
