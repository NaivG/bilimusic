import 'package:bilimusic/features/player/logic/echo_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  group('AechoParams.firstOf', () {
    test('取 `|` 分隔列表的第一段', () {
      expect(AechoParams.firstOf('1000|250', 0), 1000);
      expect(AechoParams.firstOf('0.35|0.5', 0), 0.35);
    });

    test('逗号分隔也能取（lavfi 列表分隔符两种写法都见过）', () {
      expect(AechoParams.firstOf('480,200', 0), 480);
    });

    test('空串 / null / 前导空白 / 解析不出来都回 fallback', () {
      expect(AechoParams.firstOf(null, 7), 7);
      expect(AechoParams.firstOf('', 7), 7);
      expect(AechoParams.firstOf('|250', 7), 7);
      expect(AechoParams.firstOf('abc', 7), 7);
      expect(AechoParams.firstOf(' 120 ', 0), 120);
    });
  });

  group('AechoParams.single', () {
    test('整数不带小数点（与 lavfi 默认串同形，否则默认值被当成改动）', () {
      // `AechoSettings.toFilterString()` 是拿字符串和 '1000' 比的：
      // 写成 '1000.0' 会让默认状态也判定为「非默认」，每次重建 af 链。
      expect(AechoParams.single(1000), '1000');
      expect(AechoParams.single(0.5), '0.5');
      expect(AechoParams.single(0), '0');
    });

    test('非整数原样保留小数', () {
      expect(AechoParams.single(0.35), '0.35');
      expect(AechoParams.single(250.25), '250.25');
    });

    test('写回去再读回来保真（与 firstOf 配对使用）', () {
      for (final v in <double>[1, 120, 1000, 0.01, 0.5, 0.95]) {
        expect(AechoParams.firstOf(AechoParams.single(v), -1), v);
      }
    });
  });

  group('AechoParams.delayOf / decayOf', () {
    test('未配置时回 lavfi 构造默认', () {
      expect(AechoParams.delayOf(null), 1000);
      expect(AechoParams.decayOf(null), 0.5);
      expect(
        AechoParams.delayOf(null),
        double.parse(const AechoSettings().delays),
      );
      expect(
        AechoParams.decayOf(null),
        double.parse(const AechoSettings().decays),
      );
    });

    test('多段列表取第一段', () {
      const s = AechoSettings(delays: '480|200', decays: '0.35|0.7');
      expect(AechoParams.delayOf(s), 480);
      expect(AechoParams.decayOf(s), 0.35);
    });

    test('坏数据不抛，回 fallback', () {
      const s = AechoSettings(delays: '??', decays: '');
      expect(AechoParams.delayOf(s), 1000);
      expect(AechoParams.decayOf(s), 0.5);
    });
  });
}
