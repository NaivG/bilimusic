import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/components/common/cards/music_card.dart';
import 'package:bilimusic/components/common/cards/playlist_card.dart';
import 'package:bilimusic/managers/recommendation_manager.dart';
import 'package:bilimusic/utils/color_infra.dart';

/// 横屏模式首页内容 - 基于ParticleMusic风格
class LandscapeHomeContent extends StatefulWidget {
  final List<Playlist> playlists;
  final String? selectedPlaylistId;
  final Function(String playlistId)? onPlaylistTap;

  const LandscapeHomeContent({
    super.key,
    required this.playlists,
    this.selectedPlaylistId,
    this.onPlaylistTap,
  });

  @override
  State<LandscapeHomeContent> createState() => _LandscapeHomeContentState();
}

class _LandscapeHomeContentState extends State<LandscapeHomeContent> {
  late RecommendationManager _recommendationManager;
  List<Music> _recommendationList = [];
  List<Music> _guessYouLikeList = [];
  bool _isLoading = false;
  Playlist? _dailyRecommendedPlaylist;

  @override
  void initState() {
    super.initState();
    _recommendationManager = RecommendationManager();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    await _recommendationManager.loadRecommendations();
    await _recommendationManager.updateGuessYouLike(
      sl.playerManager.playHistory,
    );
    setState(() {
      _recommendationList = _recommendationManager.recommendedList;
      _guessYouLikeList = _recommendationManager.guessYouLikeList;
      _dailyRecommendedPlaylist = _buildDailyRecommendedPlaylist();
      _isLoading = false;
    });
  }

  Playlist _buildDailyRecommendedPlaylist() {
    final base = DefaultPlaylists.recommended;
    return Playlist(
      id: base.id,
      name: base.name,
      description: base.description,
      coverUrl: _guessYouLikeList.isNotEmpty
          ? _guessYouLikeList.first.safeCoverUrl
          : '',
      songCount: _guessYouLikeList.isNotEmpty
          ? _guessYouLikeList.length
          : _recommendationList.length,
      source: base.source,
      isDefault: base.isDefault,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      songs: _guessYouLikeList.isNotEmpty
          ? _guessYouLikeList
          : _recommendationList,
    );
  }

  Future<void> _playMusic(Music music) async {
    final detailedMusic = await music.getVideoDetails();
    sl.playerManager.play(detailedMusic);
  }

  @override
  Widget build(BuildContext context) {
    final playHistory = sl.playerManager.playHistory;

    return Container(
      color: Colors.transparent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 歌单区域
            _buildPlaylistSection(context),
            const SizedBox(height: 24),

            // 官方推荐区域
            _buildRecommendationSection(context),
            const SizedBox(height: 24),

            // 历史记录区域
            _buildHistorySection(context, playHistory),

            // 底部留白（给播放器栏）
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: selectedItemColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '歌单',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 歌单卡片横向滚动
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount:
                widget.playlists.length + 3, // +3 for favorites, history, daily
            itemBuilder: (context, index) {
              if (index == 0) {
                final favorites = DefaultPlaylists.favorites
                  ..songs = sl.playlistManager.favorites;
                return PlaylistCard(
                  playlist: favorites,
                  width: 140,
                  height: 180,
                  onTap: () => widget.onPlaylistTap?.call('favorites'),
                );
              } else if (index == 1) {
                final history = DefaultPlaylists.history
                  ..songs = sl.playerManager.playHistory;
                return PlaylistCard(
                  playlist: history,
                  width: 140,
                  height: 180,
                  onTap: () => widget.onPlaylistTap?.call('history'),
                );
              } else if (index == 2) {
                return PlaylistCard(
                  playlist:
                      _dailyRecommendedPlaylist ?? DefaultPlaylists.recommended,
                  width: 140,
                  height: 180,
                  onTap: () => widget.onPlaylistTap?.call('recommended'),
                );
              } else {
                final playlist = widget.playlists[index - 3];
                return PlaylistCard(
                  playlist: playlist,
                  width: 140,
                  height: 180,
                  onTap: () => widget.onPlaylistTap?.call(playlist.id),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: selectedItemColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '官方推荐',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const Spacer(),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 双列ListView，每行两个音乐项
        SizedBox(
          height: 6 * 64.0, // 每条64px，6条完整内容
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: (_recommendationList.take(12).length / 2).ceil(),
            itemBuilder: (context, rowIndex) {
              final leftIndex = rowIndex * 2;
              final rightIndex = leftIndex + 1;
              final leftItem = _recommendationList[leftIndex];
              final rightItem = rightIndex < _recommendationList.length
                  ? _recommendationList[rightIndex]
                  : null;
              return Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: Row(
                  children: [
                    Expanded(child: _buildMusicListItem(leftItem)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: rightItem != null
                          ? _buildMusicListItem(rightItem)
                          : const SizedBox(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context, List<Music> playHistory) {
    final displayHistory = playHistory.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header (change title color to blue instead of neteaseRed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '历史记录',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 双列ListView，每行两个音乐项
        if (displayHistory.isEmpty)
          SizedBox(
            height: 64,
            child: _buildEmptyState('暂无播放历史', Icons.history_outlined),
          )
        else
          SizedBox(
            height: 6 * 64.0, // 每条64px，6条完整内容
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: (displayHistory.length / 2).ceil(),
              itemBuilder: (context, rowIndex) {
                final leftIndex = rowIndex * 2;
                final rightIndex = leftIndex + 1;
                final leftItem = displayHistory[leftIndex];
                final rightItem = rightIndex < displayHistory.length
                    ? displayHistory[rightIndex]
                    : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 0),
                  child: Row(
                    children: [
                      Expanded(child: _buildMusicListItem(leftItem)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: rightItem != null
                            ? _buildMusicListItem(rightItem)
                            : const SizedBox(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMusicListItem(Music music) {
    return MusicListItem(
      music: music,
      playerManager: sl.playerManager,
      playlistManager: sl.playlistManager,
      onTap: () => _playMusic(music),
      showCover: true,
      showDetails: true,
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      height: 64,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
