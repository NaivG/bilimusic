import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/managers/recommendation_manager.dart';
import 'package:bilimusic/components/common/cards/music_card.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/animations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Music> recommendedList = [];
  late RecommendationManager _recommendationManager;
  bool _isLoading = false;

  // 统一的间距常量 - 简约现代风格
  static const double _sectionSpacing = 32.0;
  static const double _cardSpacing = 16.0;
  static const double _titleBottomSpacing = 16.0;
  static const double _horizontalPadding = 16.0;

  @override
  void initState() {
    super.initState();
    _recommendationManager = sl.recommendationManager;

    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoading = true;
    });

    await _recommendationManager.loadRecommendations();
    setState(() {
      recommendedList = _recommendationManager.recommendedList;
      _isLoading = false;
    });

    // 更新猜你喜欢列表
    _updateGuessYouLike();
  }

  Future<void> _refreshRecommendations() async {
    setState(() {
      _isLoading = true;
    });

    await _recommendationManager.refreshRecommendations();
    setState(() {
      recommendedList = _recommendationManager.recommendedList;
      _isLoading = false;
    });
  }

  Future<void> _updateGuessYouLike() async {
    // 在后台更新猜你喜欢列表
    await _recommendationManager.updateGuessYouLike(
      sl.playerManager.playHistory,
    );
  }

  Future<void> _playMusic(Music music) async {
    // 获取视频详情
    final detailedMusic = await music.getVideoDetails();

    // 播放音乐
    sl.playerManager.play(detailedMusic);
  }

  Widget _buildMusicCard(Music music, {bool isPcMode = false}) {
    return ResponsiveMusicCard(
      music: music,
      playerManager: sl.playerManager,
      playlistManager: sl.playlistManager,
      onTap: () => _playMusic(music),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildResponsiveLayout(context);
  }

  // 响应式布局
  Widget _buildResponsiveLayout(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 应用栏
          _buildAppBar(context, screenSize),

          // 推荐音乐区域
          _buildRecommendationSection(context, screenSize),

          // 猜你喜欢区域
          _buildGuessYouLikeSection(context, screenSize),

          // 最近播放区域
          _buildRecentlyPlayedSection(context, screenSize),
        ],
      ),
    );
  }

  // 构建应用栏
  SliverAppBar _buildAppBar(BuildContext context, ScreenSize screenSize) {
    if (screenSize == ScreenSize.desktop) {
      return SliverAppBar(
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
              Navigator.pushNamed(context, '/search');
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
        title: Row(
          children: [
            Text(
              'BiliMusic',
              style: TextStyle(
                fontFamily: 'CabinSketch',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            kDebugMode
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
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
                : const SizedBox(width: 36),
          ],
        ),
        floating: true,
        snap: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.pushNamed(context, '/search');
            },
          ),
        ],
      );
    }
  }

  // 构建推荐音乐区域
  SliverPadding _buildRecommendationSection(
    BuildContext context,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;

    return SliverPadding(
      padding: EdgeInsets.all(
        isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 - 简约现代风格
            Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 0.0 : _horizontalPadding,
                isDesktop ? 0.0 : 16.0,
                isDesktop ? 0.0 : _horizontalPadding,
                _titleBottomSpacing,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FadeInWidget(
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      '推荐音乐',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (isDesktop)
                    TextButton(
                      onPressed: _isLoading ? null : _refreshRecommendations,
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('换一批'),
                    )
                  else
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      onPressed: _isLoading ? null : _refreshRecommendations,
                    ),
                ],
              ),
            ),

            // 内容
            if (recommendedList.isEmpty)
              FadeInWidget(
                duration: const Duration(milliseconds: 400),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: _sectionSpacing),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.music_off_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无推荐音乐',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (isDesktop)
              _buildDesktopGrid(recommendedList)
            else
              _buildMobileHorizontalList(recommendedList),
          ],
        ),
      ),
    );
  }

  // 构建猜你喜欢区域
  SliverPadding _buildGuessYouLikeSection(
    BuildContext context,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;

    return SliverPadding(
      padding: EdgeInsets.all(
        isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 - 简约现代风格
            Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 0.0 : _horizontalPadding,
                isDesktop ? 0.0 : 16.0,
                isDesktop ? 0.0 : _horizontalPadding,
                _titleBottomSpacing,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FadeInWidget(
                    delay: const Duration(milliseconds: 100),
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      '猜你喜欢',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Text(
                    '上次更新: ${_recommendationManager.lastGuessUpdated}',
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),

            // 内容
            if (_recommendationManager.guessYouLikeList.isEmpty)
              FadeInWidget(
                delay: const Duration(milliseconds: 100),
                duration: const Duration(milliseconds: 400),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: _sectionSpacing),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '暂无推荐',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (isDesktop)
              _buildDesktopGrid(_recommendationManager.guessYouLikeList)
            else
              _buildMobileHorizontalList(
                _recommendationManager.guessYouLikeList,
              ),
          ],
        ),
      ),
    );
  }

  // 构建最近播放区域
  SliverPadding _buildRecentlyPlayedSection(
    BuildContext context,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final playHistory = sl.playerManager.playHistory;
    final displayCount = playHistory.length > 10 ? 10 : playHistory.length;

    return SliverPadding(
      padding: EdgeInsets.all(
        isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2,
      ),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 - 简约现代风格
            Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 0.0 : _horizontalPadding,
                isDesktop ? 0.0 : 16.0,
                isDesktop ? 0.0 : _horizontalPadding,
                _titleBottomSpacing,
              ),
              child: FadeInWidget(
                delay: const Duration(milliseconds: 200),
                duration: const Duration(milliseconds: 400),
                child: Text(
                  '最近播放',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // 内容
            if (playHistory.isEmpty)
              FadeInWidget(
                delay: const Duration(milliseconds: 200),
                duration: const Duration(milliseconds: 400),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: _sectionSpacing),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '没有找到播放历史',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (isDesktop)
              _buildDesktopGrid(playHistory.take(displayCount).toList())
            else
              _buildMobileHorizontalList(
                playHistory.take(displayCount).toList(),
              ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  // 构建桌面端网格布局
  Widget _buildDesktopGrid(List<Music> musicList) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: ResponsiveHelper.responsiveGridColumns(context),
        crossAxisSpacing: 16,
        mainAxisSpacing: 20,
        childAspectRatio: 0.8,
      ),
      itemCount: musicList.length,
      itemBuilder: (context, index) {
        final music = musicList[index];
        return _buildMusicCard(music, isPcMode: true);
      },
    );
  }

  // 构建移动端水平列表
  Widget _buildMobileHorizontalList(List<Music> musicList) {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        scrollDirection: Axis.horizontal,
        itemCount: musicList.length,
        itemBuilder: (context, index) {
          final music = musicList[index];
          return _buildMusicCard(music, isPcMode: false);
        },
      ),
    );
  }
}
