import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/bili_exception.dart';

/// 异常体系的判定语义 —— 它们直接决定「要不要重试 / 要不要补签 / 算不算未登录」。
void main() {
  group('业务错误码', () {
    test('未登录', () {
      expect(const BiliApiException(-101, '账号未登录').isNotLogin, isTrue);
      expect(const BiliApiException(-404, '啥都木有').isNotLogin, isFalse);
    });

    test('风控三兄弟：-352 / -412 / -799', () {
      expect(const BiliApiException(-352, '风控校验失败').isRiskControl, isTrue);
      expect(const BiliApiException(-412, '请求被拦截').isRiskControl, isTrue);
      expect(const BiliApiException(-799, '请求过于频繁').isRiskControl, isTrue);
      expect(const BiliApiException(-101, '账号未登录').isRiskControl, isFalse);
    });

    test('资源不存在', () {
      expect(const BiliApiException(-404, '啥都木有').isNotFound, isTrue);
      expect(const BiliApiException(62002, '稿件不可见').isNotFound, isTrue);
      expect(const BiliApiException(62004, '稿件审核中').isNotFound, isTrue);
    });

    test('业务错误的 statusCode 恒为 200', () {
      expect(const BiliApiException(-101, '账号未登录').statusCode, 200);
      expect(const BiliApiException(-101, '账号未登录').code, -101);
    });
  });

  group('传输层错误', () {
    test('可重试：超时 / 连接失败 / 408 / 429 / 5xx', () {
      expect(const BiliNetworkException(null, 'timeout').isRetryable, isTrue);
      expect(
        const BiliNetworkException(
          null,
          'timeout',
          isTimeout: true,
        ).isRetryable,
        isTrue,
      );
      expect(const BiliNetworkException(408, 'timeout').isRetryable, isTrue);
      expect(const BiliNetworkException(429, 'slow down').isRetryable, isTrue);
      expect(const BiliNetworkException(500, 'boom').isRetryable, isTrue);
      expect(
        const BiliNetworkException(503, 'unavailable').isRetryable,
        isTrue,
      );
    });

    test('不可重试：412（走补签链路）、304（该带 no-cache 重取）、4xx', () {
      expect(const BiliNetworkException(412, 'blocked').isRetryable, isFalse);
      expect(
        const BiliNetworkException(304, 'not modified').isRetryable,
        isFalse,
      );
      expect(const BiliNetworkException(404, 'nope').isRetryable, isFalse);
    });

    test('HTTP 412 也算风控（B 站用状态码表达）', () {
      expect(const BiliNetworkException(412, 'blocked').isRiskControl, isTrue);
      expect(const BiliNetworkException(500, 'boom').isRiskControl, isFalse);
    });

    test('statusCode 为 null 时 code 退化成 -1，否则保留真实状态码', () {
      expect(const BiliNetworkException(null, 'connect failed').code, -1);
      expect(const BiliNetworkException(503, 'unavailable').code, 503);
    });
  });

  group('解析错误', () {
    test('归到 BiliException 一把兜住，code 为 -1', () {
      const error = BiliParseException('响应不是合法 JSON', snippet: '{"a"');
      expect(error, isA<BiliException>());
      expect(error.code, -1);
      expect(error.statusCode, 200);
      expect(error.snippet, '{"a"');
    });

    test('三类异常都能被 seal 父类统一捕获', () {
      const List<BiliException> all = [
        BiliApiException(-101, '账号未登录'),
        BiliNetworkException(500, 'boom'),
        BiliParseException('坏 JSON'),
      ];
      for (final error in all) {
        expect(error, isA<BiliException>());
      }
    });
  });

  group('toString 带上排查线索', () {
    test('vVoucher / traceId 出现在文案里', () {
      const error = BiliApiException(
        -352,
        '风控校验失败',
        vVoucher: 'voucher-1',
        traceId: 'trace-1',
      );
      expect(error.toString(), contains('voucher-1'));
      expect(error.toString(), contains('trace-1'));
    });

    test('cause 出现在网络错误文案里', () {
      const error = BiliNetworkException(500, 'boom', cause: 'SocketException');
      expect(error.toString(), contains('SocketException'));
    });
  });
}
