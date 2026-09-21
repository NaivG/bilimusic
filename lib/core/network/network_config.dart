import 'dart:async';

import 'package:bilimusic/core/network/bili_bootstrap.dart';
import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/wbi.dart';

/// 全局网络配置：请求头、Cookie 仓库、超时与签名策略。
///
/// 设计上保持**纯 Dart**（不 import 任何 Flutter 插件）：持久化由宿主通过
/// [cookieLoader] / [cookieSaver] 注入（App 走 SharedPreferences，TUI 直接读
/// 桌面 App 的存储文件），这样 core 层能被 TUI 等纯 Dart 宿主复用。
///
/// Cookie 按域名 / 路径 / 过期时间决定每个请求该带哪些 Cookie，
/// 并把响应里的 `Set-Cookie` 统一收回来。
class NetworkConfig {
  const NetworkConfig._();

  /// 全应用唯一的 User-Agent。
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:153.0) '
      'Gecko/20100101 Firefox/153.0';

  static const String apiBase = 'https://api.bilibili.com';
  static const String webBase = 'https://www.bilibili.com';
  static const String searchBase = 'https://search.bilibili.com';
  static const String passportBase = 'https://passport.bilibili.com';

  /// B 站 JSON 接口通用的 Accept。
  static const String jsonAccept = 'application/json, text/plain, */*';

  static const String _acceptLanguage = 'zh-CN,zh;q=0.9,en;q=0.8';

  /// Cookie 持久化钩子，由 App 宿主（main.dart）注入 SharedPreferences 实现。
  ///
  /// 未注入时持久化自然跳过（纯内存），CLI / 测试可直接使用。
  static Future<String?> Function()? cookieLoader;
  static Future<void> Function(String cookiesJson)? cookieSaver;

  static Duration _timeout = const Duration(seconds: 15);
  static bool _wbiOnRiskControl = true;

  static CookieJar _cookieJar = CookieJar();
  static BiliBootstrap? _bootstrap;
  static WbiSigner? _wbiSigner;

  /// Cookie 仓库。唯一的登录态事实来源（`SESSDATA` 在就在）。
  static CookieJar get cookieJar => _cookieJar;

  /// 自举器（设备标识 / 票据 / WBI 口令）。
  static BiliBootstrap get bootstrap => _bootstrap ??= BiliBootstrap(
    jar: _cookieJar,
    timeout: _timeout < const Duration(seconds: 10)
        ? _timeout
        : const Duration(seconds: 10),
  );

  /// WBI 签名器，默认口令来源就是 [bootstrap]。
  static WbiSigner get wbiSigner =>
      _wbiSigner ??= WbiSigner(fetchKeys: bootstrap.fetchWbiKeys);

  /// 默认请求超时。
  static Duration get timeout => _timeout;

  /// 撞上风控且当次未签名时，是否自动补签重试一次。
  static bool get wbiOnRiskControl => _wbiOnRiskControl;

  /// 启动时替换实现（宿主注入持久化、测试注入假数据）都走这里。
  ///
  /// 传 [cookieJar] 会连带重建 [bootstrap] / [wbiSigner]（它们持有旧 jar 的引用）。
  static void configure({
    CookieJar? cookieJar,
    Duration? timeout,
    bool? wbiOnRiskControl,
  }) {
    if (cookieJar != null) {
      _cookieJar = cookieJar;
      _bootstrap = null;
      _wbiSigner = null;
    }
    if (timeout != null) _timeout = timeout;
    if (wbiOnRiskControl != null) _wbiOnRiskControl = wbiOnRiskControl;
  }

  /// 基础请求头（不含 Cookie）。
  ///
  /// [withOrigin] 只给写请求用：浏览器的同站 GET 不带 `Origin`，
  /// 带着反而更像脚本；POST 才会带。
  static Map<String, String> baseHeaders({
    Uri? forUri,
    bool withOrigin = false,
    String accept = '*/*',
  }) {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': accept,
      'Accept-Language': _acceptLanguage,
      'Referer': '${_refererFor(forUri)}/',
    };
    if (withOrigin) {
      headers['Origin'] = webBase;
    }
    return headers;
  }

  /// 基础请求头 + 该 URL 该带的 Cookie —— **出站请求的唯一装配入口**。
  static Map<String, String> headersFor(
    Uri uri, {
    bool withOrigin = false,
    String accept = jsonAccept,
  }) {
    final headers = baseHeaders(
      forUri: uri,
      withOrigin: withOrigin,
      accept: accept,
    );
    final cookie = _cookieJar.cookieHeaderFor(uri);
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  /// 给「不区分目标域名」的调用方用的一套固定请求头：封面 / 头像 / 歌单图等
  /// `cached_network_image` 的 `httpHeaders`。
  ///
  /// 按主站域名取 Cookie —— 图片域（`i0.hdslb.com`）匹配不到，多带一份用不上的
  /// Cookie 无害；真正防外链的是 `Referer`。
  static Map<String, String> get biliHeaders =>
      headersFor(Uri.parse('$webBase/'));

  /// 按目标域名挑一个自然的 Referer（返回值不带结尾斜杠，由调用方补）。
  static String _refererFor(Uri? uri) {
    if (uri == null) return webBase;
    final host = uri.host;
    if (host == 'api.bilibili.com') return webBase;
    if (host == 'passport.bilibili.com') return webBase;
    if (host == 'search.bilibili.com') return searchBase;
    if (host.endsWith('bilibili.com')) return 'https://$host';
    return webBase;
  }

  /// 启动引导：载入持久化 Cookie（含旧扁平格式一次性迁移），补齐设备标识与票据。
  ///
  /// [waitForBootstrap] 默认 **false**：只等本地读盘（很快），联网自举放到后台 ——
  /// 自举要串行发好几个请求（finger/spi → GenWebTicket → 主站激活），等它会把首屏
  /// 拖到网络上；而自举本身只是"降低风控概率"，失败也能跑（原因记在
  /// `BiliBootstrap.lastError`）。需要确定性时序的场景（探针 / 测试）再传 true。
  static Future<void> init({bool waitForBootstrap = false}) async {
    // 宿主注入的静态钩子挂到当前 jar 上；构造时已注入的那份优先，不被覆盖。
    _cookieJar.loader ??= cookieLoader;
    _cookieJar.saver ??= cookieSaver;

    await _cookieJar.load();

    if (waitForBootstrap) {
      await bootstrap.ensureDeviceCookies();
    } else {
      unawaited(bootstrap.ensureDeviceCookies());
    }
  }
}
