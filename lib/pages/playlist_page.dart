import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/components/long_press_menu.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/models/playlist_tag.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/providers/playlist_manager_provider.dart';
import 'package:bilimusic/utils/network_config.dart';
import 'package:bilimusic/managers/cache_manager.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/pages/playlist/portrait_playlist_page.dart';
import 'package:bilimusic/pages/playlist/landscape_playlist_page.dart';

/// 播放列表页面
/// 根据屏幕方向路由到竖屏或横屏布局
class PlaylistPage extends StatefulWidget {
  final String? playlistId;
  final List<Music>? songs;
  final PlayerManager playerManager;

  const PlaylistPage({
    super.key,
    this.playlistId,
    this.songs,
    required this.playerManager,
  });

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 状态
  List<Music> _songs = [];
  bool _isLoading = true;
  bool _isFavorited = false;
  Playlist? _currentPlaylist;
  List<Playlist> _userPlaylists = [];
  List<PlaylistTag> _allTags = [];
  String? _selectedTagId;

  // 歌单管理器
  late PlaylistManager _playlistManager;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playlistManager = PlaylistManagerProvider.of(context);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 加载数据
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.songs != null) {
        _songs = List.from(widget.songs!);
        // 为特殊播放列表创建临时歌单对象用于显示
        _currentPlaylist = _createTempPlaylist(_songs);
      } else if (widget.playlistId != null) {
        // 从管理器加载歌单详情
        final detail = await _playlistManager.getPlaylistDetail(
          widget.playlistId!,
        );
        if (detail != null) {
          _currentPlaylist = detail;
          _songs = detail.songs;
        }
      }

      // 获取用户歌单列表
      _userPlaylists = _playlistManager.userPlaylists;
      _allTags = _playlistManager.watchTags().value;

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

  /// 为特殊播放列表创建临时歌单对象
  Playlist _createTempPlaylist(List<Music> songs) {
    // 尝试根据 songs 内容推断歌单类型
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

  /// 比较两个歌曲列表是否相同（基于第一个可区分的歌曲）
  bool _isSameList(List<Music> a, List<Music> b) {
    if (a.length != b.length) return false;
    if (a.isEmpty) return true;
    // 比较前几个歌曲的ID
    final compareCount = a.length < 5 ? a.length : 5;
    for (int i = 0; i < compareCount; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// 播放全部
  Future<void> _playAll() async {
    if (_songs.isEmpty) return;

    await widget.playerManager.clearPlayList();
    await widget.playerManager.addAllToPlayList(_songs);

    if (_songs.isNotEmpty) {
      await widget.playerManager.play(_songs.first);
    }
  }

  /// 随机播放
  Future<void> _shufflePlay() async {
    if (_songs.isEmpty) return;

    final shuffledSongs = List<Music>.from(_songs)..shuffle(Random());

    await widget.playerManager.clearPlayList();
    await widget.playerManager.addAllToPlayList(shuffledSongs);

    if (shuffledSongs.isNotEmpty) {
      await widget.playerManager.play(shuffledSongs.first);
    }
  }

  /// 收藏/取消收藏
  Future<void> _toggleFavorite() async {
    if (_songs.isEmpty) return;

    final music = _songs.first;
    final newState = await _playlistManager.toggleFavorite(music);

    setState(() {
      _isFavorited = newState;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newState ? '已添加到收藏' : '已取消收藏'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 播放歌曲
  Future<void> _playSong(Music music) async {
    // 添加到播放列表
    await widget.playerManager.addToPlayList(music);
    await widget.playerManager.play(music);
  }

  /// 处理歌曲长按
  void _onSongLongPress(Music music) {
    _showSongOptions(context, music);
  }

  /// 显示歌曲选项
  void _showSongOptions(BuildContext context, Music music) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => LongPressMenu(
        music: music,
        playerManager: widget.playerManager,
        onRemoveFromPlaylist: widget.playlistId != null
            ? () async {
                Navigator.pop(context);
                await _removeSong(music);
              }
            : null,
      ),
    );
  }

  /// 从歌单移除歌曲
  Future<void> _removeSong(Music music) async {
    if (widget.playlistId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要从歌单中移除"${music.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _playlistManager.removeSongsFromPlaylist(widget.playlistId!, [
        music,
      ]);
      setState(() {
        _songs.remove(music);
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已从歌单中移除"${music.title}"')));
      }
    }
  }

  /// 创建新歌单
  Future<void> _createPlaylist() async {
    final nameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建歌单'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '歌单名称',
            hintText: '请输入歌单名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _playlistManager.createPlaylist(result);
      await _loadData();
    }
  }

  /// 标签筛选
  void _filterByTag(String tagId) {
    setState(() {
      _selectedTagId = tagId;
    });

    final filteredPlaylists = _playlistManager.filterPlaylistsByTag(tagId);
    if (filteredPlaylists.isNotEmpty) {
      _showFilteredPlaylists(filteredPlaylists);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该标签下暂无歌单')));
    }
  }

  void _showFilteredPlaylists(List<Playlist> playlists) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: playlist.safeCoverUrl,
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
            title: Text(playlist.name),
            subtitle: Text('${playlist.songCount}首'),
            onTap: () {
              Navigator.pop(context);
              // TODO: 导航到对应歌单
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 检测是否为横屏模式
    final isLandscape = LandscapeBreakpoints.isLandscapeMode(context);

    // 横屏模式：使用左右分栏布局
    if (isLandscape) {
      return LandscapePlaylistPage(
        playlistId: widget.playlistId,
        songs: _songs,
        playerManager: widget.playerManager,
        playlistManager: _playlistManager,
        onBack: () => Navigator.pop(context),
      );
    }

    // 竖屏模式：使用竖屏布局
    return PortraitPlaylistPage(
      playlistId: widget.playlistId,
      songs: _songs,
      playerManager: widget.playerManager,
      playlistManager: _playlistManager,
      currentPlaylist: _currentPlaylist,
      userPlaylists: _userPlaylists,
      allTags: _allTags,
      selectedTagId: _selectedTagId,
      isFavorited: _isFavorited,
      onBack: () => Navigator.pop(context),
      onSongTap: _playSong,
      onSongLongPress: _onSongLongPress,
      onRemoveSong: _removeSong,
      onPlayAll: _playAll,
      onShufflePlay: _shufflePlay,
      onToggleFavorite: _toggleFavorite,
      onFilterByTag: _filterByTag,
      onCreatePlaylist: _createPlaylist,
    );
  }
}
