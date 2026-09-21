import 'dart:async';
import 'dart:convert';

import 'package:bilimusic/core/network/bili_cookie.dart';

/// Cookie 仓库：按域名 / 路径 / 过期时间存放，并负责持久化。
///
/// 相比旧版 `NetworkConfig` 的「扁平 name→value 表」，这里做的是真正的 Cookie 语义：
///   - 按 host 决定回传哪些 Cookie（`api.bilibili.com` 与 `www.bilibili.com` 各取所需）
///   - 路径前缀匹配、过期时间、会话 Cookie
///   - 记录 `Secure` / `HttpOnly`，方便判断能否给某个 URL 带上
///
/// 本类保持纯 Dart（不依赖任何 Flutter 插件）：持久化通过 [loader] / [saver]
/// 注入，宿主不注入时自动退化为纯内存，CLI / 测试可直接使用。
///
/// **旧格式一次性迁移**：≤1.9.x 的 BiliMusic 把 Cookie 存成扁平 JSON
/// （`{"SESSDATA":"…","buvid3":"…"}`），[load] 会就地展开成完整 Cookie 按当前格式回写一次。
class CookieJar {
  CookieJar({this.loader, this.saver, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// 读取持久化字符串（JSON，见 [toJsonString]）。
  ///
  /// 故意可变：宿主有两套注入习惯 —— 构造时注入（测试 / CLI），或沿用
  /// `NetworkConfig.cookieLoader / cookieSaver` 静态钩子（`NetworkConfig.init`
  /// 会把它挂到当前 jar 上，且**不覆盖**构造时已注入的那份）。
  Future<String?> Function()? loader;

  /// 写入持久化字符串。多次调用会被串行化，避免并发写互相覆盖。
  Future<void> Function(String json)? saver;

  final DateTime Function() _clock;

  /// key 为 `domain|path|name`。
  final Map<String, BiliCookie> _cookies = {};

  Future<void> _writeChain = Future<void>.value();

  /// 旧扁平格式补全时用的域名。
  ///
  /// 老格式不带域名信息 —— 当年是所有请求共用一份 Cookie，等价于
  /// 「`bilibili.com` 及其子域都带上」。
  static const String legacyDomain = 'bilibili.com';

  /// 旧格式也没有过期时间；给一个上界，服务端真过期时照旧会返回 -101。
  static const Duration legacyLifetime = Duration(days: 365);

  /// 当前所有未过期的 Cookie。
  List<BiliCookie> get all {
    final now = _clock();
    return _cookies.values.where((c) => !c.isExpiredAt(now)).toList();
  }

  int get length => all.length;

  bool get isEmpty => all.isEmpty;

  /// 是否已登录（SESSDATA 存在即视为登录态，与 Web 端一致）。
  bool get isLoggedIn => value('SESSDATA') != null;

  /// 写接口需要的 csrf，就是 `bili_jct`。
  String? get csrf => value('bili_jct');

  /// 取某个名字的 Cookie 值（不区分域名，取路径最具体的那条）。
  String? value(String name) {
    final now = _clock();
    BiliCookie? best;
    for (final cookie in _cookies.values) {
      if (cookie.name != name || cookie.isExpiredAt(now)) continue;
      if (best == null || cookie.path.length > best.path.length) best = cookie;
    }
    return best?.value;
  }

  bool contains(String name) => value(name) != null;

  /// 本地生成 / 覆盖一条 Cookie（设备标识、登录成功后手动写入等）。
  void set(
    String name,
    String value, {
    String domain = legacyDomain,
    String path = '/',
    DateTime? expiresAt,
    bool httpOnly = false,
    bool secure = true,
  }) {
    final normalized = domain.startsWith('.') ? domain.substring(1) : domain;
    final cookie = BiliCookie(
      name: name,
      value: value,
      domain: normalized.toLowerCase(),
      path: path,
      expiresAt: expiresAt,
      httpOnly: httpOnly,
      secure: secure,
    );
    _cookies[cookie.storageKey] = cookie;
    scheduleSave();
  }

  /// 按名字删除（登出时清会话 Cookie 用）。
  void remove(String name) {
    _cookies.removeWhere((_, cookie) => cookie.name == name);
    scheduleSave();
  }

  /// 收集 [uri] 该带的 Cookie，拼成 `Cookie` 请求头的值。
  ///
  /// 排序遵循 RFC 6265 §5.4：路径长的在前（更具体的优先）。
  String? cookieHeaderFor(Uri uri) {
    final now = _clock();
    final matched = <BiliCookie>[];
    for (final cookie in _cookies.values) {
      if (cookie.isExpiredAt(now)) continue;
      if (!cookie.domainMatches(uri.host)) continue;
      if (!cookie.pathMatches(uri.path.isEmpty ? '/' : uri.path)) continue;
      if (cookie.secure && uri.scheme != 'https') continue;
      matched.add(cookie);
    }
    if (matched.isEmpty) return null;

    matched.sort((a, b) {
      final byPath = b.path.length.compareTo(a.path.length);
      return byPath != 0 ? byPath : a.name.compareTo(b.name);
    });
    return matched.map((c) => '${c.name}=${c.value}').join('; ');
  }

  /// name → value 的扁平视图，便于调试与展示。
  Map<String, String> toMap() => {
    for (final cookie in all) cookie.name: cookie.value,
  };

  /// 处理一轮响应里的 `Set-Cookie`。
  ///
  /// [setCookieValues] 直接传 `response.headersSplitValues['set-cookie']`；
  /// 若中间层把它们拼成了一条，这里也会按 RFC 语义拆开。
  /// 返回本次实际生效（新增或修改）的 Cookie 名，便于上层打日志。
  List<String> ingest(Uri uri, Iterable<String> setCookieValues) {
    final now = _clock();
    final changed = <String>[];

    for (final rawValue in setCookieValues) {
      for (final single in SetCookieParser.splitMerged(rawValue)) {
        final cookie = SetCookieParser.parse(
          single,
          requestHost: uri.host,
          now: now,
        );
        if (cookie == null) continue;

        if (cookie.isExpiredAt(now)) {
          // Max-Age=0 / 已过期的 Expires 表示删除。
          if (_cookies.remove(cookie.storageKey) != null) {
            changed.add(cookie.name);
          }
          continue;
        }

        final existing = _cookies[cookie.storageKey];
        if (existing != null && existing.value == cookie.value) continue;
        _cookies[cookie.storageKey] = cookie;
        changed.add(cookie.name);
      }
    }

    if (changed.isNotEmpty) scheduleSave();
    return changed;
  }

  /// 清空全部 Cookie（含登录态）。
  void clear() {
    _cookies.clear();
    scheduleSave();
  }

  /// 只清登录态，保留 buvid3 / b_nut / bili_ticket 等设备标识。
  void clearSession() {
    const sessionKeys = {
      'SESSDATA',
      'bili_jct',
      'DedeUserID',
      'DedeUserID__ckMd5',
      'sid',
      'buvid_fp',
      'x-bili-gaia-vtoken',
    };
    _cookies.removeWhere((_, cookie) => sessionKeys.contains(cookie.name));
    scheduleSave();
  }

  /// 从 [loader] 载入持久化数据，并顺手清掉已过期的条目。
  ///
  /// 认三种历史格式：
  ///   1. 当前格式 `{"version":1,"cookies":[{…}]}`
  ///   2. 旧扁平 JSON `{"SESSDATA":"…","buvid3":"…"}`（≤1.9.x 的落盘形态）
  ///   3. 裸 Cookie 串 `"SESSDATA=…; buvid3=…"`（更早的字符串形态）
  ///
  /// 2 / 3 会按 [legacyDomain] 补全成完整 Cookie 并**回写一次**，把盘上格式升级掉；
  /// 换不回也无所谓 —— 下次启动再认一遍老格式即可。
  Future<void> load() async {
    final load = loader;
    if (load == null) return;
    final raw = await load();
    if (raw == null || raw.isEmpty) return;

    final now = _clock();

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // 不是 JSON：按裸 Cookie 串处理
      _importLegacyPairs(_pairsFromCookieString(raw), now);
      return;
    }

    if (decoded is Map) {
      final list = decoded['cookies'];
      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;
          final cookie = BiliCookie.fromJson(Map<String, dynamic>.from(item));
          if (cookie == null || cookie.isExpiredAt(now)) continue;
          _cookies[cookie.storageKey] = cookie;
        }
        return;
      }
      // 扁平 JSON（旧格式）：所有键值对都是 Cookie
      _importLegacyPairs(
        decoded.map((key, value) => MapEntry('$key', '$value')),
        now,
      );
      return;
    }

    if (decoded is String) {
      _importLegacyPairs(_pairsFromCookieString(decoded), now);
    }
  }

  String toJsonString() => jsonEncode({
    'version': 1,
    'cookies': all.map((c) => c.toJson()).toList(),
  });

  /// 立即落盘。
  Future<void> save() {
    final save = saver;
    if (save == null) return Future<void>.value();
    final payload = toJsonString();
    // 串行化写入：上一次写完之后再写，避免交错覆盖。
    _writeChain = _writeChain.then((_) => save(payload)).catchError((Object _) {
      // 持久化失败不应影响请求链路，下一次写入会带上最新状态。
    });
    return _writeChain;
  }

  /// 标记需要落盘（非阻塞）。
  void scheduleSave() {
    unawaited(save());
  }

  /// 旧扁平格式 → 完整 Cookie；补全后回写一次升级盘上格式。
  void _importLegacyPairs(Map<String, String> pairs, DateTime now) {
    final expiresAt = now.add(legacyLifetime);
    var imported = 0;
    pairs.forEach((name, value) {
      if (name.isEmpty || value.isEmpty) return;
      final cookie = BiliCookie(
        name: name,
        value: value,
        domain: legacyDomain,
        path: '/',
        expiresAt: expiresAt,
        secure: true,
      );
      _cookies[cookie.storageKey] = cookie;
      imported++;
    });
    if (imported == 0) return;
    scheduleSave();
  }

  /// 解析 `a=1; b=2` 形态的 Cookie 串。
  static Map<String, String> _pairsFromCookieString(String raw) {
    final pairs = <String, String>{};
    for (final segment in raw.split(';')) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      pairs[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
    return pairs;
  }
}
