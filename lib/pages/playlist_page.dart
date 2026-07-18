import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/pages/playlist/portrait_playlist_page.dart';
import 'package:bilimusic/pages/playlist/landscape_playlist_page.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';

/// 播放列表页面
/// 根据屏幕方向路由到竖屏或横屏布局
class PlaylistPage extends ConsumerStatefulWidget {
  final String? playlistId;
  final List<Music>? songs;
  final String? playlistName;
  final VoidCallback? onBack;

  const PlaylistPage({
    super.key,
    this.playlistId,
    this.songs,
    this.playlistName,
    this.onBack,
  });

  @override
  ConsumerState<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends ConsumerState<PlaylistPage> {
  // 状态
  List<Music> _songs = [];
  bool _isLoading = true;
  bool _isFavorited = false;
  Playlist? _currentPlaylist;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  /// 加载数据
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.songs != null) {
        _songs = List.from(widget.songs!);
        // 为特殊播放列表创建临时歌单对象用于显示
        _currentPlaylist = _createTempPlaylist(
          _songs,
          name: widget.playlistName,
        );
      } else if (widget.playlistId != null) {
        // 从管理器加载歌单详情
        final detail = await ref
            .read(playlistManagerProvider)
            .getPlaylistDetail(widget.playlistId!);
        if (detail != null) {
          _currentPlaylist = detail;
          _songs = detail.songs;
        }
      }

      // 检查是否已收藏
      if (_songs.isNotEmpty) {
        _isFavorited = ref.read(playlistManagerProvider).isFavorite(_songs.first);
      }
    } catch (e) {
      debugPrint('Failed to load playlist data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 为特殊播放列表创建临时歌单对象
  Playlist _createTempPlaylist(List<Music> songs, {String? name}) {
    // 尝试根据 songs 内容推断歌单类型
    String displayName = name ?? '播放列表';
    PlaylistSource source = PlaylistSource.user;

    final favorites = ref.read(favoritesProvider);
    final history = ref.read(playHistoryProvider);

    if (displayName == '播放列表') {
      if (favorites.isNotEmpty && _isSameList(songs, favorites)) {
        displayName = '我的收藏';
        source = PlaylistSource.system;
      } else if (history.isNotEmpty && _isSameList(songs, history)) {
        displayName = '播放历史';
        source = PlaylistSource.system;
      }
    }

    return Playlist(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: displayName,
      source: source,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      songs: songs,
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

    final commands = ref.read(playbackCommandsProvider.notifier);
    await commands.clearPlaylist();
    await commands.addAllToPlaylist(_songs);

    if (_songs.isNotEmpty) {
      await commands.playMusic(_songs.first);
    }
  }

  /// 随机播放
  Future<void> _shufflePlay() async {
    if (_songs.isEmpty) return;

    final shuffledSongs = List<Music>.from(_songs)..shuffle(Random());
    final commands = ref.read(playbackCommandsProvider.notifier);

    await commands.clearPlaylist();
    await commands.addAllToPlaylist(shuffledSongs);

    if (shuffledSongs.isNotEmpty) {
      await commands.playMusic(shuffledSongs.first);
    }
  }

  /// 收藏/取消收藏
  Future<void> _toggleFavorite() async {
    if (_songs.isEmpty) return;

    final music = _songs.first;
    final newState = await ref.read(playlistManagerProvider).toggleFavorite(music);

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
    final commands = ref.read(playbackCommandsProvider.notifier);
    await commands.addToPlaylist(music);
    await commands.playMusic(music);
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
      await ref.read(playlistManagerProvider).removeSongsFromPlaylist(
        widget.playlistId!,
        [music],
      );
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 检测是否为横屏模式
    final isLandscape = LandscapeBreakpoints.isLandscapeMode(context);

    // 横屏模式：使用横屏布局
    if (isLandscape) {
      return LandscapePlaylistPage(
        playlistId: widget.playlistId,
        songs: _songs,
        currentPlaylist: _currentPlaylist,
        isFavorited: _isFavorited,
        onBack: widget.onBack ?? () => ShellPageManager.instance.pop(),
        onSongTap: _playSong,
        onRemoveSong: _removeSong,
        onPlayAll: _playAll,
        onShufflePlay: _shufflePlay,
        onToggleFavorite: _toggleFavorite,
      );
    }

    // 竖屏模式：使用竖屏布局
    return PortraitPlaylistPage(
      playlistId: widget.playlistId,
      songs: _songs,
      currentPlaylist: _currentPlaylist,
      isFavorited: _isFavorited,
      onBack: widget.onBack ?? () => ShellPageManager.instance.pop(),
      onSongTap: _playSong,
      onRemoveSong: _removeSong,
      onPlayAll: _playAll,
      onShufflePlay: _shufflePlay,
      onToggleFavorite: _toggleFavorite,
    );
  }
}
