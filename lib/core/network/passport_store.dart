import 'dart:async';
import 'dart:convert';

/// 登录凭据仓库：保存 `refresh_token` 这类**非 Cookie** 的登录凭据。
///
/// Cookie 由 `CookieJar` 负责；而 `refresh_token` 是 passport 在登录成功时
/// （扫码确认 / 密码 / 短信）随响应体下发的刷新凭据，SESSDATA 续期要用，Web 端
/// 把它存 localStorage，这里单独落盘。
///
/// 纯 Dart（core 层规则，TUI / CLI 宿主可复用）：持久化通过 [loader] / [saver]
/// 注入，宿主不注入时退化为纯内存（App 侧的注入在 `app_providers.dart`）。
class PassportStore {
  PassportStore({this.loader, this.saver});

  /// 读取持久化字符串（JSON，见 [setRefreshToken] 的落盘格式）。
  final Future<String?> Function()? loader;

  /// 写入持久化字符串。
  final Future<void> Function(String json)? saver;

  String? _refreshToken;

  /// 首次读盘只做一次，后续读写都基于缓存。
  Future<void>? _loaded;

  /// 当前内存里的 refresh_token（可能尚未读盘，读路径请用 [readRefreshToken]）。
  String? get refreshToken => _refreshToken;

  Future<void> _ensureLoaded() => _loaded ??= _loadOnce();

  Future<void> _loadOnce() async {
    final load = loader;
    if (load == null) return;
    final raw = await load();
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      _refreshToken = decoded['refresh_token']?.toString();
    }
  }

  /// 读取 refresh_token（首次调用会读盘）。
  Future<String?> readRefreshToken() async {
    await _ensureLoaded();
    return _refreshToken;
  }

  /// 写入 refresh_token（登录成功时调用）。
  Future<void> setRefreshToken(String token) async {
    _refreshToken = token;
    final save = saver;
    if (save == null) return;
    await save(jsonEncode({'version': 1, 'refresh_token': token}));
  }

  /// 清空（登出时调用）。
  Future<void> clear() async {
    await _ensureLoaded();
    _refreshToken = null;
    final save = saver;
    if (save == null) return;
    await save(jsonEncode({'version': 1, 'refresh_token': null}));
  }
}
