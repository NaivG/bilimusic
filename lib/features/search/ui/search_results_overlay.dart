import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/domain/music.dart' as music_model;
import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_type_tabs.dart';
import 'package:bilimusic/features/search/ui/search_empty_state.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/widgets/cards/music_list_item.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:bilimusic/shared/utils/animations.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/player/playback_providers.dart';

/// 搜索结果Overlay - 只消费 [searchResultsProvider] 展示结果。
///
/// 搜索请求由搜索页发起并写入 Provider。这里是纯视图：从分P歌单、UP 主页
/// 返回时页面 State 虽然会重建，但不会重新搜索，也不会丢掉分P缓存。
class SearchResultsOverlay extends ConsumerStatefulWidget {
  final String query;

  const SearchResultsOverlay({super.key, required this.query});

  @override
  ConsumerState<SearchResultsOverlay> createState() =>
      _SearchResultsOverlayState();
}

class _SearchResultsOverlayState extends ConsumerState<SearchResultsOverlay> {
  static const double _sectionSpacing = 24.0;
  static const double _cardSpacing = 12.0;
  static const double _horizontalPadding = 16.0;

  void _onTypeChanged(SearchResultType type) {
    ref.read(searchResultsProvider.notifier).selectType(type);
  }

  void _playResult(SearchResult result) {
    if (result.type != SearchResultType.video) return;
    // 分P已预取时直接携带 cid；缺失时 playMusic 内部经 ensureCid 补齐
    final pages = ref.read(searchResultsProvider).pages[result.id];
    ref
        .read(playbackCommandsProvider.notifier)
        .playMusic(result.toMusic(pages: pages));
  }

  void _openArtist(SearchResult result) {
    final artist = result.artist;
    if (!artist.hasMid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该用户缺少 mid，无法打开 UP 主主页')));
      return;
    }
    ShellPageManager.instance.goToArtist(
      up: UpProfile(mid: artist.mid, name: artist.name, face: artist.face),
    );
  }

  VoidCallback? _onResultTap(SearchResult result) {
    switch (result.type) {
      case SearchResultType.video:
        return () => _playResult(result);
      case SearchResultType.author:
      case SearchResultType.upuser:
        return () => _openArtist(result);
      case SearchResultType.album:
      case SearchResultType.bangumi:
      case SearchResultType.topic:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchResultsProvider);
    // 正常情况下搜索页在 push 前已经把 query 写进状态。这里兜一层：
    // 状态还没跟上时按加载中处理，避免旧结果短暂串到新关键词下。
    final queryMatches = search.query == widget.query;
    final selectedType = queryMatches
        ? search.selectedType
        : SearchResultType.video;
    final availableTypes = queryMatches
        ? search.availableTypes
        : const <SearchResultType>[];
    final results = queryMatches
        ? search.filteredResults
        : const <SearchResult>[];
    final isLoading = search.isLoading || !queryMatches;
    final hasSearched = queryMatches && search.hasSearched;
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
          // 返回搜索结果页时保留滚动位置（搜索状态本身已在 Provider 里）
          key: PageStorageKey<String>('searchResults:${widget.query}'),
          slivers: [
            _buildAppBar(
              context,
              screenSize,
              selectedType: selectedType,
              availableTypes: availableTypes,
            ),
            if (isLoading)
              _buildLoadingContent()
            else if (!hasSearched)
              _buildInitialContent()
            else if (results.isEmpty)
              _buildEmptyContent(search.errorMessage)
            else
              _buildResultsContent(
                context,
                screenSize,
                selectedType: selectedType,
                results: results,
                pages: search.pages,
                loadingPages: search.loadingPages,
              ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(
    BuildContext context,
    ScreenSize screenSize, {
    required SearchResultType selectedType,
    required List<SearchResultType> availableTypes,
  }) {
    // 横屏外壳的标题栏已提供返回入口，内页不再重复显示
    final isLandscape = LandscapeBreakpoints.shouldUseLandscapeLayout(context);

    if (screenSize == ScreenSize.desktop) {
      return SliverAppBar(
        backgroundColor: Colors.transparent,
        floating: true,
        snap: true,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            if (!isLandscape)
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
            if (availableTypes.isNotEmpty)
              SearchTypeDropdown(
                selectedType: selectedType,
                onTypeChanged: _onTypeChanged,
                availableTypes: availableTypes,
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
        automaticallyImplyLeading: false,
        leading: isLandscape
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                onPressed: () => ShellPageManager.instance.pop(),
              ),
        title: Text(
          '搜索: ${widget.query}',
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        bottom: availableTypes.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SearchTypeTabs(
                    selectedType: selectedType,
                    onTypeChanged: _onTypeChanged,
                    availableTypes: availableTypes,
                  ),
                ),
              )
            : null,
      );
    }
  }

  Widget _buildInitialContent() {
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

  Widget _buildEmptyContent(String? errorMessage) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: SearchEmptyState(
        type: EmptyStateType.noResults,
        customMessage: errorMessage ?? '没有找到相关结果',
      ),
    );
  }

  Widget _buildResultsContent(
    BuildContext context,
    ScreenSize screenSize, {
    required SearchResultType selectedType,
    required List<SearchResult> results,
    required Map<String, List<music_model.Page>> pages,
    required Set<String> loadingPages,
  }) {
    final isDesktop = screenSize == ScreenSize.desktop;
    final spacing = isDesktop ? _sectionSpacing / 2 : _cardSpacing / 2;

    final multiPartResults = <SearchResult>[];
    final singlePartResults = <SearchResult>[];

    for (final result in results) {
      if (result.type != SearchResultType.video) {
        singlePartResults.add(result);
      } else {
        final resultPages = pages[result.id] ?? const [];
        if (resultPages.length > 1) {
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
                    '找到 ${results.length} 个结果',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (!isDesktop)
                    Text(
                      '类型: ${_getTypeLabel(selectedType)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ),
          if (multiPartResults.isNotEmpty) ...[
            _buildMultiPartList(context, multiPartResults, pages, screenSize),
            const SizedBox(height: _cardSpacing * 2),
          ],
          Text(
            '${_getTypeLabel(selectedType)} (${singlePartResults.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: _cardSpacing),
          ...singlePartResults.map(
            (result) => _buildResultItem(
              context,
              result,
              pages[result.id],
              loading: loadingPages.contains(result.id),
            ),
          ),
          const SizedBox(height: 120),
        ]),
      ),
    );
  }

  Widget _buildMultiPartList(
    BuildContext context,
    List<SearchResult> results,
    Map<String, List<music_model.Page>> pages,
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
          final resultPages = pages[result.id] ?? const [];
          return Padding(
            padding: EdgeInsets.only(bottom: _cardSpacing),
            child: FadeInWidget(
              duration: const Duration(milliseconds: 400),
              child: _buildMultiPartListItem(context, result, resultPages),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResultItem(
    BuildContext context,
    SearchResult result,
    List<music_model.Page>? pages, {
    required bool loading,
  }) {
    if (result.type != SearchResultType.video ||
        (loading && (pages == null || pages.isEmpty))) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _cardSpacing),
        child: _SearchResultCard(result: result, onTap: _onResultTap(result)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: _cardSpacing),
      child: _buildListItem(context, result, pages),
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
      playerCoordinator: ref.read(playerCoordinatorProvider),
      commands: ref.read(playlistCommandsProvider.notifier),
      playlistService: ref.read(playlistServiceProvider),
      onTap: () => _navigateToPlaylist(result, pages),
      showCover: true,
      showDetails: true,
      showPageIndicator: true,
    );
  }

  Widget _buildListItem(
    BuildContext context,
    SearchResult result,
    List<music_model.Page>? pages,
  ) {
    return MusicListItem(
      music: result.toMusic(pages: pages),
      playerCoordinator: ref.read(playerCoordinatorProvider),
      commands: ref.read(playlistCommandsProvider.notifier),
      playlistService: ref.read(playlistServiceProvider),
      onTap: () => _playResult(result),
    );
  }

  void _navigateToPlaylist(SearchResult result, List<music_model.Page> pages) {
    final songs = pages.map<music_model.Music>((page) {
      return music_model.Music(
        id: result.id,
        cid: page.cid,
        title: page.part.isNotEmpty ? page.part : result.title,
        artist: result.artist,
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

/// 简化版搜索结果卡片（用于非视频结果，也用于视频分P尚未取回时的占位）
class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback? onTap;

  const _SearchResultCard({required this.result, this.onTap});

  bool get _isPerson =>
      result.type == SearchResultType.author ||
      result.type == SearchResultType.upuser;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildCover(context),
      title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        result.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: _isPerson
          ? const Icon(Icons.chevron_right)
          : result.type == SearchResultType.video
          ? IconButton(
              icon: const Icon(Icons.play_circle_outline),
              onPressed: onTap,
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildCover(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 48,
      height: 48,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_trailingIcon, size: 22, color: colorScheme.onSurfaceVariant),
    );

    final coverUrl = result.coverUrl.isNotEmpty
        ? result.coverUrl
        : (_isPerson ? '' : music_model.fallbackCoverUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_isPerson ? 24 : 8),
      child: coverUrl.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: coverUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              httpHeaders: NetworkConfig.biliHeaders,
              cacheManager: imageCacheManager,
              placeholder: (context, url) => fallback,
              errorWidget: (context, url, error) => fallback,
            ),
    );
  }

  IconData get _trailingIcon {
    switch (result.type) {
      case SearchResultType.video:
        return Icons.music_note;
      case SearchResultType.album:
        return Icons.album;
      case SearchResultType.author:
      case SearchResultType.upuser:
        return Icons.person;
      case SearchResultType.bangumi:
        return Icons.tv;
      case SearchResultType.topic:
        return Icons.tag;
    }
  }
}
