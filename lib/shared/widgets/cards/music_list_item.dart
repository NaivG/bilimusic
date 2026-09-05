import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/common/cards/common_music_list_tile.dart';

/// 列表样式组件
/// 类似于PlaylistItem，用于单page或单个id-cid实例
class MusicListItem extends StatelessWidget {
  final Music music;
  final int? index;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final PlayerCoordinator playerCoordinator;
  final PlaylistManager? playlistManager;
  final bool showCover;
  final bool showDetails;
  final bool showPageIndicator;

  const MusicListItem({
    super.key,
    required this.music,
    required this.playerCoordinator,
    this.playlistManager,
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
      playlistManager: playlistManager,
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
