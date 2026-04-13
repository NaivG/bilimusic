import 'package:flutter/material.dart';

/// 搜索状态管理器
/// 用于横屏模式下 LandscapeShell 和 SearchPage 之间的搜索状态共享
class SearchStateNotifier extends ChangeNotifier {
  String _query = '';
  bool _shouldSearch = false;

  String get query => _query;
  bool get shouldSearch => _shouldSearch;

  /// 设置搜索查询并触发搜索
  void setQuery(String query) {
    if (_query != query) {
      _query = query;
      _shouldSearch = query.isNotEmpty;
      notifyListeners();
    }
  }

  /// 清除搜索状态
  void clear() {
    if (_query.isNotEmpty || _shouldSearch) {
      _query = '';
      _shouldSearch = false;
      notifyListeners();
    }
  }

  /// 标记搜索已完成（用于 SearchPage 搜索完成后调用）
  void markSearched() {
    if (_shouldSearch) {
      _shouldSearch = false;
      notifyListeners();
    }
  }
}

/// 提供 SearchStateNotifier 的 InheritedWidget
class SearchStateProvider extends InheritedWidget {
  final SearchStateNotifier searchState;

  const SearchStateProvider({
    super.key,
    required this.searchState,
    required super.child,
  });

  static SearchStateNotifier of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<SearchStateProvider>();
    if (provider == null) {
      throw Exception('No SearchStateProvider found in the widget tree');
    }
    return provider.searchState;
  }

  @override
  bool updateShouldNotify(covariant SearchStateProvider oldWidget) {
    return searchState != oldWidget.searchState;
  }
}
