import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/managers/player_manager.dart';
import 'package:bilimusic/managers/playlist_manager.dart';
import 'package:bilimusic/components/common/cards/music_card.dart';
import 'package:bilimusic/managers/recommendation_manager.dart';
import 'package:bilimusic/utils/responsive.dart';

/// 横屏模式首页内容 - 仿网易云音乐风格
class LandscapeHomeContent extends StatefulWidget {
  final PlayerManager playerManager;
  final PlaylistManager playlistManager;
  final List<Playlist> playlists;
  final String? selectedPlaylistId;
  final Function(String playlistId)? onPlaylistTap;

  const LandscapeHomeContent({
    super.key,
    required this.playerManager,
    required this.playlistManager,
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
  bool _isLoading = false;

  // 网易云音乐品牌红色
  static const Color neteaseRed = Color(0xFFEC407A);

  @override
  void initState() {
    super.initState();
    _recommendationManager = RecommendationManager();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    await _recommendationManager.loadRecommendations();
    setState(() {
      _recommendationList = _recommendationManager.recommendedList;
      _isLoading = false;
    });
  }

  Future<void> _playMusic(Music music) async {
    final detailedMusic = await music.getVideoDetails();
    widget.playerManager.play(detailedMusic);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final playHistory = widget.playerManager.playHistory;

    return Container(
      color: isDark ? const Color(0xFF1a1a1a) : const Color(0xFFFAFAFA),
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
    final theme = Theme.of(context);

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
                  color: neteaseRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '歌单',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 歌单卡片横向滚动
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount:
                widget.playlists.length + 2, // +2 for favorites and history
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildPlaylistCard(
                  context,
                  icon: Icons.favorite,
                  iconColor: Colors.red,
                  title: '我喜欢的音乐',
                  subtitle: '${widget.playlistManager.favorites.length}首',
                  isSelected: widget.selectedPlaylistId == 'favorites',
                  onTap: () => widget.onPlaylistTap?.call('favorites'),
                );
              } else if (index == 1) {
                return _buildPlaylistCard(
                  context,
                  icon: Icons.history,
                  iconColor: Colors.blue,
                  title: '最近播放',
                  subtitle: '${widget.playerManager.playHistory.length}首',
                  isSelected: widget.selectedPlaylistId == 'history',
                  onTap: () => widget.onPlaylistTap?.call('history'),
                );
              } else {
                final playlist = widget.playlists[index - 2];
                return _buildPlaylistCard(
                  context,
                  icon: Icons.queue_music,
                  iconColor: neteaseRed,
                  title: playlist.name,
                  subtitle: '${playlist.songCount}首',
                  isSelected: widget.selectedPlaylistId == playlist.id,
                  onTap: () => widget.onPlaylistTap?.call(playlist.id),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 120,
          decoration: BoxDecoration(
            color: isSelected
                ? neteaseRed.withValues(alpha: 0.1)
                : (isDark ? const Color(0xFF2a2a2a) : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(
                    color: neteaseRed.withValues(alpha: 0.3),
                    width: 1.5,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? neteaseRed
                        : theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationSection(BuildContext context) {
    final theme = Theme.of(context);

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
                  color: neteaseRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '官方推荐',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
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
        // 双列列表音乐
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildMusicGrid(_recommendationList),
        ),
      ],
    );
  }

  Widget _buildHistorySection(BuildContext context, List<Music> playHistory) {
    final theme = Theme.of(context);
    final displayHistory = playHistory.take(20).toList();

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
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 双列列表音乐
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: playHistory.isEmpty
              ? _buildEmptyState('暂无播放历史', Icons.history_outlined)
              : _buildMusicGrid(displayHistory),
        ),
      ],
    );
  }

  Widget _buildMusicGrid(List<Music> musicList) {
    if (musicList.isEmpty) {
      return _buildEmptyState('暂无音乐', Icons.music_off_outlined);
    }

    // 双列布局
    return Column(
      children: [
        for (int i = 0; i < musicList.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: _buildMusicListItem(musicList[i])),
                const SizedBox(width: 8),
                Expanded(
                  child: i + 1 < musicList.length
                      ? _buildMusicListItem(musicList[i + 1])
                      : const SizedBox(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMusicListItem(Music music) {
    return MusicListItem(
      music: music,
      playerManager: widget.playerManager,
      playlistManager: widget.playlistManager,
      onTap: () => _playMusic(music),
      showCover: true,
      showDetails: true,
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      height: 120,
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
