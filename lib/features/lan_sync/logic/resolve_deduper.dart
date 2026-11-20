import 'dart:async';

/// [ResolveDeduper] 使用的定时器工厂，便于单测注入假定时器。
typedef DeduperTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// mDNS 服务解析（resolve）在途去重器。
///
/// bonsoir 的 Found / Updated 事件都可能带着空地址到达，每来一个事件就
/// `resolve` 一次，会让同一条服务记录同时被多个解析请求改写，给原生层的
/// 数据竞争提供更多机会。这里按服务键做在途占位：
///
/// - 占位期间同一服务不再重复发起解析；
/// - 收到终态事件（Resolved / 带地址的 Updated / Lost）时 [complete] 释放；
/// - 事件丢失时用 [timeout] 兜底释放，避免该服务永久无法再解析。
class ResolveDeduper {
  ResolveDeduper({
    this.timeout = defaultTimeout,
    DeduperTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? _createTimer;

  /// 在途占位的默认兜底超时。
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// 单个占位的最长存活时间；到点强制释放。
  final Duration timeout;

  final DeduperTimerFactory _timerFactory;

  /// 服务键 → 超时定时器。
  final Map<String, Timer> _inFlight = <String, Timer>{};

  static Timer _createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);

  /// [key] 是否已有解析在途。
  bool isInFlight(String key) => _inFlight.containsKey(key);

  /// 当前在途解析数量。
  int get inFlightCount => _inFlight.length;

  /// 尝试占用 [key] 来发起解析；已有解析在途时返回 false。
  bool tryBegin(String key) {
    if (_inFlight.containsKey(key)) return false;
    _inFlight[key] = _timerFactory(timeout, () => _inFlight.remove(key));
    return true;
  }

  /// 释放 [key] 的在途占位（收到终态事件或解析失败时调用）。
  void complete(String key) => _inFlight.remove(key)?.cancel();

  /// 清空所有在途占位（停止发现时调用）。
  void clear() {
    for (final timer in _inFlight.values) {
      timer.cancel();
    }
    _inFlight.clear();
  }
}
