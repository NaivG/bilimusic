import 'package:bilimusic/app/shells/logic/mini_player_auto_hide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MiniPlayerAutoHide', () {
    test('向下滚动累计超过阈值后收起', () {
      final autoHide = MiniPlayerAutoHide(threshold: 10);

      expect(autoHide.update(4), isNull);
      expect(autoHide.update(4), isNull);
      expect(autoHide.update(4), isTrue);
    });

    test('向上滚动累计超过阈值后展开', () {
      final autoHide = MiniPlayerAutoHide(threshold: 10);
      autoHide.update(20);

      expect(autoHide.update(-4), isNull);
      expect(autoHide.update(-4), isNull);
      expect(autoHide.update(-4), isFalse);
    });

    test('方向反转时重新累计，小抖动不触发', () {
      final autoHide = MiniPlayerAutoHide(threshold: 10);

      expect(autoHide.update(8), isNull);
      expect(autoHide.update(-8), isNull);
      expect(autoHide.update(8), isNull);
      expect(autoHide.update(-8), isNull);
    });

    test('回到顶部时总是展开，并清空累计量', () {
      final autoHide = MiniPlayerAutoHide(threshold: 10);
      autoHide.update(50);

      expect(autoHide.update(-1, atTop: true), isFalse);
      expect(autoHide.update(4), isNull);
    });

    test('reset 后重新累计', () {
      final autoHide = MiniPlayerAutoHide(threshold: 10);

      expect(autoHide.update(8), isNull);
      autoHide.reset();
      expect(autoHide.update(8), isNull);
      expect(autoHide.update(3), isTrue);
    });
  });
}
