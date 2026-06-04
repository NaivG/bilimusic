import 'dart:convert';

import 'package:flutter/cupertino.dart' show ChangeNotifier, debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/models/user_info.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 用户管理器
/// 职责：
///   - 从 NetworkConfig 的 cookie 判断登录状态
///   - 调用 /x/web-interface/nav 获取用户信息
///   - 内存缓存 + SharedPreferences 持久化，避免短时内重复请求
class UserManager extends ChangeNotifier {
  static const String _prefsKey = 'cached_user_info';
  static const Duration _defaultTtl = Duration(minutes: 5);

  UserInfo? _userInfo;
  bool _isLoggedIn = false;
  DateTime? _lastFetchTime;

  /// 缓存的用户信息（可能为 null）
  UserInfo? get userInfo => _userInfo;

  /// 是否已登录（由 cookie 中的 SESSDATA 判定）
  bool get isLoggedIn => _isLoggedIn;

  /// 最后从 API 刷新的时间
  DateTime? get lastFetchTime => _lastFetchTime;

  /// 缓存是否还在 TTL 内（避免短时内重复请求）
  bool get isFresh {
    if (_lastFetchTime == null) return false;
    return DateTime.now().difference(_lastFetchTime!) < _defaultTtl;
  }

  // ==================== 登录状态检测 ====================

  /// 从当前 cookie 判断是否有登录态（仅检查 SESSDATA，不发请求）
  bool checkCookieLogin() {
    final cookies = NetworkConfig.cookies;
    final hasSession = cookies.containsKey('SESSDATA') &&
        (cookies['SESSDATA'] ?? '').isNotEmpty;
    if (_isLoggedIn != hasSession) {
      _isLoggedIn = hasSession;
      if (!_isLoggedIn) {
        // cookie 消失了，清除用户信息
        _userInfo = null;
        _lastFetchTime = null;
        _persist();
      }
      notifyListeners();
    }
    return _isLoggedIn;
  }

  // ==================== 获取 / 刷新用户信息 ====================

  /// 获取用户信息，优先使用缓存
  ///
  /// [forceRefresh] - true 则跳过缓存，强制调用 API
  /// 返回 current UserInfo？或 null（未登录 / API 失败）
  Future<UserInfo?> getUserInfo({bool forceRefresh = false}) async {
    // 先更新登录状态
    if (!checkCookieLogin()) return null;

    // 缓存有效且不必刷新，直接返回
    if (!forceRefresh && isFresh && _userInfo != null) {
      // debugPrint('[UserManager] 使用缓存用户信息');
      return _userInfo;
    }

    // 调用 API
    return _fetchFromApi();
  }

  /// 强制刷新用户信息（用户显式触发）
  Future<UserInfo?> refresh() => getUserInfo(forceRefresh: true);

  /// 清除用户信息（退出登录时调用）
  Future<void> clear() async {
    _userInfo = null;
    _isLoggedIn = false;
    _lastFetchTime = null;
    await _persist();
    notifyListeners();
  }

  // ==================== 内部 API 调用 ====================

  Future<UserInfo?> _fetchFromApi() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: NetworkConfig.biliHeaders,
      );

      if (response.statusCode != 200) {
        debugPrint('[UserManager] API 请求失败: ${response.statusCode}');
        return _userInfo;
      }

      final json = jsonDecode(response.body);
      if (json['code'] != 0 || json['data'] == null) {
        debugPrint('[UserManager] API 返回异常: ${json['code']}');
        return _userInfo;
      }

      final data = json['data'] as Map<String, dynamic>;

      // 确认登录有效
      if (data['isLogin'] != true) {
        await clear();
        return null;
      }

      _userInfo = UserInfo.fromNavData(data);
      _isLoggedIn = true;
      _lastFetchTime = DateTime.now();
      await _persist();
      notifyListeners();
      return _userInfo;
    } catch (e) {
      debugPrint('[UserManager] 获取用户信息网络异常: $e');
      return _userInfo;
    }
  }

  // ==================== 持久化 ====================

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_userInfo != null && _isLoggedIn) {
        await prefs.setString(_prefsKey, json.encode(_userInfo!.toJson()));
      } else {
        await prefs.remove(_prefsKey);
      }
    } catch (e) {
      debugPrint('[UserManager] 持久化失败: $e');
    }
  }

  /// 从持久化存储恢复缓存（在 app 启动时调用）
  Future<void> restoreFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _userInfo = UserInfo.fromJson(json.decode(raw));
        _isLoggedIn = _userInfo != null && !(_userInfo!.isEmpty);
      }
    } catch (e) {
      debugPrint('[UserManager] 恢复缓存失败: $e');
    }
  }
}
