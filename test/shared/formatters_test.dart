import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/shared/utils/formatters.dart';

void main() {
  group('formatCount', () {
    test('不足一万原样输出', () {
      expect(formatCount(0), '0');
      expect(formatCount(9999), '9999');
    });

    test('万 / 亿保留一位小数', () {
      expect(formatCount(10000), '1.0万');
      expect(formatCount(502170), '50.2万');
      expect(formatCount(123456789), '1.2亿');
    });
  });
}
