import 'package:flutter/material.dart';
import 'package:bilimusic/models/search_result.dart';
import 'package:bilimusic/models/music.dart' as music_model;
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/services/search_service.dart';
import 'package:bilimusic/pages/search/widgets/search_type_tabs.dart';
import 'package:bilimusic/pages/search/widgets/search_empty_state.dart';
import 'package:bilimusic/components/common/cards/music_list_item.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/animations.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';
import 'package:rxdart/rxdart.dart';

/// 搜索结果Overlay - 接收搜索关键词，展示搜索结果
class SearchResultsOverlay extends StatefulWidget {
  final String query;

  const SearchResultsOverlay({super.key, required this.query});

  @override
  State<SearchResultsOverlay> createState() => _SearchResultsOverlayState();
}

class _SearchResultsOverlayState extends State<SearchResultsOverlay> {
  final SearchService _searchService = SearchService();

  // 搜索状态
  List<SearchResult> _allResults = [];
  List<SearchResult> _filteredResults = [];
  SearchResultType _selectedType = SearchResultType.video;
  List<SearchResultType> _availableTypes = [];
  bool _isLoading = false;
  String? _errorMessage;

  // 分P加载状态
  final Map<String, bool> _pagesLoading = {};
  final Map<String, List<music_model.Page>> _pagesCache = {};
  bool _isPagesLoading = false;

  // 防抖
  final _searchSubject = BehaviorSubject<String>();

  static const double _sectionSpacing = 24.0;
  static const double _cardSpacing = 12.0;
  static const double _horizontalPadding = 16.0;

  @override
  void initState() {
    super.initState();
    _searchSubject
        .debounceTime(const Duration(milliseconds: 300))
        .listen(_performSearch);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performSearch(widget.query);
    });
  }

  @override
  void dispose() {
    _searchSubject.close();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _allResults = [];
        _filteredResults = [];
        _availableTypes = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
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

    if (response.results.isNotEmpty) {
      _fetchAllPagesWithDelay(response.results);
    }
  }

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
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            ShellPageManager.instance.pop();
          }
        },
        child: CustomScrollView(
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
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, ScreenSize screenSize) {
    if (screenSize == ScreenSize.desktop) {
      return SliverAppBar(
        backgroundColor: Colors.transparent,
        floating: true,
        snap: true,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
              onPressed: () => ShellPageManager.instance.pop(),
            ),
            Expanded(
              child: Text(
                '搜索: ${widget.query}',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
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
        backgroundColor: Colors.transparent,
        floating: true,
        snap: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => ShellPageManager.instance.pop(),
        ),
        title: Text(
          '搜索: ${widget.query}',
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
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

  Widget _buildInitialContent(BuildContext context, ScreenSize screenSize) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(
        type: EmptyStateType.initial,
        suggestions: const ['周杰伦', '林俊杰', '五月天', '陈奕迅', '邓紫棋'],
      ),
    );
  }

  Widget _buildLoadingContent() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(type: EmptyStateType.loading),
    );
  }

  Widget _buildEmptyContent() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(
        type: _errorMessage == null
            ? EmptyStateType.initial
            : EmptyStateType.noResults,
        customMessage: _errorMessage ?? '没有找到相关结果',
      ),
    );
  }

  Widget _buildResultsContent(BuildContext context, ScreenSize screenSize) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final spacing = isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2;

    final multiPartResults = <SearchResult>[];
    final singlePartResults = <SearchResult>[];

    for (final result in _filteredResults) {
      if (result.type != SearchResultType.video) {
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
          if (multiPartResults.isNotEmpty) ...[
            _buildMultiPartList(context, multiPartResults, screenSize),
            const SizedBox(height: _cardSpacing * 2),
          ],
          Text(
            '单曲 (${singlePartResults.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: _cardSpacing),
          ...singlePartResults.map(
            (result) => _buildResultItem(context, result, screenSize),
          ),
          const SizedBox(height: 120),
        ]),
      ),
    );
  }

  Widget _buildMultiPartList(
    BuildContext context,
    List<SearchResult> results,
    ScreenSize screenSize,
  ) {
    final isDesktop = screenSize == ScreenSize.desktop;

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
        ...results.map((result) {
          final pages = _pagesCache[result.id] ?? [];
          return Padding(
            padding: EdgeInsets.only(bottom: _cardSpacing),
            child: FadeInWidget(
              duration: const Duration(milliseconds: 400),
              child: _buildMultiPartListItem(context, result, pages),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResultItem(
    BuildContext context,
    SearchResult result,
    ScreenSize screenSize,
  ) {
    final pages = _pagesCache[result.id] ?? [];
    final isLoading = _pagesLoading[result.id] == true;

    if (result.type != SearchResultType.video || (isLoading && pages.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _cardSpacing),
        child: _SearchResultCard(
          result: result,
          playerManager: sl.playerManager,
          playlistManager: sl.playlistManager,
          onTap: () => _playResult(result),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: _cardSpacing),
      child: _buildListItem(context, result),
    );
  }

  Widget _buildMultiPartListItem(
    BuildContext context,
    SearchResult result,
    List<music_model.Page> pages,
  ) {
    final music = result.toMusic(pages: pages);

    return MusicListItem(
      music: music,
      playerManager: sl.playerManager,
      playlistManager: sl.playlistManager,
      onTap: () => _navigateToPlaylist(result, pages),
      showCover: true,
      showDetails: true,
      showPageIndicator: true,
    );
  }

  Widget _buildListItem(BuildContext context, SearchResult result) {
    return MusicListItem(
      music: result.toMusic(),
      playerManager: sl.playerManager,
      playlistManager: sl.playlistManager,
      onTap: () => _playResult(result),
    );
  }

  void _navigateToPlaylist(SearchResult result, List<music_model.Page> pages) {
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

    ShellPageManager.instance.goToPlaylist(
      playlistId: 'search_${result.id}',
      songs: songs,
      playlistName: result.title,
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

/// 简化版搜索结果卡片（用于搜索结果页）
class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final dynamic playerManager;
  final dynamic playlistManager;
  final VoidCallback? onTap;

  const _SearchResultCard({
    required this.result,
    required this.playerManager,
    required this.playlistManager,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          result.coverUrl.isNotEmpty
              ? result.coverUrl
              : 'https://i0.hdslb.com/bfs/static/jinkela/video/asserts/no_video.png',
          width: 56,
          height: 56,
          fit: BoxFit.cover,
        ),
      ),
      title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        result.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline),
        onPressed: onTap,
      ),
      onTap: onTap,
    );
  }
}
