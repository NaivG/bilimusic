import 'package:flutter/foundation.dart';

/// 搜索状态管理器（单例）
/// 用于横屏模式下 LandscapeShell 和 SearchPage 之间的搜索状态共享
class SearchStateNotifier extends ChangeNotifier {
  static SearchStateNotifier? _instance;
  static SearchStateNotifier get instance {
    _instance ??= SearchStateNotifier._();
    return _instance!;
  }

  SearchStateNotifier._();

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
