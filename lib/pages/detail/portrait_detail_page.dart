import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/components/auto_appbar.dart';
import 'package:bilimusic/components/lyric/lyric_section.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';
import 'package:bilimusic/components/portrait/album_section.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/utils/dialog_helpers.dart';

/// 竖屏详情页 —— Apple Music 风格单面板布局
/// （与横屏 `LandscapeAlbumSection` 思路一致：封面 + 信息 + 操作 + 进度 + 5 按钮 + 音量）
class PortraitDetailPage extends ConsumerStatefulWidget {
  final model.Music music;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
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
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                widget.dominantColor?.withValues(alpha: 0.8) ?? Colors.black,
                widget.dominantColor?.withValues(alpha: 0.6) ??
                    Colors.grey[900]!,
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        if (widget.music.coverUrl.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: CachedNetworkImage(
                  imageUrl: widget.music.coverUrl,
                  fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.3),
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumView(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 8),
            PortraitAlbumSection(
              coverUrl: widget.music.coverUrl,
              title: widget.music.title,
              artist: widget.music.artist,
              album: widget.music.album,
              dominantColor: widget.dominantColor,
              isFavorite: _isFavorite(),
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  bool _isFavorite() {
    return ref.read(playbackCommandsProvider.notifier).isFavorite(widget.music);
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                _isFavorite() ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite() ? Colors.red : Colors.white,
              ),
              title: Text(
                _isFavorite() ? '取消收藏' : '收藏',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onToggleFavorite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('分享', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onShare();
              },
            ),
            ListTile(
              leading: Icon(
                widget.showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                color: Colors.white,
              ),
              title: Text(
                widget.showLyrics ? '隐藏歌词' : '显示歌词',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                widget.onToggleShowLyrics();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(sheetContext);
                _showSongInfo(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSongInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            infoRow('标题', widget.music.title),
            infoRow('艺术家', widget.music.artist),
            infoRow('专辑', widget.music.album),
            infoRow('时长', _formatDuration(widget.duration ?? Duration.zero)),
            infoRow('来源', 'Bilibili'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
