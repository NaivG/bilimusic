/// B 站 API 错误的公共抽象父类（便于 `on BiliException` 一并捕获）。
sealed class BiliException implements Exception {
  const BiliException();

  String get message;
  int get code;
  int? get statusCode;

  @override
  String toString() => '$runtimeType(code: $code, message: $message)';
}

/// 业务错误：HTTP 200 但 `code != 0`。
class BiliApiException extends BiliException {
  @override
  final int code;
  @override
  final String message;

  const BiliApiException(this.code, this.message);

  @override
  int? get statusCode => 200;
}

/// 网络 / 传输层错误：非 200、超时、SocketException、JSON 解析失败等。
class BiliNetworkException extends BiliException {
  @override
  final int? statusCode;
  @override
  final String message;
  @override
  int get code => -1;

  const BiliNetworkException(this.statusCode, this.message);
}
