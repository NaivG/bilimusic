import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:bilimusic/features/lyrics/widgets/lyric_section.dart';
import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/features/player/now_playing/album_section.dart';
import 'package:bilimusic/domain/music.dart' as model;
import 'package:bilimusic/features/player/now_playing/detail_blur_background.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/shared/utils/dialog_helpers.dart';

/// 竖屏详情页 —— Apple Music 风格单面板布局
/// （与 `AlbumSection` 思路一致：封面 + 信息 + 操作 + 进度 + 5 按钮 + 音量）
class PortraitDetailPage extends ConsumerStatefulWidget {
  final model.Music music;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isFavorite;
  final bool showLyrics;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final LyricController? lyricController;
  final bool isLoadingLyrics;
  final Color? dominantColor;
  final IconData playModeIcon;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleShowLyrics;
  final VoidCallback onPlaylist;
  final Function(String) onLoadLyric;
  final Function(Duration) onSeek;
  final VoidCallback onTogglePlayMode;

  const PortraitDetailPage({
    super.key,
    required this.music,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isFavorite,
    required this.showLyrics,
    required this.lyricSources,
    required this.selectedLyricId,
    required this.lyricController,
    required this.isLoadingLyrics,
    required this.dominantColor,
    required this.playModeIcon,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onTogglePlay,
    required this.onToggleShowLyrics,
    required this.onPlaylist,
    required this.onLoadLyric,
    required this.onSeek,
    required this.onTogglePlayMode,
  });

  @override
  ConsumerState<PortraitDetailPage> createState() => _PortraitDetailPageState();
}

class _PortraitDetailPageState extends ConsumerState<PortraitDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          widget.dominantColor?.withValues(alpha: 0.4) ?? Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          _buildBackground(),
          widget.showLyrics
              ? _buildLyricsView(context)
              : _buildAlbumView(context),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AutoAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 24,
          ),
        ),
        onPressed: () => ShellPageManager.instance.pop(),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
          ),
          onPressed: () => _showOptionsSheet(context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBackground() {
    return DetailBlurBackground(
      dominantColor: widget.dominantColor,
      coverUrl: widget.music.coverUrl,
    );
  }

  Widget _buildAlbumView(BuildContext context) {
    // 高度有界交给 AlbumSection：内容放得下时富余高度分摊到封面上下，放不下自滚动。
    return SafeArea(
      child: AlbumSection(
        coverUrl: widget.music.coverUrl,
        title: widget.music.title,
        artist: widget.music.artist,
        album: widget.music.album,
        dominantColor: widget.dominantColor,
        isFavorite: widget.isFavorite,
        trackId: widget.music.id,
        onFavoritePressed: widget.onToggleFavorite,
        onSharePressed: widget.onShare,
        isPlaying: widget.isPlaying,
        playModeIcon: widget.playModeIcon,
        onPlayPause: widget.onTogglePlay,
        onPrevious: () =>
            ref.read(playbackCommandsProvider.notifier).playPrevious(),
        onNext: () =>
            ref.read(playbackCommandsProvider.notifier).playNext(),
        onPlayModeToggle: widget.onTogglePlayMode,
        onPlaylist: widget.onPlaylist,
        onShowLyrics: widget.onToggleShowLyrics,
      ),
    );
  }

  Widget _buildLyricsView(BuildContext context) {
    return LyricSection(
      title: widget.music.title,
      artist: widget.music.artist,
      album: widget.music.album,
      lyricController: widget.lyricController,
      position: widget.position,
      lyricSources: widget.lyricSources,
      selectedLyricId: widget.selectedLyricId,
      isLoadingLyrics: widget.isLoadingLyrics,
      onLyricSourceChanged: widget.onLoadLyric,
      onLyricTap: widget.onSeek,
    );
  }

  void _showOptionsSheet(BuildContext context) {
    showOptionsSheet(
      context,
      actions: [
        SheetAction(
          icon: widget.isFavorite ? Icons.favorite : Icons.favorite_border,
          iconColor: widget.isFavorite ? Colors.red : null,
          label: widget.isFavorite ? '取消收藏' : '收藏',
          onTap: widget.onToggleFavorite,
        ),
        SheetAction(icon: Icons.share, label: '分享', onTap: widget.onShare),
        SheetAction(
          icon: widget.showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
          label: widget.showLyrics ? '隐藏歌词' : '显示歌词',
          onTap: widget.onToggleShowLyrics,
        ),
        SheetAction(
          icon: Icons.info_outline,
          label: '歌曲信息',
          onTap: () => _showSongInfo(context),
        ),
      ],
    );
  }

  void _showSongInfo(BuildContext context) {
    showSongInfoDialog(
      context,
      title: widget.music.title,
      artist: widget.music.artist,
      album: widget.music.album,
      duration: widget.duration ?? Duration.zero,
    );
  }
}
