import 'package:flutter/material.dart';
import 'package:bilimusic/pages/search/widgets/search_bar_widget.dart';
import 'package:bilimusic/pages/search/widgets/search_empty_state.dart';
import 'package:bilimusic/providers/search_state_provider.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

/// 搜索Overlay - 只负责渲染搜索栏
/// 用户输入关键词提交后，推送 SearchResultsOverlay 展示结果
class SearchOverlay extends StatefulWidget {
  const SearchOverlay({super.key});

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  bool _hasInitialQuery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSearchStateListener();
    });
  }

  void _setupSearchStateListener() {
    SearchStateNotifier.instance.addListener(_onSearchStateChanged);
    // 检查初始是否有待搜索词
    final searchState = SearchStateNotifier.instance;
    if (searchState.shouldSearch && searchState.query.isNotEmpty) {
      _searchController.text = searchState.query;
      _hasInitialQuery = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _submitSearch(searchState.query);
        searchState.markSearched();
      });
    }
  }

  void _onSearchStateChanged() {
    final searchState = SearchStateNotifier.instance;
    if (searchState.shouldSearch && searchState.query.isNotEmpty) {
      if (_searchController.text != searchState.query) {
        _searchController.text = searchState.query;
      }
      _hasInitialQuery = true;
      _submitSearch(searchState.query).then((_) {
        searchState.markSearched();
      });
    }
  }

  @override
  void dispose() {
    SearchStateNotifier.instance.removeListener(_onSearchStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _submitSearch(String query) async {
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    ShellPageManager.instance.push(
      ShellPage.searchResults,
      args: {'query': query},
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = ResponsiveHelper.getScreenSize(context);
    final isDesktop = screenSize == ScreenSize.desktop;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // 搜索栏
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 0 : 16,
              ),
              child: Row(
                children: [
                  if (!isDesktop)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => ShellPageManager.instance.pop(),
                    ),
                  Expanded(
                    child: SearchBarWidget(
                      controller: _searchController,
                      onSearch: _submitSearch,
                      autoFocus: !_hasInitialQuery,
                      hintText: '搜索音乐、视频、用户...',
                    ),
                  ),
                ],
              ),
            ),
            // 初始状态提示
            Expanded(
              child: _hasInitialQuery
                  ? const SizedBox()
                  : SearchEmptyState(
                      type: EmptyStateType.initial,
                      suggestions: const [
                        '周杰伦',
                        '林俊杰',
                        '五月天',
                        '陈奕迅',
                        '邓紫棋',
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
