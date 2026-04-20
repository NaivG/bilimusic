import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/common/cards/common_music_list_tile.dart';

/// 水平布局的音乐卡片（用于列表视图）
class HorizontalMusicCard extends StatelessWidget {
  final Music music;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onTap;
  final bool showCover;
  final bool showDetails;

  const HorizontalMusicCard({
    super.key,
    required this.music,
    required this.playerManager,
    this.playlistManager,
    this.onTap,
    this.showCover = true,
    this.showDetails = true,
  });

  @override
  Widget build(BuildContext context) {
    return CommonMusicListTile(
      music: music,
      playerManager: playerManager,
      playlistManager: playlistManager,
      onTap: onTap,
      showCover: showCover,
      showDetails: showDetails,
      showPageIndicator: false,
      showIndex: false,
    );
  }
}
