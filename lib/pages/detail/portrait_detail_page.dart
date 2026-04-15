import 'dart:ui';
import 'package:bilimusic/components/autoAppBar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'package:bilimusic/components/lyric/lyric_section.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';

/// 竖屏详情页
class PortraitDetailPage extends StatefulWidget {
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

  const PortraitDetailPage({
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
  State<PortraitDetailPage> createState() => _PortraitDetailPageState();
}

class _PortraitDetailPageState extends State<PortraitDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.dominantColor?.withValues(alpha: 0.4) ?? Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          // 渐变背景
          _buildBackground(),
          // 主内容
          widget.showLyrics ? _buildLyricsView(context) : _buildAlbumView(context),
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
        onPressed: () => Navigator.pop(context),
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
        // 主背景色
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                widget.dominantColor?.withValues(alpha: 0.8) ?? Colors.black,
                widget.dominantColor?.withValues(alpha: 0.6) ?? Colors.grey[900]!,
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // 封面图片模糊背景
        if (widget.music.coverUrl.isNotEmpty)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: CachedNetworkImage(
                imageUrl: widget.music.coverUrl,
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.3),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
        // 底部暗角
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
      child: Column(
        children: [
          const Spacer(flex: 1),
          // 封面
          _buildCover(),
          const SizedBox(height: 40),
          // 歌曲信息
          _buildSongInfo(),
          const Spacer(flex: 2),
          // 迷你播放控制
          _buildMiniControls(context),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCover() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey(widget.music.id),
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (widget.dominantColor ?? Colors.pink).withValues(alpha: 0.4),
              blurRadius: 40,
              spreadRadius: 5,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: widget.music.coverUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: widget.music.coverUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: 80,
                    ),
                  ),
                )
              : Container(
                  color: Colors.grey[800],
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSongInfo() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: Padding(
        key: ValueKey('${widget.music.id}_info'),
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            Text(
              widget.music.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              widget.music.artist,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // 进度条
          _buildProgressBar(context),
          const SizedBox(height: 16),
          // 控制按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 收藏
              IconButton(
                icon: Icon(
                  sl.playerManager.isFavorite(widget.music)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: sl.playerManager.isFavorite(widget.music)
                      ? Colors.red[400]
                      : Colors.white,
                ),
                iconSize: 28,
                onPressed: widget.onToggleFavorite,
              ),
              // 播放/暂停
              GestureDetector(
                onTap: widget.onTogglePlay,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white,
                        Colors.white.withValues(alpha: 0.9),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.black,
                    size: 36,
                  ),
                ),
              ),
              // 歌词切换
              IconButton(
                icon: Icon(Icons.lyrics_outlined, color: Colors.white),
                iconSize: 28,
                onPressed: widget.onToggleShowLyrics,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 底部操作栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 24,
                onPressed: widget.onTogglePlayMode,
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_previous,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 32,
                onPressed: () => sl.playerManager.playPrevious(),
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_next,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 32,
                onPressed: () => sl.playerManager.playNext(),
              ),
              IconButton(
                icon: Icon(
                  Icons.share_outlined,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 24,
                onPressed: widget.onShare,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final progress = widget.duration != null && widget.duration!.inSeconds > 0
        ? widget.position.inSeconds / widget.duration!.inSeconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              if (widget.duration != null) {
                widget.onSeek(
                  Duration(seconds: (value * widget.duration!.inSeconds).toInt()),
                );
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(widget.position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              if (widget.isTransitioning)
                TransitionGlowIndicator(
                  isVisible: widget.isTransitioning,
                  child: const Text(
                    '过渡中',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Text(
                  _formatDuration(widget.duration ?? Duration.zero),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsView(BuildContext context) {
    // 将 LyricInfo 转换为 LyricSource
    final lyricSources = widget.lyricOptions.map((option) {
      return LyricSource(id: option.id, name: option.name);
    }).toList();

    return LyricSection(
      lyricParser: widget.lyricParser,
      position: widget.position,
      lyricSources: lyricSources,
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
      builder: (context) => Container(
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
                sl.playerManager.isFavorite(widget.music)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: sl.playerManager.isFavorite(widget.music)
                    ? Colors.red
                    : Colors.white,
              ),
              title: Text(
                sl.playerManager.isFavorite(widget.music) ? '取消收藏' : '收藏',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onToggleFavorite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('分享', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                widget.onShare();
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: Colors.white),
              title: const Text(
                '添加到播放列表',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: 添加到播放列表
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
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
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('标题', widget.music.title),
            _infoRow('艺术家', widget.music.artist),
            _infoRow('专辑', widget.music.album),
            _infoRow('时长', _formatDuration(widget.duration ?? Duration.zero)),
            _infoRow('来源', 'Bilibili'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
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

/// 歌词信息类（用于竖屏模式）
class LyricInfo {
  final String id;
  final String name;
  final String artist;

  LyricInfo({required this.id, required this.name, required this.artist});

  @override
  String toString() {
    return '$name - $artist';
  }
}
