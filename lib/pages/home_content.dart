import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/playlist.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/managers/recommendation_manager.dart';
import 'package:bilimusic/components/common/cards/playlist_card.dart';
import 'package:bilimusic/components/common/cards/music_list_item.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/theme/lucent_theme.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:bilimusic/providers/playback_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';

class HomeContent extends ConsumerStatefulWidget {
  final bool showAppBar;
  final String? appBarTitle;

  const HomeContent({super.key, this.showAppBar = false, this.appBarTitle});

  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<HomeContent> {
  List<Music> recommendedList = [];
  List<Music> guessYouLikeList = [];
  late RecommendationManager _recommendationManager;
  bool _isLoading = false;

  static const double _sectionSpacing = 32.0;
  static const double _cardSpacing = 16.0;
  static const double _titleBottomSpacing = 16.0;
  static const double _horizontalPadding = 16.0;

  @override
  void initState() {
    super.initState();
    _recommendationManager = ref.read(recommendationManagerProvider);

    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);

    await _recommendationManager.loadRecommendations();
    setState(() {
      recommendedList = _recommendationManager.recommendedList;
      _isLoading = false;
    });

    _updateGuessYouLike();
  }

  Future<void> _refreshRecommendations() async {
    setState(() => _isLoading = true);

    await _recommendationManager.refreshRecommendations();
    setState(() {
      recommendedList = _recommendationManager.recommendedList;
      _isLoading = false;
    });
  }

  Future<void> _updateGuessYouLike() async {
    await _recommendationManager.updateGuessYouLike(
      ref.read(playHistoryProvider),
      playlistService: ref.read(playlistServiceProvider),
    );
    setState(() {
      guessYouLikeList = _recommendationManager.guessYouLikeList;
    });
  }

  Playlist _buildDailyRecommendedPlaylist() {
    final base = DefaultPlaylists.recommended;
    return Playlist(
      id: base.id,
      name: base.name,
      description: base.description,
      coverUrl: guessYouLikeList.isNotEmpty
          ? guessYouLikeList.first.safeCoverUrl
          : (recommendedList.isNotEmpty
                ? recommendedList.first.safeCoverUrl
                : ''),
      songCount: guessYouLikeList.isNotEmpty
          ? guessYouLikeList.length
          : recommendedList.length,
      source: base.source,
      isDefault: base.isDefault,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      songs: guessYouLikeList.isNotEmpty ? guessYouLikeList : recommendedList,
    );
  }

  Future<void> _playMusic(Music music) async {
    final detailedMusic = await music.getVideoDetails();
    ref.read(playbackCommandsProvider.notifier).playMusic(detailedMusic);
  }

  Widget _buildMusicListItem(Music music, {bool showCover = false}) {
    return MusicListItem(
      music: music,
      playerCoordinator: ref.read(playerCoordinatorProvider),
      playlistManager: ref.read(playlistManagerProvider),
      onTap: () => _playMusic(music),
      showCover: showCover,
      showDetails: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);

    Widget content = CustomScrollView(
      slivers: [
        if (widget.showAppBar) _buildAppBar(context, screenSize),
        _buildPlaylistSection(context, screenSize),
        _buildRecommendationSection(context, screenSize),
        _buildHistorySection(context, screenSize),
      ],
    );

    return Scaffold(backgroundColor: Colors.transparent, body: content);
  }

  SliverAppBar _buildAppBar(BuildContext context, ScreenSize screenSize) {
    if (screenSize == ScreenSize.desktop) {
      return SliverAppBar(
        backgroundColor: Colors.transparent,
        floating: true,
        snap: true,
        automaticallyImplyLeading: false,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: '搜索音乐、视频、用户...',
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onTap: () {
              ShellPageManager.instance.goToTab(1);
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshRecommendations,
          ),
        ],
      );
    } else {
      return SliverAppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Text(
              widget.appBarTitle ?? 'BiliMusic',
              style: const TextStyle(
                fontFamily: 'CabinSketch',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            if (kDebugMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Beta',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              )
            else
              const SizedBox(width: 36),
          ],
        ),
        floating: true,
        snap: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ShellPageManager.instance.goToTab(1);
            },
          ),
        ],
      );
    }
  }

  Widget _buildSectionHeader(String title, Color accentColor, bool isDesktop) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 0.0 : _horizontalPadding,
        isDesktop ? 0.0 : 16.0,
        isDesktop ? 0.0 : _horizontalPadding,
        _titleBottomSpacing,
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  SliverPadding _buildPlaylistSection(
    BuildContext context,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final selectedColor = LucentTokens.selectedItem(brightness);

    return SliverPadding(
      padding: EdgeInsets.all(
        isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('歌单', selectedColor, isDesktop),
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    PlaylistCard(
                      playlist: DefaultPlaylists.favorites
                        ..songs = ref.read(playlistManagerProvider).favorites,
                      onTap: () => ShellPageManager.instance.goToPlaylist(
                        playlistId: 'favorites',
                        songs: ref.read(playlistManagerProvider).favorites,
                      ),
                    ),
                    const SizedBox(width: 12),
                    PlaylistCard(
                      playlist: DefaultPlaylists.history
                        ..songs = ref.read(playHistoryProvider),
                      onTap: () => ShellPageManager.instance.goToPlaylist(
                        playlistId: 'history',
                        songs: ref.read(playHistoryProvider),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PlaylistCard(
                      playlist: _buildDailyRecommendedPlaylist(),
                      onTap: () => ShellPageManager.instance.goToPlaylist(
                        playlistId: 'recommended',
                        songs: guessYouLikeList.isNotEmpty
                            ? guessYouLikeList
                            : recommendedList,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverPadding _buildRecommendationSection(
    BuildContext context,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final displayList = recommendedList.isNotEmpty
        ? recommendedList.take(12).toList()
        : _recommendationManager.guessYouLikeList.take(12).toList();
    final brightness = View.of(context).platformDispatcher.platformBrightness;
    final selectedColor = LucentTokens.selectedItem(brightness);

    return SliverPadding(
      padding: EdgeInsets.all(
        isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('官方推荐', selectedColor, isDesktop),
            if (displayList.isEmpty)
              SizedBox(
                height: 64,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.music_off_outlined,
                        size: 32,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '暂无推荐',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              )
            else if (isDesktop)
              SizedBox(
                height: 6 * 64.0,
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: (displayList.length / 2).ceil(),
                  itemBuilder: (context, rowIndex) {
                    final leftIndex = rowIndex * 2;
                    final rightIndex = leftIndex + 1;
                    final leftItem = displayList[leftIndex];
                    final rightItem = rightIndex < displayList.length
                        ? displayList[rightIndex]
                        : null;
                    return Row(
                      children: [
                        Expanded(
                          child: _buildMusicListItem(leftItem, showCover: true),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: rightItem != null
                              ? _buildMusicListItem(rightItem, showCover: true)
                              : const SizedBox(),
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              SizedBox(
                height: 6 * 64.0,
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: displayList.take(6).length,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      height: 64.0,
                      child: _buildMusicListItem(
                        displayList[index],
                        showCover: true,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  SliverPadding _buildHistorySection(
    BuildContext context,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final playHistory = ref.watch(playHistoryProvider);
    final displayHistory = playHistory.take(12).toList();

    return SliverPadding(
      padding: EdgeInsets.all(
        isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 0.0 : _horizontalPadding,
                isDesktop ? 0.0 : 16.0,
                isDesktop ? 0.0 : _horizontalPadding,
                _titleBottomSpacing,
              ),
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (displayHistory.isEmpty)
              SizedBox(
                height: 64,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 32,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '暂无播放历史',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              )
            else if (isDesktop)
              SizedBox(
                height: 6 * 64.0,
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: (displayHistory.length / 2).ceil(),
                  itemBuilder: (context, rowIndex) {
                    final leftIndex = rowIndex * 2;
                    final rightIndex = leftIndex + 1;
                    final leftItem = displayHistory[leftIndex];
                    final rightItem = rightIndex < displayHistory.length
                        ? displayHistory[rightIndex]
                        : null;
                    return Row(
                      children: [
                        Expanded(
                          child: _buildMusicListItem(leftItem, showCover: true),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: rightItem != null
                              ? _buildMusicListItem(rightItem, showCover: true)
                              : const SizedBox(),
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              SizedBox(
                height: 6 * 64.0,
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: displayHistory.take(6).length,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      height: 64.0,
                      child: _buildMusicListItem(
                        displayHistory[index],
                        showCover: true,
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}
