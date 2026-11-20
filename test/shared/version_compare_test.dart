import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/shared/utils/version_compare.dart';

void main() {
  group('compareVersions', () {
    test('相同版本返回 0', () {
      expect(compareVersions('1.12.0', '1.12.0'), 0);
    });

    test('忽略 build 号', () {
      expect(compareVersions('1.12.0+301', '1.12.0+300'), 0);
    });

    test('按 major / minor / patch 逐段比较', () {
      expect(compareVersions('2.0.0', '1.99.99'), 1);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
      expect(compareVersions('1.12.1', '1.12.0'), 1);
      expect(compareVersions('1.12.0', '1.12.1'), -1);
    });

    test('缺失的段按 0 处理', () {
      expect(compareVersions('1.12', '1.12.0'), 0);
      expect(compareVersions('1', '1.0.1'), -1);
    });

    test('非数字段按 0 处理，不抛异常', () {
      expect(compareVersions('dev', '0.0.0'), 0);
      expect(compareVersions('1.x.0', '1.0.0'), 0);
    });
  });
}
