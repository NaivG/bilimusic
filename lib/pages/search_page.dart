import 'package:bilimusic/providers/search_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/models/search_result.dart';
import 'package:bilimusic/models/music.dart' as music_model;
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/services/search_service.dart';
import 'package:bilimusic/pages/search/widgets/search_bar_widget.dart';
import 'package:bilimusic/pages/search/widgets/search_type_tabs.dart';
import 'package:bilimusic/pages/search/widgets/search_result_card.dart';
import 'package:bilimusic/pages/search/widgets/search_empty_state.dart';
import 'package:bilimusic/components/common/cards/music_card.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:rxdart/rxdart.dart';

/// 搜索页 - 重构版本
class SearchPage extends StatefulWidget {
  final String? initialQuery; // 可选的初始搜索参数
  final String? pendingQuery; // 来自横屏搜索栏的待搜索词

  const SearchPage({super.key, this.initialQuery, this.pendingQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final SearchService _searchService = SearchService();

  // 搜索状态
  List<SearchResult> _allResults = [];
  List<SearchResult> _filteredResults = [];
  SearchResultType _selectedType = SearchResultType.video;
  List<SearchResultType> _availableTypes = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _currentQuery = '';

  // 分P加载状态
  final Map<String, bool> _pagesLoading = {};
  final Map<String, List<music_model.Page>> _pagesCache = {};
  bool _isPagesLoading = false;

  // 防抖
  final _searchSubject = BehaviorSubject<String>();

  // 统一间距
  static const double _sectionSpacing = 24.0;
  static const double _cardSpacing = 12.0;
  static const double _horizontalPadding = 16.0;

  @override
  void initState() {
    super.initState();

    // 防抖处理搜索
    _searchSubject
        .debounceTime(const Duration(milliseconds: 300))
        .listen(_performSearch);

    // 监听 SearchStateNotifier 的变化（兼容独立路由 /search）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSearchStateListener();
    });

    // 处理来自横屏搜索栏的待搜索词（优先级最高）
    if (widget.pendingQuery != null && widget.pendingQuery!.isNotEmpty) {
      _searchController.text = widget.pendingQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.pendingQuery!);
      });
    }
    // 如果有初始搜索参数且没有待搜索词，立即执行搜索
    else if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.initialQuery!);
      });
    }
  }

  void _setupSearchStateListener() {
    SearchStateNotifier.instance.addListener(_onSearchStateChanged);
  }

  void _onSearchStateChanged() {
    final searchState = SearchStateNotifier.instance;
    if (searchState.shouldSearch && searchState.query.isNotEmpty) {
      // 更新搜索框文字并执行搜索
      if (_searchController.text != searchState.query) {
        _searchController.text = searchState.query;
      }
      _performSearch(searchState.query).then((_) {
        // 搜索完成后标记已搜索
        searchState.markSearched();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchSubject.close();
    // 移除 SearchStateNotifier 监听器
    SearchStateNotifier.instance.removeListener(_onSearchStateChanged);
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _allResults = [];
        _filteredResults = [];
        _availableTypes = [];
        _currentQuery = '';
        _pagesCache.clear();
        _pagesLoading.clear();
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentQuery = query;
      _pagesCache.clear();
      _pagesLoading.clear();
    });

    final response = await _searchService.search(query);

    setState(() {
      _isLoading = false;
      if (response.results.isEmpty) {
        _errorMessage = '没有搜索到任何结果';
        _allResults = [];
        _filteredResults = [];
        _availableTypes = [];
      } else {
        _allResults = response.results;
        _availableTypes = _searchService.getAvailableTypes(response.results);
        _filterResults();
      }
    });

    // 搜索完成后，加载所有视频的分P信息
    if (response.results.isNotEmpty) {
      _fetchAllPagesWithDelay(response.results);
    }
  }

  // 延时加载所有视频的分P信息
  Future<void> _fetchAllPagesWithDelay(List<SearchResult> results) async {
    if (_isPagesLoading) return;
    _isPagesLoading = true;

    for (final result in results) {
      if (!mounted) break;
      if (result.type != SearchResultType.video) continue;
      if (_pagesCache.containsKey(result.id)) continue;
      if (_pagesLoading[result.id] == true) continue;

      setState(() => _pagesLoading[result.id] = true);

      try {
        final pages = await result.fetchPages();
        if (mounted) {
          setState(() {
            _pagesCache[result.id] = pages;
            _pagesLoading[result.id] = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _pagesLoading[result.id] = false);
        }
      }

      // 延时50ms避免请求过快
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _isPagesLoading = false;
  }

  void _filterResults() {
    setState(() {
      _filteredResults = _searchService.filterByType(
        _allResults,
        _selectedType,
      );
    });
  }

  void _onTypeChanged(SearchResultType type) {
    setState(() {
      _selectedType = type;
      _filterResults();
    });
  }

  void _onSearch(String query) {
    _searchSubject.add(query);
  }

  void _onClear() {
    setState(() {
      _allResults = [];
      _filteredResults = [];
      _availableTypes = [];
      _currentQuery = '';
    });
  }

  Future<void> _playResult(SearchResult result) async {
    if (result.type == SearchResultType.video) {
      final music = result.toMusic();
      final detailedMusic = await music.getVideoDetails();
      sl.playerManager.play(detailedMusic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, screenSize),
          if (_allResults.isEmpty && !_isLoading)
            _buildInitialContent(context, screenSize)
          else if (_isLoading)
            _buildLoadingContent()
          else if (_filteredResults.isEmpty)
            _buildEmptyContent()
          else
            _buildResultsContent(context, screenSize),
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
        title: Row(
          children: [
            Expanded(
              child: SearchBarWidget(
                controller: _searchController,
                onSearch: _onSearch,
                onClear: _onClear,
                hintText: '搜索音乐、视频、UP主...',
              ),
            ),
            const SizedBox(width: 12),
            SearchTypeDropdown(
              selectedType: _selectedType,
              onTypeChanged: _onTypeChanged,
            ),
          ],
        ),
        toolbarHeight: 64,
      );
    } else {
      return SliverAppBar(
        floating: true,
        snap: true,
        title: SearchBarWidget(
          controller: _searchController,
          onSearch: _onSearch,
          onClear: _onClear,
          autoFocus: true,
        ),
        bottom: _availableTypes.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SearchTypeTabs(
                    selectedType: _selectedType,
                    onTypeChanged: _onTypeChanged,
                    availableTypes: _availableTypes,
                  ),
                ),
              )
            : null,
      );
    }
  }

  // 构建初始内容（未搜索状态）
  Widget _buildInitialContent(BuildContext context, ScreenSize screenSize) {
    final suggestions = ['周杰伦', '林俊杰', '五月天', '陈奕迅', '邓紫棋'];

    return SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(
        type: EmptyStateType.initial,
        suggestions: suggestions,
      ),
    );
  }

  // 构建加载内容
  Widget _buildLoadingContent() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(type: EmptyStateType.loading),
    );
  }

  // 构建空内容
  Widget _buildEmptyContent() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(
        type: _currentQuery.isEmpty
            ? EmptyStateType.initial
            : EmptyStateType.noResults,
        customMessage: _errorMessage ?? '没有找到相关结果',
      ),
    );
  }

  // 构建搜索结果内容 - 混合布局
  Widget _buildResultsContent(BuildContext context, ScreenSize screenSize) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final spacing = isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2;

    // 分离多P和单P视频
    final multiPartResults = <SearchResult>[];
    final singlePartResults = <SearchResult>[];

    for (final result in _filteredResults) {
      if (result.type != SearchResultType.video) {
        // 非视频类型（专辑、UP主等）归为单P
        singlePartResults.add(result);
      } else {
        final pages = _pagesCache[result.id] ?? [];
        if (pages.length > 1) {
          multiPartResults.add(result);
        } else {
          singlePartResults.add(result);
        }
      }
    }

    return SliverPadding(
      padding: EdgeInsets.all(spacing),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // 搜索结果标题
          FadeInWidget(
            duration: const Duration(milliseconds: 400),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 0.0 : _horizontalPadding,
                isDesktop ? 0.0 : 8.0,
                isDesktop ? 0.0 : _horizontalPadding,
                _cardSpacing,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '找到 ${_filteredResults.length} 个结果',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isDesktop && _availableTypes.length > 1)
                    Text(
                      '类型: ${_getTypeLabel(_selectedType)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ),

          // 多P视频网格布局（紧凑排列）
          if (multiPartResults.isNotEmpty) ...[
            _buildMultiPartGrid(context, multiPartResults, screenSize),
            const SizedBox(height: _cardSpacing * 2),
          ],

          // 单P视频列表样式
          ...singlePartResults.map(
            (result) => _buildResultItem(context, result, screenSize),
          ),

          const SizedBox(height: 120), // 底部占位
        ]),
      ),
    );
  }

  // 构建多P视频网格布局（像首页一样紧凑排列）
  Widget _buildMultiPartGrid(
    BuildContext context,
    List<SearchResult> results,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final columns = ResponsiveHelper.responsiveGridColumns(context);
    final gridSpacing = ResponsiveHelper.responsiveSpacing(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 0.0 : _horizontalPadding,
          ),
          child: Text(
            '系列视频 (${results.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        const SizedBox(height: _cardSpacing),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: gridSpacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gridSpacing,
            mainAxisSpacing: gridSpacing,
            childAspectRatio: screenSize == ScreenSize.mobile ? 0.8 : 0.85,
          ),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final result = results[index];
            final pages = _pagesCache[result.id] ?? [];
            return FadeInWidget(
              duration: const Duration(milliseconds: 400),
              delay: Duration(milliseconds: (index % columns) * 50),
              child: _buildStackedCard(context, result, pages),
            );
          },
        ),
      ],
    );
  }

  // 根据类型选择卡片或列表样式
  Widget _buildResultItem(
    BuildContext context,
    SearchResult result,
    ScreenSize screenSize,
  ) {
    final pages = _pagesCache[result.id] ?? [];
    final isLoading = _pagesLoading[result.id] == true;

    // 非视频类型或单P视频，使用原有卡片样式
    if (result.type != SearchResultType.video || (isLoading && pages.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _cardSpacing),
        child: SearchResultCard(
          result: result,
          playerManager: sl.playerManager,
          playlistManager: sl.playlistManager,
          onTap: () => _playResult(result),
        ),
      );
    }

    // 单P视频：使用列表样式
    return Padding(
      padding: const EdgeInsets.only(bottom: _cardSpacing),
      child: _buildListItem(context, result),
    );
  }

  // 构建叠加卡片样式（多P视频）
  Widget _buildStackedCard(
    BuildContext context,
    SearchResult result,
    List<music_model.Page> pages,
  ) {
    final music = result.toMusic(pages: pages);

    return StackedMusicCard(
      music: music,
      playerManager: sl.playerManager,
      playlistManager: sl.playlistManager,
      onTap: () => _navigateToPlaylist(result, pages),
      showBadge: true,
    );
  }

  // 构建列表样式（单P视频）
  Widget _buildListItem(BuildContext context, SearchResult result) {
    return MusicListItem(
      music: result.toMusic(),
      playerManager: sl.playerManager,
      playlistManager: sl.playlistManager,
      onTap: () => _playResult(result),
    );
  }

  // 导航到Playlist页面展示所有分P
  void _navigateToPlaylist(SearchResult result, List<music_model.Page> pages) {
    // 将分P转换为Music列表，每个分P使用分P的名称、时长和cid
    final songs = pages.map<music_model.Music>((page) {
      return music_model.Music(
        id: result.id,
        cid: page.cid,
        title: page.part.isNotEmpty ? page.part : result.title,
        artist: result.subtitle.split(' - ').first,
        album: result.subtitle.split(' - ').last,
        coverUrl: result.coverUrl,
        duration: page.durationValue,
        audioUrl: '',
        pages: [page],
        currentPageIndex: 0,
      );
    }).toList();

    // 统一使用Shell导航
    ShellPageManager.instance.goToPlaylist(
      playlistId: 'search_${result.id}',
      songs: songs,
    );
  }

  String _getTypeLabel(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return '单曲';
      case SearchResultType.album:
        return '专辑';
      case SearchResultType.author:
        return 'UP主';
      case SearchResultType.bangumi:
        return '番剧';
      case SearchResultType.topic:
        return '话题';
      case SearchResultType.upuser:
        return '用户';
    }
  }
}
