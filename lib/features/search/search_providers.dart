import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/domain/search_suggest.dart';

/// 搜索中间态的联想词状态。
class SearchSuggestState {
  /// 当前输入的关键词（已 trim）。
  final String term;

  /// 接口返回的联想词，按返回顺序排列。
  final List<SearchSuggest> items;

  final bool isLoading;

  const SearchSuggestState({
    this.term = '',
    this.items = const [],
    this.isLoading = false,
  });
}

/// 搜索联想：输入防抖后拉取，只采纳最后一次输入对应的响应。
class SearchSuggestNotifier extends Notifier<SearchSuggestState> {
  static const Duration _debounceDuration = Duration(milliseconds: 250);

  Timer? _debounce;
  int _generation = 0;

  @override
  SearchSuggestState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchSuggestState();
  }

  /// 输入变化时调用：空串立即清空，其余防抖后请求联想词。
  void update(String raw) {
    _debounce?.cancel();
    final term = raw.trim();
    final generation = ++_generation;

    if (term.isEmpty) {
      if (state.term.isNotEmpty || state.items.isNotEmpty || state.isLoading) {
        state = const SearchSuggestState();
      }
      return;
    }

    state = SearchSuggestState(term: term, isLoading: true);
    _debounce = Timer(_debounceDuration, () => _load(term, generation));
  }

  Future<void> _load(String term, int generation) async {
    final items = await ref.read(apiServiceProvider).fetchSearchSuggest(term);
    if (!ref.mounted || generation != _generation) return;
    state = SearchSuggestState(term: term, items: items);
  }

  /// 提交搜索时记录关键词，不再为它发联想请求（返回中间态时由页面重新拉）。
  void remember(String raw) {
    _debounce?.cancel();
    _generation++;
    final term = raw.trim();
    state = term.isEmpty
        ? const SearchSuggestState()
        : SearchSuggestState(term: term);
  }

  /// 退出搜索中间态时清空。
  void clear() {
    _debounce?.cancel();
    _generation++;
    if (state.term.isNotEmpty || state.items.isNotEmpty || state.isLoading) {
      state = const SearchSuggestState();
    }
  }
}

final searchSuggestProvider =
    NotifierProvider<SearchSuggestNotifier, SearchSuggestState>(
      SearchSuggestNotifier.new,
    );

/// 一次关键词搜索的完整结果。
///
/// 放在应用级 Provider 里而不是页面 State：搜索结果页被分P歌单、UP 主页等
/// 压栈时会整个销毁，返回时若重新初始化就会再发一次搜索请求。把结果留在这里，
/// 页面重建只是重新订阅同一份状态——数据、分P 缓存和选中的类型都原样还在。
class SearchResultsState {
  final String query;

  /// `/x/web-interface/search/all/v2` 一次返回的全部类型结果。
  final List<SearchResult> results;

  /// 本次结果里实际出现过的类型（保持接口返回顺序）。
  final List<SearchResultType> availableTypes;

  /// 当前展示的类型。
  final SearchResultType selectedType;

  final bool isLoading;
  final bool hasSearched;
  final String? errorMessage;

  /// bvid -> 分P。随搜索结果一起缓存，返回页面时不会重新拉取。
  final Map<String, List<Page>> pages;

  /// 正在拉取分P的 bvid。
  final Set<String> loadingPages;

  const SearchResultsState({
    this.query = '',
    this.results = const [],
    this.availableTypes = const [],
    this.selectedType = SearchResultType.video,
    this.isLoading = false,
    this.hasSearched = false,
    this.errorMessage,
    this.pages = const {},
    this.loadingPages = const {},
  });

  /// 当前类型下的结果。
  List<SearchResult> get filteredResults =>
      SearchResult.filterByType(results, selectedType);

  SearchResultsState copyWith({
    String? query,
    List<SearchResult>? results,
    List<SearchResultType>? availableTypes,
    SearchResultType? selectedType,
    bool? isLoading,
    bool? hasSearched,
    String? errorMessage,
    bool clearError = false,
    Map<String, List<Page>>? pages,
    Set<String>? loadingPages,
  }) {
    return SearchResultsState(
      query: query ?? this.query,
      results: results ?? this.results,
      availableTypes: availableTypes ?? this.availableTypes,
      selectedType: selectedType ?? this.selectedType,
      isLoading: isLoading ?? this.isLoading,
      hasSearched: hasSearched ?? this.hasSearched,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pages: pages ?? this.pages,
      loadingPages: loadingPages ?? this.loadingPages,
    );
  }
}

class SearchResultsNotifier extends Notifier<SearchResultsState> {
  /// 搜索请求代数：新搜索开始后，旧请求（含分P预取）的返回结果一律丢弃。
  int _generation = 0;

  @override
  SearchResultsState build() => const SearchResultsState();

  /// 用 [rawQuery] 重新搜索。入口只有竖屏搜索中间态页与横屏标题栏，
  /// 搜索结果页本身只消费本状态，因此压栈/返回不会触发网络请求。
  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    final generation = ++_generation;

    if (query.isEmpty) {
      state = const SearchResultsState();
      return;
    }

    state = SearchResultsState(query: query, isLoading: true);

    final SearchResponse response;
    try {
      response = await ref.read(apiServiceProvider).search(query);
    } catch (e) {
      if (!ref.mounted || generation != _generation) return;
      debugPrint('[SearchResults] search($query): $e');
      state = SearchResultsState(
        query: query,
        hasSearched: true,
        errorMessage: '搜索失败，请稍后重试',
      );
      return;
    }
    if (!ref.mounted || generation != _generation) return;

    final types = SearchResult.getAvailableTypes(response.results);
    state = SearchResultsState(
      query: query,
      results: response.results,
      availableTypes: types,
      selectedType: _defaultType(types),
      hasSearched: true,
      errorMessage: response.results.isEmpty ? '没有搜索到任何结果' : null,
    );

    if (response.results.isNotEmpty) {
      unawaited(_prefetchPages(response.results, generation));
    }
  }

  /// 切换当前展示的类型。类型不在本次结果集里时忽略。
  void selectType(SearchResultType type) {
    if (type == state.selectedType || !state.availableTypes.contains(type)) {
      return;
    }
    state = state.copyWith(selectedType: type);
  }

  /// 默认展示视频；本次没有视频时退回接口返回的第一个类型（例如只搜到 UP主）。
  static SearchResultType _defaultType(List<SearchResultType> types) {
    if (types.isEmpty) return SearchResultType.video;
    if (types.contains(SearchResultType.video)) return SearchResultType.video;
    return types.first;
  }

  /// 依次预取视频分P，用于把多P稿件拆成「系列视频」。
  ///
  /// 沿用原来的 50ms 间隔，避免一次打太多详情请求。代数变化时立即停手。
  Future<void> _prefetchPages(
    List<SearchResult> results,
    int generation,
  ) async {
    for (final result in results) {
      if (!ref.mounted || generation != _generation) return;
      if (result.type != SearchResultType.video || result.id.isEmpty) continue;
      if (state.pages.containsKey(result.id)) continue;
      if (state.loadingPages.contains(result.id)) continue;

      state = state.copyWith(loadingPages: {...state.loadingPages, result.id});

      try {
        final pages = await ref
            .read(apiServiceProvider)
            .getVideoPages(result.id);
        if (!ref.mounted || generation != _generation) return;
        state = state.copyWith(
          pages: {...state.pages, result.id: pages},
          loadingPages: {...state.loadingPages}..remove(result.id),
        );
      } catch (_) {
        if (!ref.mounted || generation != _generation) return;
        state = state.copyWith(
          loadingPages: {...state.loadingPages}..remove(result.id),
        );
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}

final searchResultsProvider =
    NotifierProvider<SearchResultsNotifier, SearchResultsState>(
      SearchResultsNotifier.new,
    );
