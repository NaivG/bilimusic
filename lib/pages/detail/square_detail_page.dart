import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/components/auto_appbar.dart';
import 'package:bilimusic/components/lyric/lyric_section.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/pages/detail/portrait_detail_page.dart'
    show LyricInfo;
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/utils/dialog_helpers.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'package:bilimusic/utils/responsive.dart';

/// 方屏详情页（手表/折叠外屏/近正方形 PiP）
/// 顶部：横向封面 + 信息（miniplayer 风格）
/// 中部：进度条
/// 底部：主控按钮
class SquareDetailPage extends ConsumerWidget {
  final model.Music music;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool showLyrics;
  final List<LyricInfo> lyricOptions;
  final String? selectedLyricId;
  final LyricParser? lyricParser;
  final bool isLoadingLyrics;
  final Color? dominantColor;
  final Color? vibrantColor;
  final IconData playModeIcon;
  final bool isTransitioning;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleShowLyrics;
  final Function(String) onLoadLyric;
  final Function(Duration) onSeek;
  final VoidCallback onTogglePlayMode;

  const SquareDetailPage({
    super.key,
    required this.music,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.showLyrics,
    required this.lyricOptions,
    required this.selectedLyricId,
    required this.lyricParser,
    required this.isLoadingLyrics,
    required this.dominantColor,
    required this.vibrantColor,
    required this.playModeIcon,
    required this.isTransitioning,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onTogglePlay,
    required this.onToggleShowLyrics,
    required this.onLoadLyric,
    required this.onSeek,
    required this.onTogglePlayMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (showLyrics) return _buildLyricsView(context, ref);

    return Scaffold(
      backgroundColor: dominantColor?.withValues(alpha: 0.4) ?? Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, ref),
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final outerPadding = SquareBreakpoints.getOuterPadding(context);
                return Padding(
                  padding: EdgeInsets.all(outerPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderRow(context),
                      SizedBox(height: outerPadding),
                      _buildProgressBar(context),
                      SizedBox(height: outerPadding),
                      _buildMainControls(context, ref),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    return AutoAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 48,
      leading: IconButton(
        padding: EdgeInsets.zero,
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
          padding: EdgeInsets.zero,
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_horiz, color: Colors.white, size: 22),
          ),
          onPressed: () => _showOptionsSheet(context, ref),
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
                dominantColor?.withValues(alpha: 0.8) ?? Colors.black,
                dominantColor?.withValues(alpha: 0.6) ?? Colors.grey[900]!,
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        if (music.coverUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: CachedNetworkImage(
                imageUrl: music.coverUrl,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.3),
                colorBlendMode: BlendMode.darken,
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

  Widget _buildHeaderRow(BuildContext context) {
    final coverSize = SquareBreakpoints.getCoverSize(context);
    final placeholderIconSize = coverSize * 0.4;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: coverSize,
            height: coverSize,
            child: music.coverUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: music.coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[800],
                      child: Icon(
                        Icons.music_note,
                        color: Colors.white,
                        size: placeholderIconSize,
                      ),
                    ),
                  )
                : Container(
                    color: Colors.grey[800],
                    child: Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: placeholderIconSize,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                music.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                music.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final progress = duration != null && duration!.inSeconds > 0
        ? position.inSeconds / duration!.inSeconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              if (duration != null) {
                onSeek(
                  Duration(seconds: (value * duration!.inSeconds).toInt()),
                );
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatDuration(duration ?? Duration.zero),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls(BuildContext context, WidgetRef ref) {
    final mainSize = SquareBreakpoints.getMainPlayButtonSize(context);
    final sideSize = SquareBreakpoints.getSideButtonSize(context);
    final sideIconSize = sideSize * 0.55;
    final mainIconSize = mainSize * 0.55;
    final commands = ref.read(playbackCommandsProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SideButton(
          icon: Icons.skip_previous_rounded,
          size: sideSize,
          iconSize: sideIconSize,
          onTap: () => commands.playPrevious(),
        ),
        _MainPlayButton(
          isPlaying: isPlaying,
          size: mainSize,
          iconSize: mainIconSize,
          onTap: onTogglePlay,
        ),
        _SideButton(
          icon: Icons.skip_next_rounded,
          size: sideSize,
          iconSize: sideIconSize,
          onTap: () => commands.playNext(),
        ),
      ],
    );
  }

  Widget _buildLyricsView(BuildContext context, WidgetRef ref) {
    final lyricSources = lyricOptions.map((option) {
      return LyricSource(id: option.id, name: option.name);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(context, ref),
      body: LyricSection(
        lyricParser: lyricParser,
        position: position,
        lyricSources: lyricSources,
        selectedLyricId: selectedLyricId,
        isLoadingLyrics: isLoadingLyrics,
        onLyricSourceChanged: onLoadLyric,
        onLyricTap: onSeek,
      ),
    );
  }

  void _showOptionsSheet(BuildContext context, WidgetRef ref) {
    final commands = ref.read(playbackCommandsProvider.notifier);
    final isFav = commands.isFavorite(music);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
            const SizedBox(height: 16),
            ListTile(
              dense: true,
              leading: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? Colors.red : Colors.white,
                size: 22,
              ),
              title: Text(
                isFav ? '取消收藏' : '收藏',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                onToggleFavorite();
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.share, color: Colors.white, size: 22),
              title: const Text(
                '分享',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                onShare();
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(
                showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                color: Colors.white,
                size: 22,
              ),
              title: Text(
                showLyrics ? '隐藏歌词' : '显示歌词',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                onToggleShowLyrics();
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(playModeIcon, color: Colors.white, size: 22),
              title: const Text(
                '切换播放模式',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                onTogglePlayMode();
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.info_outline,
                color: Colors.white,
                size: 22,
              ),
              title: const Text(
                '歌曲信息',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
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
        title: const Text(
          '歌曲信息',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            infoRow('标题', music.title),
            infoRow('艺术家', music.artist),
            infoRow('专辑', music.album),
            infoRow('时长', _formatDuration(duration ?? Duration.zero)),
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

class _SideButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _SideButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.9),
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

class _MainPlayButton extends StatelessWidget {
  final bool isPlaying;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _MainPlayButton({
    required this.isPlaying,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFE0E0E0)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.35),
              blurRadius: 28,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(isPlaying),
              color: Colors.black87,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
