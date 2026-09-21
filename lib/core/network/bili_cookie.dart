/// 单条 Cookie 的模型与解析。
///
/// 只实现 RFC 6265 里 B 站实际会用到的部分：name/value、Domain、Path、Expires、
/// Max-Age、Secure、HttpOnly。SameSite 只做忽略（我们不是浏览器，没有跨站语义）。
library;

/// 一条 Cookie。
class BiliCookie {
  const BiliCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.expiresAt,
    this.secure = false,
    this.httpOnly = false,
    this.hostOnly = false,
  });

  final String name;
  final String value;

  /// 不含前导点，统一小写。hostOnly 时等于下发它的主机名。
  final String domain;

  final String path;

  /// null 表示会话 Cookie（关掉进程就没了）。
  final DateTime? expiresAt;

  final bool secure;
  final bool httpOnly;

  /// true 表示服务端没给 Domain 属性，只对下发它的主机生效。
  final bool hostOnly;

  bool get isSession => expiresAt == null;

  bool isExpiredAt(DateTime now) {
    final expires = expiresAt;
    return expires != null && !expires.isAfter(now);
  }

  /// RFC 6265 §5.1.3：域名匹配。
  bool domainMatches(String host) {
    final h = host.toLowerCase();
    if (h == domain) return true;
    if (hostOnly) return false;
    return h.endsWith('.$domain');
  }

  /// RFC 6265 §5.1.4：路径匹配（前缀 + 边界必须是 `/`）。
  bool pathMatches(String requestPath) {
    if (requestPath == path) return true;
    if (!requestPath.startsWith(path)) return false;
    if (path.endsWith('/')) return true;
    return requestPath.length > path.length && requestPath[path.length] == '/';
  }

  /// 持久化用的稳定键：同一域名 + 路径 + 名字视为同一条。
  String get storageKey => '${domain.toLowerCase()}|$path|$name';

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'secure': secure,
    'httpOnly': httpOnly,
    'hostOnly': hostOnly,
  };

  static BiliCookie? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final value = json['value'];
    final domain = json['domain'];
    if (name is! String || value is! String || domain is! String) return null;
    final expiresRaw = json['expiresAt'];
    return BiliCookie(
      name: name,
      value: value,
      domain: domain.toLowerCase(),
      path: json['path'] is String ? json['path'] as String : '/',
      expiresAt: expiresRaw is String ? DateTime.tryParse(expiresRaw) : null,
      secure: json['secure'] == true,
      httpOnly: json['httpOnly'] == true,
      hostOnly: json['hostOnly'] == true,
    );
  }

  @override
  String toString() =>
      'BiliCookie($name=$value; domain=$domain; path=$path'
      '${expiresAt == null ? '; session' : '; expires=${expiresAt!.toUtc()}'}'
      '${secure ? '; secure' : ''})';
}

/// `Set-Cookie` 解析工具。
class SetCookieParser {
  const SetCookieParser._();

  static const Map<String, int> _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// RFC 1123 / RFC 850 / asctime 三种日期格式的宽松解析。
  ///
  /// 不使用 `HttpDate.parse`：它在 `dart:io` 里，而本层要保持 Web/wasm 可编译。
  static DateTime? parseHttpDate(String raw) {
    final value = raw.trim();
    // RFC 1123（`Sat, 26 Jul 2025 06:38:43 GMT`）与 RFC 850（`Sunday, 06-Nov-94 08:49:37 GMT`）
    final rfc = RegExp(
      r'^(?:[A-Za-z]{3,9},?\s+)?(\d{1,2})[-\s]([A-Za-z]{3})[-\s](\d{2,4})\s+'
      r'(\d{1,2}):(\d{2}):(\d{2})',
    ).firstMatch(value);
    if (rfc != null) {
      final month = _months[rfc.group(2)!.toLowerCase()];
      if (month != null) {
        return _buildUtc(
          year: int.parse(rfc.group(3)!),
          month: month,
          day: int.parse(rfc.group(1)!),
          hour: int.parse(rfc.group(4)!),
          minute: int.parse(rfc.group(5)!),
          second: int.parse(rfc.group(6)!),
        );
      }
    }

    // asctime（`Sun Nov  6 08:49:37 1994`）：月份在前面
    final asctime = RegExp(
      r'^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+'
      r'(\d{1,2}):(\d{2}):(\d{2})\s+(\d{4})',
    ).firstMatch(value);
    if (asctime != null) {
      final month = _months[asctime.group(1)!.toLowerCase()];
      if (month != null) {
        return _buildUtc(
          year: int.parse(asctime.group(6)!),
          month: month,
          day: int.parse(asctime.group(2)!),
          hour: int.parse(asctime.group(3)!),
          minute: int.parse(asctime.group(4)!),
          second: int.parse(asctime.group(5)!),
        );
      }
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static DateTime _buildUtc({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int second,
  }) {
    // 两位年份：RFC 6265 §5.1.1 规定 70 以前算 2000 年代
    final normalizedYear = year < 100
        ? (year < 70 ? 2000 + year : 1900 + year)
        : year;
    return DateTime.utc(normalizedYear, month, day, hour, minute, second);
  }

  /// 把被合并成一条的多个 `Set-Cookie` 拆开。
  ///
  /// `package:http` 1.2+ 提供了 `headersSplitValues`，正常情况下用不到这里；
  /// 但中间层（代理、自建 Client）可能仍把它们拼成 `a=1, b=2`。
  /// 拆分依据：逗号后紧跟 `token=` 才是新 Cookie 的开头，
  /// 这样 `Expires=Sat, 26 Jul 2025 06:38:43 GMT` 里的逗号不会被误切。
  static List<String> splitMerged(String merged) {
    if (!merged.contains(',')) return [merged];
    final boundaries = <int>[];
    final pattern = RegExp(r',\s*(?=[A-Za-z0-9_.\-]+=)');
    for (final match in pattern.allMatches(merged)) {
      boundaries.add(match.start);
    }
    if (boundaries.isEmpty) return [merged];

    final parts = <String>[];
    var start = 0;
    for (final boundary in boundaries) {
      parts.add(merged.substring(start, boundary));
      start = boundary + 1;
    }
    parts.add(merged.substring(start));
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 解析单条 `Set-Cookie`。
  ///
  /// [requestHost] 用于 Domain 缺省与合法性校验（RFC 6265 §5.3）：
  /// 服务端不能给一个与自己无关的域种 Cookie。
  static BiliCookie? parse(
    String headerValue, {
    required String requestHost,
    required DateTime now,
  }) {
    final segments = headerValue.split(';');
    if (segments.isEmpty) return null;

    final first = segments.first;
    final eq = first.indexOf('=');
    if (eq <= 0) return null;

    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (name.isEmpty) return null;

    String? domainAttr;
    var path = '';
    DateTime? expiresAt;
    int? maxAge;
    var secure = false;
    var httpOnly = false;

    for (final segment in segments.skip(1)) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final index = trimmed.indexOf('=');
      final key = (index == -1 ? trimmed : trimmed.substring(0, index))
          .trim()
          .toLowerCase();
      final attrValue = index == -1 ? '' : trimmed.substring(index + 1).trim();

      switch (key) {
        case 'domain':
          domainAttr = attrValue;
        case 'path':
          path = attrValue;
        case 'expires':
          expiresAt = parseHttpDate(attrValue);
        case 'max-age':
          maxAge = int.tryParse(attrValue);
        case 'secure':
          secure = true;
        case 'httponly':
          httpOnly = true;
        default:
          break; // samesite / priority 等一律忽略
      }
    }

    final host = requestHost.toLowerCase();
    var hostOnly = domainAttr == null || domainAttr.isEmpty;
    var domain = hostOnly ? host : domainAttr.toLowerCase();
    if (domain.startsWith('.')) domain = domain.substring(1);

    // 服务端越权种域直接丢弃。
    if (!hostOnly) {
      final matches =
          host == domain || (host.endsWith('.$domain') && !_looksLikeIp(host));
      if (!matches) return null;
    }

    if (path.isEmpty || !path.startsWith('/')) path = '/';

    // Max-Age 优先于 Expires（RFC 6265 §4.1.2.2）；<=0 表示立即删除。
    if (maxAge != null) {
      expiresAt = now.add(Duration(seconds: maxAge));
    }

    return BiliCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expiresAt: expiresAt,
      secure: secure,
      httpOnly: httpOnly,
      hostOnly: hostOnly,
    );
  }

  static bool _looksLikeIp(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');
}
