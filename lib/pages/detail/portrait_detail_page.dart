import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/models/music.dart' as model;
import 'package:bilimusic/utils/lyric_parser.dart';

/// 竖屏详情页
class PortraitDetailPage extends StatelessWidget {
  final PlayerManager playerManager;
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
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleShowLyrics;
  final Function(String) onLoadLyric;
  final Function(Duration) onSeek;
  final VoidCallback onTogglePlayMode;

  const PortraitDetailPage({
    super.key,
    required this.playerManager,
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
    required this.onToggleFavorite,
    required this.onShare,
    required this.onTogglePlay,
    required this.onToggleShowLyrics,
    required this.onLoadLyric,
    required this.onSeek,
    required this.onTogglePlayMode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dominantColor?.withValues(alpha: 0.4) ?? Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          // 渐变背景
          _buildBackground(),
          // 主内容
          showLyrics ? _buildLyricsView(context) : _buildAlbumView(context),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
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
                dominantColor?.withValues(alpha: 0.8) ?? Colors.black,
                dominantColor?.withValues(alpha: 0.6) ?? Colors.grey[900]!,
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // 封面图片模糊背景
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
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (dominantColor ?? Colors.pink).withValues(alpha: 0.4),
            blurRadius: 40,
            spreadRadius: 5,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: music.coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: music.coverUrl,
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
    );
  }

  Widget _buildSongInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Text(
            music.title,
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
            music.artist,
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
                  playerManager.isFavorite(music)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: playerManager.isFavorite(music)
                      ? Colors.red[400]
                      : Colors.white,
                ),
                iconSize: 28,
                onPressed: onToggleFavorite,
              ),
              // 播放/暂停
              GestureDetector(
                onTap: onTogglePlay,
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
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.black,
                    size: 36,
                  ),
                ),
              ),
              // 歌词切换
              IconButton(
                icon: Icon(Icons.lyrics_outlined, color: Colors.white),
                iconSize: 28,
                onPressed: onToggleShowLyrics,
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
                onPressed: onTogglePlayMode,
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_previous,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 32,
                onPressed: () => playerManager.playPrevious(),
              ),
              IconButton(
                icon: Icon(
                  Icons.skip_next,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 32,
                onPressed: () => playerManager.playNext(),
              ),
              IconButton(
                icon: Icon(
                  Icons.share_outlined,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                iconSize: 24,
                onPressed: onShare,
              ),
            ],
          ),
        ],
      ),
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
              if (duration != null) {
                onSeek(
                  Duration(seconds: (value * duration!.inSeconds).toInt()),
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
                _formatDuration(position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                _formatDuration(duration ?? Duration.zero),
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
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 60),
          // 返回按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  onPressed: onToggleShowLyrics,
                ),
                const Spacer(),
              ],
            ),
          ),
          // 歌词来源选择
          if (!isLoadingLyrics)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButton<String>(
                  value: selectedLyricId,
                  dropdownColor: Colors.grey[900],
                  underline: const SizedBox(),
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                  items: lyricOptions.map((option) {
                    return DropdownMenuItem<String>(
                      value: option.id,
                      child: Text(option.name),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id != null) onLoadLyric(id);
                  },
                ),
              ),
            ),
          // 歌词内容
          Expanded(child: _buildLyricContent(context)),
        ],
      ),
    );
  }

  Widget _buildLyricContent(BuildContext context) {
    if (lyricParser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '选择歌词来源后显示歌词',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (lyricParser!.lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 16,
          ),
        ),
      );
    }

    final currentLine = lyricParser!.getCurrentLine(
      position.inMilliseconds / 1000,
    );

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: MediaQuery.of(context).size.height * 0.3,
      ),
      itemCount: lyricParser!.lines.length,
      itemBuilder: (context, index) {
        final line = lyricParser!.lines[index];
        final isCurrentLine = line == currentLine;

        return GestureDetector(
          onTap: () {
            onSeek(Duration(seconds: line.time.toInt()));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                fontSize: isCurrentLine ? 24 : 18,
                fontWeight: isCurrentLine ? FontWeight.w700 : FontWeight.w500,
                color: isCurrentLine
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              child: Text(line.content),
            ),
          ),
        );
      },
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
                playerManager.isFavorite(music)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: playerManager.isFavorite(music)
                    ? Colors.red
                    : Colors.white,
              ),
              title: Text(
                playerManager.isFavorite(music) ? '取消收藏' : '收藏',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                onToggleFavorite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('分享', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onShare();
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
            _infoRow('标题', music.title),
            _infoRow('艺术家', music.artist),
            _infoRow('专辑', music.album),
            _infoRow('时长', _formatDuration(duration ?? Duration.zero)),
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
