import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/widgets/long_press_menu.dart';

/// 首页「为你推荐」媒体卡：封面 + 标题 + UP 主，右键 / 长按出曲目菜单。
class HomeMusicCard extends ConsumerWidget {
  const HomeMusicCard({super.key, required this.music, required this.onTap});

  final Music music;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppContextMenu(
      // 菜单展开时才读 Provider，构建期不初始化播放器与歌单服务。
      menuProvider: (_) => buildMusicContextMenu(
        context: context,
        music: music,
        playerCoordinator: ref.read(playerCoordinatorProvider),
        commands: ref.read(playlistCommandsProvider.notifier),
        playlistService: ref.read(playlistServiceProvider),
        ref: ref,
      ),
      child: BmMediaCard(
        cover: BmArtImage(url: music.safeCoverUrl, cacheKey: music.id),
        title: music.title,
        subtitle: music.artist.displayName,
        onTap: onTap,
      ),
    );
  }
}
