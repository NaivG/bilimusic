import 'package:flutter/material.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/logic/player_coordinator.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/shared/widgets/cards/common_music_list_tile.dart';

/// 列表样式组件
/// 类似于PlaylistItem，用于单page或单个id-cid实例
class MusicListItem extends StatelessWidget {
  final Music music;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final PlayerCoordinator playerCoordinator;
  final PlaylistCommands commands;
  final PlaylistService playlistService;
  final bool showCover;
  final bool showDetails;
  final bool showPageIndicator;

  const MusicListItem({
    super.key,
    required this.music,
    required this.playerCoordinator,
    required this.commands,
    required this.playlistService,
    this.index,
    this.onTap,
    this.onFavoriteToggle,
    this.showCover = true,
    this.showDetails = true,
    this.showPageIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    return CommonMusicListTile(
      music: music,
      playerCoordinator: playerCoordinator,
      commands: commands,
      playlistService: playlistService,
      index: index,
      onTap: onTap,
      onFavoriteToggle: onFavoriteToggle,
      showCover: showCover,
      showDetails: showDetails,
      showPageIndicator: showPageIndicator,
      showIndex: index != null,
    );
  }
}
