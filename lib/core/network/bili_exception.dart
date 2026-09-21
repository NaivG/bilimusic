/// B 站 API 的异常体系。
///
/// 分三类，调用方用 `on BiliApiException` / `on BiliNetworkException` 精确捕获，
/// 或统一用 `on BiliException` 一把兜住：
///   - [BiliApiException]     HTTP 200 但业务 `code != 0`
///   - [BiliNetworkException] 传输层问题：超时、连接失败、非 200 状态码
///   - [BiliParseException]   响应不是预期的 JSON 结构
sealed class BiliException implements Exception {
  const BiliException();

  /// 业务错误码；非业务错误统一为 -1。
  int get code;

  /// HTTP 状态码，传输层完全没拿到响应时为 null。
  int? get statusCode;

  String get message;

  @override
  String toString() =>
      '$runtimeType(code: $code, statusCode: $statusCode, message: $message)';
}

/// 业务错误：HTTP 200，但响应体里的 `code != 0`。
///
/// 常见码：
///   - `-101` 账号未登录
///   - `-352` 风控校验失败（`data.v_voucher` 可用于走 gaia 验证）
///   - `-412` 请求被拦截
///   - `-799` 请求过于频繁
class BiliApiException extends BiliException {
  const BiliApiException(
    this.code,
    this.message, {
    this.vVoucher,
    this.traceId,
  });

  @override
  final int code;

  @override
  final String message;

  /// 风控凭证，`code == -352` 时由服务端下发，可用于申请极验验证。
  final String? vVoucher;

  /// 响应头 `bili-trace-id`，反馈问题时带上。
  final String? traceId;

  @override
  int? get statusCode => 200;

  /// 未登录。列表/详情类接口在未登录时也可能返回它，不一定是错误。
  bool get isNotLogin => code == -101;

  /// 命中风控，需要降频或走验证码。
  bool get isRiskControl => code == -352 || code == -412 || code == -799;

  /// 资源不存在（视频被删、分区为空等）。
  bool get isNotFound => code == -404 || code == 62002 || code == 62004;

  @override
  String toString() {
    final extra = [
      if (vVoucher != null) 'vVoucher: $vVoucher',
      if (traceId != null) 'traceId: $traceId',
    ];
    final suffix = extra.isEmpty ? '' : ', ${extra.join(', ')}';
    return 'BiliApiException(code: $code, message: $message$suffix)';
  }
}

/// 传输层错误：超时、DNS/连接失败、TLS 失败、非 200 状态码。
class BiliNetworkException extends BiliException {
  const BiliNetworkException(
    this.statusCode,
    this.message, {
    this.cause,
    this.isTimeout = false,
  });

  @override
  final int? statusCode;

  @override
  final String message;

  /// 原始异常，方便排查。
  final Object? cause;

  /// 是否为超时（调用方通常可以放心重试）。
  final bool isTimeout;

  /// 非 200 状态码时保留真实状态码，其余情况为 -1。
  @override
  int get code => statusCode ?? -1;

  /// HTTP 412：B 站用状态码表达风控拦截。
  bool get isRiskControl => statusCode == 412;

  /// 服务端错误或限流，适合退避重试。
  ///
  /// 注意不含 412：B 站用 412 表达风控拦截，原样重试既没意义又更像脚本，
  /// 它交给 `BiliClient` 的"补签重试"路径处理。
  ///
  /// 也**不含 304**：304 不是"服务端出错"，而是"你手上的版本还新鲜"，
  /// 该做的是带上 `Cache-Control: no-cache` 重新要一次（由 `getBytes`
  /// 自己处理，见那里的注释），而不是无脑退避重试。
  bool get isRetryable {
    final s = statusCode;
    if (isTimeout) return true;
    if (s == null) return true; // 连接层直接失败
    return s == 408 || s == 429 || s >= 500;
  }

  @override
  String toString() =>
      'BiliNetworkException(statusCode: $statusCode, message: $message, '
      'isTimeout: $isTimeout${cause == null ? '' : ', cause: $cause'})';
}

/// 响应体不是预期结构：JSON 解析失败、根节点不是对象、缺少必需字段等。
class BiliParseException extends BiliException {
  const BiliParseException(this.message, {this.snippet});

  @override
  final String message;

  /// 出问题时的响应片段，截断保留，便于定位。
  final String? snippet;

  @override
  int get code => -1;

  @override
  int? get statusCode => 200;

  @override
  String toString() =>
      'BiliParseException(message: $message'
      '${snippet == null ? '' : ', snippet: $snippet'})';
}
