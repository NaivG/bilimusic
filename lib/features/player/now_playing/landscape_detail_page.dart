import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/features/player/now_playing/background.dart';
import 'package:bilimusic/features/player/now_playing/album_section.dart';
import 'package:bilimusic/features/lyrics/widgets/lyric_section.dart';
import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/domain/music.dart' as model;
import 'package:bilimusic/app/shells/navigation_providers.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/utils/dialog_helpers.dart';
import 'package:bilimusic/shared/utils/responsive.dart';

/// 横屏详情页 —— 纯视图：左侧专辑区 + 右侧歌词面板（Apple Music 左右分栏布局）。
/// 状态与业务回调由 [DetailPage] 宿主下发，与 Portrait/Square 同一套 props 模式。
class LandscapeDetailPage extends ConsumerWidget {
  final model.Music music;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isFavorite;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final LyricController? lyricController;
  final bool isLoadingLyrics;
  final Color? dominantColor;

  /// 上一首的主导色 —— 供 [AnimatedLandscapeBackground] 做切换渐变。
  final Color? previousDominantColor;
  final IconData playModeIcon;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onTogglePlay;
  final VoidCallback onPlaylist;
  final Function(String) onLoadLyric;
  final Function(Duration) onSeek;
  final VoidCallback onTogglePlayMode;

  const LandscapeDetailPage({
    super.key,
    required this.music,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isFavorite,
    required this.lyricSources,
    required this.selectedLyricId,
    required this.lyricController,
    required this.isLoadingLyrics,
    required this.dominantColor,
    required this.previousDominantColor,
    required this.playModeIcon,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onTogglePlay,
    required this.onPlaylist,
    required this.onLoadLyric,
    required this.onSeek,
    required this.onTogglePlayMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leftRatio = LandscapeBreakpoints.getLeftSectionRatio(context);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          AnimatedLandscapeBackground(
            coverUrl: music.coverUrl,
            previousColor: previousDominantColor,
            newColor: dominantColor,
            child: const SizedBox.expand(),
          ),
          Column(
            children: [
              _buildAppBar(context, ref),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width * leftRatio,
                      child: AlbumSection(
                        coverUrl: music.coverUrl,
                        title: music.title,
                        artist: music.artist,
                        album: music.album,
                        dominantColor: dominantColor,
                        isFavorite: isFavorite,
                        trackId: music.id,
                        onFavoritePressed: onToggleFavorite,
                        onSharePressed: onShare,
                        isPlaying: isPlaying,
                        playModeIcon: playModeIcon,
                        onPlayPause: onTogglePlay,
                        onPrevious: () => ref
                            .read(playbackCommandsProvider.notifier)
                            .playPrevious(),
                        onNext: () => ref
                            .read(playbackCommandsProvider.notifier)
                            .playNext(),
                        onPlayModeToggle: onTogglePlayMode,
                        onPlaylist: onPlaylist,
                      ),
                    ),
                    Expanded(
                      child: LyricSection(
                        title: music.title,
                        artist: music.artist,
                        album: music.album,
                        lyricController: lyricController,
                        position: position,
                        lyricSources: lyricSources,
                        selectedLyricId: selectedLyricId,
                        isLoadingLyrics: isLoadingLyrics,
                        showHeader: false,
                        onLyricSourceChanged: onLoadLyric,
                        onLyricTap: onSeek,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
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
              onPressed: () =>
                  ref.read(shellNavigationProvider.notifier).maybePop(context),
            ),
            const Spacer(),
            Text(
              '正在播放',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.more_horiz,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => _showOptionsSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptionsSheet(BuildContext context) {
    showOptionsSheet(
      context,
      actions: [
        SheetAction(
          icon: isFavorite ? Icons.favorite : Icons.favorite_border,
          iconColor: isFavorite ? Colors.red : null,
          label: isFavorite ? '取消收藏' : '收藏',
          onTap: onToggleFavorite,
        ),
        SheetAction(icon: Icons.share, label: '分享', onTap: onShare),
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
      title: music.title,
      artist: music.artist,
      album: music.album,
      duration: duration ?? Duration.zero,
    );
  }
}
