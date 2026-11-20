import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/domain/music.dart' as music_model;
import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/features/search/search_providers.dart';
import 'package:bilimusic/features/search/ui/search_type_tabs.dart';
import 'package:bilimusic/features/search/ui/search_empty_state.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/overlay/bm_toast.dart';
import 'package:bilimusic/shared/ui/sections/bm_page_header.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
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
      showBmToast(context, '该用户缺少 mid，无法打开 UP 主主页');
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
    final isDesktop = screenSize == ScreenSize.desktop;
    final isLandscape = LandscapeBreakpoints.shouldUseLandscapeLayout(context);
    final side = isLandscape ? BmTokens.contentInset : BmTokens.pageInset;

    return Scaffold(
      // 透出壳层的流体背景；页面本身不再铺一层底色。
      backgroundColor: context.bmColors.bg.withAlpha(0),
      body: SafeArea(
        top: !isLandscape,
        bottom: false,
        left: false,
        right: false,
        child: PopScope(
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
              _pad(
                side,
                SliverToBoxAdapter(
                  child: _buildHeader(
                    context,
                    selectedType: selectedType,
                    availableTypes: availableTypes,
                    isLandscape: isLandscape,
                    isDesktop: isDesktop,
                  ),
                ),
              ),
              if (availableTypes.isNotEmpty && !isDesktop)
                _pad(
                  side,
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: BmTokens.s3),
                      child: SearchTypeTabs(
                        selectedType: selectedType,
                        onTypeChanged: _onTypeChanged,
                        availableTypes: availableTypes,
                      ),
                    ),
                  ),
                ),
              if (isLoading)
                _buildLoadingContent()
              else if (!hasSearched)
                _buildInitialContent()
              else if (results.isEmpty)
                _buildEmptyContent(search.errorMessage)
              else
                ..._buildResultSlivers(
                  context,
                  side: side,
                  isLandscape: isLandscape,
                  selectedType: selectedType,
                  results: results,
                  pages: search.pages,
                  loadingPages: search.loadingPages,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pad(double side, Widget sliver) => SliverPadding(
    padding: EdgeInsets.symmetric(horizontal: side),
    sliver: sliver,
  );

  Widget _buildHeader(
    BuildContext context, {
    required SearchResultType selectedType,
    required List<SearchResultType> availableTypes,
    required bool isLandscape,
    required bool isDesktop,
  }) {
    return BmPageHeader(
      title: '搜索',
      eyebrow: '“${widget.query}”',
      padding: EdgeInsets.only(
        top: isLandscape ? BmTokens.contentInsetTop : BmTokens.s3,
        bottom: BmTokens.s3,
      ),
      actions: [
        if (!isLandscape)
          BmIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onPressed: () => ShellPageManager.instance.pop(),
          ),
        if (isDesktop && availableTypes.isNotEmpty)
          SearchTypeDropdown(
            selectedType: selectedType,
            onTypeChanged: _onTypeChanged,
            availableTypes: availableTypes,
          ),
      ],
    );
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

  List<Widget> _buildResultSlivers(
    BuildContext context, {
    required double side,
    required bool isLandscape,
    required SearchResultType selectedType,
    required List<SearchResult> results,
    required Map<String, List<music_model.Page>> pages,
    required Set<String> loadingPages,
  }) {
    final colors = context.bmColors;
    final type = context.bmType;
    final isDesktop =
        ResponsiveHelper.getScreenSize(context) == ScreenSize.desktop;

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

    final slivers = <Widget>[
      _pad(
        side,
        SliverToBoxAdapter(
          child: FadeInWidget(
            duration: BmMotion.large,
            child: Padding(
              padding: const EdgeInsets.only(bottom: BmTokens.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '找到 ${results.length} 个结果',
                      style: type.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (!isDesktop)
                    Text(
                      '类型：${_getTypeLabel(selectedType)}',
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];

    if (multiPartResults.isNotEmpty) {
      slivers.add(
        _pad(
          side,
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: BmTokens.s2),
              child: Text(
                '系列视频 (${multiPartResults.length})',
                style: type.bodyStrong.copyWith(color: colors.accentDeep),
              ),
            ),
          ),
        ),
      );
      slivers.add(
        _pad(
          side,
          SliverList.builder(
            itemCount: multiPartResults.length,
            itemBuilder: (context, index) {
              final result = multiPartResults[index];
              final resultPages = pages[result.id] ?? const [];
              return Padding(
                padding: const EdgeInsets.only(bottom: BmTokens.s3),
                child: FadeInWidget(
                  duration: BmMotion.large,
                  child: _buildMultiPartListItem(result, resultPages),
                ),
              );
            },
          ),
        ),
      );
    }

    slivers.add(
      _pad(
        side,
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              top: BmTokens.s2,
              bottom: BmTokens.s2,
            ),
            child: Text(
              '${_getTypeLabel(selectedType)} (${singlePartResults.length})',
              style: type.bodyStrong.copyWith(color: colors.accentDeep),
            ),
          ),
        ),
      ),
    );
    slivers.add(
      _pad(
        side,
        SliverList.builder(
          itemCount: singlePartResults.length,
          itemBuilder: (context, index) {
            final result = singlePartResults[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: BmTokens.s3),
              child: _buildResultItem(
                context,
                result,
                pages[result.id],
                loading: loadingPages.contains(result.id),
              ),
            );
          },
        ),
      ),
    );
    // 原有留白之外再叠加竖屏浮动 chrome 的高度；横屏该值即底部安全区。
    slivers.add(
      SliverToBoxAdapter(
        child: SizedBox(
          // 竖屏的浮层高度由壳层注入；横屏底栏在布局里，只留 s8 收尾。
          height:
              (isLandscape ? BmTokens.s8 : 0) +
              MediaQuery.paddingOf(context).bottom,
        ),
      ),
    );
    return slivers;
  }

  Widget _buildResultItem(
    BuildContext context,
    SearchResult result,
    List<music_model.Page>? pages, {
    required bool loading,
  }) {
    if (result.type != SearchResultType.video ||
        (loading && (pages == null || pages.isEmpty))) {
      return _SearchResultCard(result: result, onTap: _onResultTap(result));
    }

    return _buildListItem(result, pages);
  }

  Widget _buildMultiPartListItem(
    SearchResult result,
    List<music_model.Page> pages,
  ) {
    return MusicListItem(
      music: result.toMusic(pages: pages),
      playerCoordinator: ref.read(playerCoordinatorProvider),
      commands: ref.read(playlistCommandsProvider.notifier),
      playlistService: ref.read(playlistServiceProvider),
      onTap: () => _navigateToPlaylist(result, pages),
      showCover: true,
      showDetails: true,
      showPageIndicator: true,
    );
  }

  Widget _buildListItem(SearchResult result, List<music_model.Page>? pages) {
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

/// 非视频结果的行：封面 + 标题 + 副标题 + 尾部图标。
class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback? onTap;

  const _SearchResultCard({required this.result, this.onTap});

  bool get _isPerson =>
      result.type == SearchResultType.author ||
      result.type == SearchResultType.upuser;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return BmPressable(
      onTap: onTap,
      borderRadius: BmTokens.r10All,
      semanticLabel: '${result.title}，${result.subtitle}',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s2,
          vertical: BmTokens.s2,
        ),
        child: Row(
          children: [
            _buildCover(context),
            const SizedBox(width: BmTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.body.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: BmTokens.s1 / 2),
                  Text(
                    result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (_isPerson)
              Icon(
                Icons.chevron_right,
                size: BmTokens.icon,
                color: colors.textTertiary,
              )
            else if (result.type == SearchResultType.video)
              BmIconButton(
                icon: Icons.play_circle_outline_rounded,
                tooltip: '播放',
                onPressed: onTap,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final colors = context.bmColors;
    final coverUrl = result.coverUrl.isNotEmpty
        ? result.coverUrl
        : (_isPerson ? '' : music_model.fallbackCoverUrl);

    return ClipRRect(
      borderRadius: _isPerson ? BmTokens.rPillAll : BmTokens.albumArtRadius,
      child: SizedBox(
        width: BmTokens.row,
        height: BmTokens.row,
        child: coverUrl.isEmpty
            ? ColoredBox(
                color: colors.bgDeep,
                child: Icon(
                  _trailingIcon,
                  size: BmTokens.iconLarge,
                  color: colors.textTertiary,
                ),
              )
            : BmArtImage(url: coverUrl, cacheKey: result.id),
      ),
    );
  }

  IconData get _trailingIcon {
    switch (result.type) {
      case SearchResultType.video:
        return Icons.music_note_rounded;
      case SearchResultType.album:
        return Icons.album_rounded;
      case SearchResultType.author:
      case SearchResultType.upuser:
        return Icons.person_rounded;
      case SearchResultType.bangumi:
        return Icons.tv_rounded;
      case SearchResultType.topic:
        return Icons.tag_rounded;
    }
  }
}
