import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/common/cards/responsive_music_card.dart';
import 'package:bilimusic/components/common/cards/stacked_music_card.dart';
import 'package:bilimusic/components/common/cards/music_list_item.dart';

// Export all card components
export 'responsive_music_card.dart';
export 'horizontal_music_card.dart';
export 'stacked_music_card.dart';
export 'music_list_item.dart';
export 'bili_item_cards.dart';

// ============================================================================
// MusicCardFactory
// ============================================================================

/// 音乐卡片工厂
/// 根据渲染样式创建相应的卡片组件
class MusicCardFactory {
  /// 根据渲染样式创建卡片
  static Widget create({
    required Music music,
    required PlayerManager playerManager,
    PlaylistManager? playlistManager,
    MusicRenderStyle? style,
    VoidCallback? onTap,
    bool showArtist = true,
    bool showAlbum = true,
    double? width,
    double? height,
  }) {
    final renderStyle = style ?? music.renderStyle;

    switch (renderStyle) {
      case MusicRenderStyle.card:
        return ResponsiveMusicCard(
          music: music,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: onTap,
          showArtist: showArtist,
          showAlbum: showAlbum,
          width: width,
          height: height,
        );

      case MusicRenderStyle.stacked:
        return StackedMusicCard(
          music: music,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: onTap,
          showArtist: showArtist,
          showAlbum: showAlbum,
          width: width,
          height: height,
        );

      case MusicRenderStyle.list:
        return MusicListItem(
          music: music,
          playerManager: playerManager,
          playlistManager: playlistManager,
          onTap: onTap,
          showCover: true,
          showDetails: true,
        );
    }
  }
}
