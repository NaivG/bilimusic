import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/providers/playlist_manager_provider.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/responsive.dart';

/// 横屏播放列表页面
/// Apple Music 风格的左右分栏布局
class LandscapePlaylistPage extends StatefulWidget {
  final String? playlistId;
  final List<Music>? songs;
  final PlayerManager playerManager;
  final PlaylistManager? playlistManager;
  final VoidCallback? onBack;

  const LandscapePlaylistPage({
    super.key,
    this.playlistId,
    this.songs,
    required this.playerManager,
    this.playlistManager,
    this.onBack,
  });

  @override
  State<LandscapePlaylistPage> createState() => _LandscapePlaylistPageState();
}

class _LandscapePlaylistPageState extends State<LandscapePlaylistPage>
    with SingleTickerProviderStateMixin {
  late PlaylistManager _playlistManager;

  // 状态
  List<Music> _songs = [];
  bool _isLoading = true;
  bool _isFavorited = false;
  Playlist? _currentPlaylist;

  // 动画控制器
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlistManager = PlaylistManagerProvider.of(context);
    _loadData();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.songs != null) {
        _songs = List.from(widget.songs!);
        _currentPlaylist = _createTempPlaylist(_songs);
      } else if (widget.playlistId != null) {
        final detail = await _playlistManager.getPlaylistDetail(
          widget.playlistId!,
        );
        if (detail != null) {
          _currentPlaylist = detail;
          _songs = detail.songs;
        }
      }

      // 检查是否已收藏
      if (_songs.isNotEmpty) {
        _isFavorited = _playlistManager.isFavorite(_songs.first);
      }
    } catch (e) {
      debugPrint('Failed to load playlist data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Playlist _createTempPlaylist(List<Music> songs) {
    String name = '播放列表';
    PlaylistSource source = PlaylistSource.user;

    final favorites = widget.playerManager.favorites;
    final history = widget.playerManager.playHistory;

    if (favorites.isNotEmpty && _isSameList(songs, favorites)) {
      name = '我的收藏';
      source = PlaylistSource.system;
    } else if (history.isNotEmpty && _isSameList(songs, history)) {
      name = '播放历史';
      source = PlaylistSource.system;
    }

    return Playlist(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      source: source,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  bool _isSameList(List<Music> a, List<Music> b) {
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    final compareCount = a.length < 5 ? a.length : 5;
    for (int i = 0; i < compareCount; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _playAll() async {
    if (_songs.isEmpty) return;
    await widget.playerManager.clearPlayList();
    await widget.playerManager.addAllToPlayList(_songs);
    if (_songs.isNotEmpty) {
      await widget.playerManager.play(_songs.first);
    }
  }

  Future<void> _shufflePlay() async {
    if (_songs.isEmpty) return;
    final shuffledSongs = List<Music>.from(_songs)..shuffle(Random());
    await widget.playerManager.clearPlayList();
    await widget.playerManager.addAllToPlayList(shuffledSongs);
    if (shuffledSongs.isNotEmpty) {
      await widget.playerManager.play(shuffledSongs.first);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_songs.isEmpty) return;
    final music = _songs.first;
    final newState = await _playlistManager.toggleFavorite(music);
    setState(() {
      _isFavorited = newState;
    });
  }

  Future<void> _playSong(Music music) async {
    await widget.playerManager.addToPlayList(music);
    await widget.playerManager.play(music);
  }

  void _showSongOptions(BuildContext context, Music music) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => LongPressMenu(
        music: music,
        playerManager: widget.playerManager,
        playlistManager: widget.playlistManager,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
              Colors.black,
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // 顶部导航栏
              _buildAppBar(context),
              // 主内容区
              Expanded(
                child: Row(
                  children: [
                    // 左侧歌单信息区域
                    Expanded(flex: 1, child: _buildLeftSection(context)),
                    // 右侧歌曲列表
                    Expanded(flex: 1, child: _buildRightSection(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(
          horizontal: LandscapeBreakpoints.getHorizontalPadding(context) / 2,
        ),
        child: Row(
          children: [
            // 返回按钮
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
              onPressed: widget.onBack ?? () => Navigator.pop(context),
            ),
            const Spacer(),
            // 标题
            Text(
              _currentPlaylist?.displayName ?? '播放列表',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // 更多按钮
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
              onPressed: () => _showPlaylistOptions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftSection(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        LandscapeBreakpoints.getHorizontalPadding(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // 歌单封面
          _buildCover(context),
          const SizedBox(height: 24),
          // 歌单信息
          _buildPlaylistInfo(context),
          const SizedBox(height: 24),
          // 标签
          if (_currentPlaylist?.tagIds.isNotEmpty ?? false) ...[
            _buildTags(context),
            const SizedBox(height: 24),
          ],
          // 操作按钮
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final coverSize = LandscapeBreakpoints.getCoverSize(context);
    final coverUrl = _currentPlaylist?.safeCoverUrl ?? '';
    final systemIcon = _currentPlaylist?.systemPlaylistIcon;
    final systemIconColor = _currentPlaylist?.systemPlaylistIconColor;

    return Hero(
      tag: 'playlist_cover_${_currentPlaylist?.id ?? "temp"}',
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxWidth: coverSize, maxHeight: coverSize),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 系统歌单显示特殊图标
              if (systemIcon != null)
                Container(
                  color: systemIconColor?.withValues(alpha: 0.15),
                  child: Center(
                    child: Icon(
                      systemIcon,
                      size: coverSize * 0.4,
                      color: systemIconColor ?? Colors.grey,
                    ),
                  ),
                )
              // 如果有封面URL，显示图片；否则显示图标
              else if (coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: coverUrl,
                  httpHeaders: NetworkConfig.biliHeaders,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.music_note,
                      size: 64,
                      color: Colors.white54,
                    ),
                  ),
                  fit: BoxFit.cover,
                  cacheManager: imageCacheManager,
                )
              else
                Container(
                  color: Colors.grey[800],
                  child: const Icon(
                    Icons.music_note,
                    size: 64,
                    color: Colors.white54,
                  ),
                ),
              // 歌曲数量
              if (_songs.isNotEmpty)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_songs.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _currentPlaylist?.displayName ?? '播放列表',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          _buildInfoText(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
        if (_currentPlaylist?.hasDescription ?? false) ...[
          const SizedBox(height: 12),
          Text(
            _currentPlaylist!.description!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              height: 1.5,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  String _buildInfoText() {
    final parts = <String>[];
    parts.add('${_songs.length}首歌曲');
    if (_currentPlaylist?.formattedDuration.isNotEmpty ?? false) {
      parts.add(_currentPlaylist!.formattedDuration);
    }
    return parts.join(' · ');
  }

  Widget _buildTags(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _currentPlaylist!.tagIds.map((tagId) {
        final tag = DefaultPlaylistTags.getById(tagId);
        if (tag == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: tag.color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tag.color.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tag.icon, size: 14, color: tag.color),
              const SizedBox(width: 4),
              Text(
                tag.nameCn,
                style: TextStyle(
                  color: tag.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 900;

    if (isNarrow) {
      // 窄屏：按钮垂直排列
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPlayButton(context, isPrimary: true),
          const SizedBox(height: 12),
          _buildShuffleButton(context),
          const SizedBox(height: 12),
          _buildFavoriteButton(context),
        ],
      );
    } else {
      // 宽屏：按钮水平排列
      return Row(
        children: [
          Expanded(flex: 2, child: _buildPlayButton(context, isPrimary: true)),
          const SizedBox(width: 12),
          Expanded(child: _buildShuffleButton(context)),
          const SizedBox(width: 12),
          _buildFavoriteButton(context),
        ],
      );
    }
  }

  Widget _buildPlayButton(BuildContext context, {required bool isPrimary}) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _songs.isNotEmpty ? _playAll : null,
        icon: const Icon(Icons.play_arrow, size: 22),
        label: const Text(
          '播放全部',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildShuffleButton(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _songs.length > 1 ? _shufflePlay : null,
        icon: const Icon(Icons.shuffle, size: 20),
        label: const Text('随机播放', style: TextStyle(fontSize: 14)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteButton(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        onPressed: _toggleFavorite,
        icon: Icon(
          _isFavorited ? Icons.favorite : Icons.favorite_border,
          color: _isFavorited ? Colors.red[400] : Colors.white,
        ),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  Widget _buildRightSection(BuildContext context) {
    final horizontalPadding = LandscapeBreakpoints.getHorizontalPadding(
      context,
    );

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // 列表头部
          _buildListHeader(context, horizontalPadding),
          // 歌曲列表
          Expanded(
            child: _songs.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding / 2,
                      vertical: 8,
                    ),
                    itemCount: _songs.length,
                    itemExtent: 72,
                    itemBuilder: (context, index) {
                      final music = _songs[index];
                      final isPlaying = _isCurrentPlaying(music);
                      return _LandscapeSongTile(
                        music: music,
                        index: index,
                        isPlaying: isPlaying,
                        onTap: () => _playSong(music),
                        onLongPress: () => _showSongOptions(context, music),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context, double horizontalPadding) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding / 2,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '歌曲列表',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_songs.length}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_off,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '歌单为空',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  bool _isCurrentPlaying(Music music) {
    final currentMusic = widget.playerManager.currentMusic;
    if (currentMusic == null) return false;
    return music.id == currentMusic.id &&
        (music.pages.isEmpty && currentMusic.pages.isEmpty ||
            music.pages.isNotEmpty &&
                currentMusic.pages.isNotEmpty &&
                music.pages[0].cid == currentMusic.pages[0].cid);
  }

  void _showPlaylistOptions(BuildContext context) {
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
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('分享歌单', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: const Text('编辑歌单', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.white),
              title: const Text('下载全部', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 横屏歌曲列表项
class _LandscapeSongTile extends StatelessWidget {
  final Music music;
  final int index;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LandscapeSongTile({
    required this.music,
    required this.index,
    required this.isPlaying,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isPlaying
          ? theme.colorScheme.primary.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // 序号/播放指示器
              SizedBox(width: 32, child: _buildIndex(context)),
              const SizedBox(width: 8),
              // 封面
              _buildCover(context),
              const SizedBox(width: 12),
              // 歌曲信息
              Expanded(child: _buildInfo(context)),
              // 操作按钮
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndex(BuildContext context) {
    if (isPlaying) {
      return const _PlayingIndicator();
    }
    return Text(
      '${index + 1}',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCover(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: music.safeCoverUrl,
            httpHeaders: NetworkConfig.biliHeaders,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                Container(width: 48, height: 48, color: Colors.grey[800]),
            errorWidget: (context, url, error) => Container(
              width: 48,
              height: 48,
              color: Colors.grey[800],
              child: const Icon(Icons.music_note, color: Colors.white54),
            ),
            cacheManager: imageCacheManager,
          ),
        ),
        if (isPlaying)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Colors.black38,
              ),
              child: const Icon(Icons.equalizer, color: Colors.white, size: 20),
            ),
          ),
      ],
    );
  }

  Widget _buildInfo(BuildContext context) {
    final textColor = isPlaying
        ? Colors.white
        : Colors.white.withValues(alpha: 0.9);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (music.isFavorite)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.favorite,
                  size: 12,
                  color: Colors.red[400]!.withValues(alpha: 0.8),
                ),
              ),
            Expanded(
              child: Text(
                music.title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${music.artist} · ${music.album}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        color: Colors.white.withValues(alpha: 0.4),
        size: 20,
      ),
      onPressed: onLongPress,
    );
  }
}

/// 播放指示器
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator();

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 400 + index * 100),
        vsync: this,
      )..repeat(reverse: true);
    });
    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(controller);
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              width: 3,
              height: 12 * _animations[index].value,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}

/// 横屏歌曲操作底部表单
