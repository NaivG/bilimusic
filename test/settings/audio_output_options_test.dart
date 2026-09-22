import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/settings/logic/audio_output_options.dart';

void main() {
  group('音频延迟量程与读数', () {
    test('clamp 夹住两端，区间内原样返回', () {
      expect(clampAudioDelay(0), 0);
      expect(clampAudioDelay(120), 120);
      expect(clampAudioDelay(-80), -80);
      expect(clampAudioDelay(99999), kAudioDelayMaxMs);
      expect(clampAudioDelay(-99999), kAudioDelayMinMs);
    });

    test('读数带符号，零不带', () {
      // 正数不带 + 就分不清「往左拖数字在变大」是控件坏了还是本来就负。
      expect(formatAudioDelay(0), '0 ms');
      expect(formatAudioDelay(120), '+120 ms');
      expect(formatAudioDelay(-80), '-80 ms');
    });

    test('超范围的读数先夹再格式化', () {
      expect(formatAudioDelay(4321), '+500 ms');
      expect(formatAudioDelay(-4321), '-500 ms');
    });

    test('分度数让步进正好是 10ms', () {
      final span = kAudioDelayMaxMs - kAudioDelayMinMs;
      expect(span / kAudioDelayDivisions, 10);
    });
  });

  group('DAC 采样率档位表', () {
    test('第一档是自动，其余按采样率升序且不重复', () {
      expect(kDacSampleRates.first.rate, 0);
      final rates = [for (final o in kDacSampleRates) o.rate];
      expect(rates.toSet().length, rates.length, reason: '档位重复会让下拉命中错 item');
      final real = rates.skip(1).toList();
      expect(real, equals([...real]..sort()));
    });

    test('档位都有文案', () {
      for (final o in kDacSampleRates) {
        expect(o.label, isNotEmpty, reason: 'rate=${o.rate} 缺文案');
      }
    });
  });

  group('设备列表并集', () {
    const a = mpv.Device(name: 'wasapi/{a}', description: '耳机');
    const b = mpv.Device(name: 'wasapi/{b}', description: '扬声器');

    test('两路各报一份时按 name 去重、保持首见顺序', () {
      final merged = mergeAudioDevices([
        [a, b],
        [b, a],
      ]);
      expect(merged.map((d) => d.name), ['wasapi/{a}', 'wasapi/{b}']);
    });

    test('丢掉 mpv 的 auto 哨兵与空名——UI 自己渲染「自动」那一行', () {
      const auto = mpv.Device.auto;
      final merged = mergeAudioDevices([
        [auto, a],
        [auto, const mpv.Device(name: '', description: '坏的'), b],
      ]);
      expect(merged.map((d) => d.name), ['wasapi/{a}', 'wasapi/{b}']);
    });

    test('mpv 还没报真设备时（只有 auto）归一成空列表', () {
      expect(
        mergeAudioDevices([
          [mpv.Device.auto],
          [mpv.Device.auto],
        ]),
        isEmpty,
      );
    });

    test('设备被拔掉后再次下发的清单能收缩', () {
      // 不是「追加合并」：每次都拿两路的**当前**快照重算。
      expect(
        mergeAudioDevices([
          [a],
          [a],
        ]),
        [a],
      );
      expect(mergeAudioDevices([<mpv.Device>[], <mpv.Device>[]]), isEmpty);
    });
  });

  group('「跟随系统」的两种写法归一', () {
    test('空串与 mpv 的 auto 是同一个意思', () {
      expect(normalizeDeviceName(''), '');
      expect(normalizeDeviceName('auto'), '');
      expect(normalizeDeviceName('wasapi/{a}'), 'wasapi/{a}');
    });
  });
}
