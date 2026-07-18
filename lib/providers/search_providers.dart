import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchState {
  final String query;
  final bool shouldSearch;

  const SearchState({this.query = '', this.shouldSearch = false});

  SearchState copyWith({String? query, bool? shouldSearch}) {
    return SearchState(
      query: query ?? this.query,
      shouldSearch: shouldSearch ?? this.shouldSearch,
    );
  }
}

class SearchStateNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();

  void setQuery(String query) {
    if (state.query != query) {
      state = SearchState(query: query, shouldSearch: query.isNotEmpty);
    }
  }

  void clear() {
    if (state.query.isNotEmpty || state.shouldSearch) {
      state = const SearchState();
    }
  }

  void markSearched() {
    if (state.shouldSearch) {
      state = state.copyWith(shouldSearch: false);
    }
  }
}

final searchStateProvider = NotifierProvider<SearchStateNotifier, SearchState>(
  SearchStateNotifier.new,
);
