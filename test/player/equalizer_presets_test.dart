import 'dart:math' as math;

import 'package:bilimusic/features/player/logic/equalizer_bands.dart';
import 'package:bilimusic/features/player/logic/equalizer_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 全部内置预设摊平（跨组）。
  List<EqualizerPreset> allPresets() => [
    for (final g in kEqualizerPresetGroups) ...g.presets,
  ];

  group('sampleEqCurve 目标曲线采样', () {
    test('区间外取最近端点的值', () {
      const curve = [(freq: 100.0, gain: 3.0), (freq: 1000.0, gain: -1.0)];
      expect(sampleEqCurve([50, 100], curve), [3.0, 3.0]);
      expect(sampleEqCurve([1000, 5000], curve), [-1.0, -1.0]);
    });

    test('log 频率域线性插值：几何中点恰为增益中点', () {
      // 1000 是 100 与 10000 的几何中点 ⇒ t = 0.5。
      const curve = [(freq: 100.0, gain: 0.0), (freq: 10000.0, gain: 6.0)];
      expect(sampleEqCurve([1000], curve), [closeTo(3.0, 1e-9)]);
    });

    test('多段曲线逐段插值，与手工公式一致', () {
      const multi = [
        (freq: 20.0, gain: 5.0),
        (freq: 160.0, gain: 4.0),
        (freq: 400.0, gain: 1.5),
      ];
      final gains = sampleEqCurve([80, 320, 160], multi);
      final t80 =
          (math.log(80) - math.log(20)) / (math.log(160) - math.log(20));
      final t320 =
          (math.log(320) - math.log(160)) / (math.log(400) - math.log(160));
      expect(gains[0], closeTo(5 + t80 * (4 - 5), 1e-9));
      expect(gains[1], closeTo(4 + t320 * (1.5 - 4), 1e-9));
      expect(gains[2], 4.0); // 恰在控制点上，无插值误差。
    });

    test('控制点不足 / 频点不升序时 assert 失败', () {
      expect(
        () => sampleEqCurve([100], [(freq: 200.0, gain: 1.0)]),
        throwsAssertionError,
      );
      expect(
        () => sampleEqCurve(
          [100],
          [(freq: 200.0, gain: 1.0), (freq: 100.0, gain: 0.0)],
        ),
        throwsAssertionError,
      );
    });
  });

  group('内置预设数据质量', () {
    test('分组有标题、预设 id 全局唯一', () {
      expect(kEqualizerPresetGroups, isNotEmpty);
      final presets = allPresets();
      expect(presets.length, greaterThanOrEqualTo(6));
      for (final g in kEqualizerPresetGroups) {
        expect(g.title, isNotEmpty);
        expect(g.presets, isNotEmpty, reason: '${g.title} 组为空');
      }
      expect(presets.map((p) => p.id).toSet().length, presets.length);
    });

    test('每个预设：8 段、频点合法、增益在 ±12 dB', () {
      for (final p in allPresets()) {
        final m = p.model;
        expect(
          m.frequencies,
          hasLength(EqualizerBandModel.bandCount),
          reason: p.id,
        );
        expect(
          m.gainsDb,
          hasLength(EqualizerBandModel.bandCount),
          reason: p.id,
        );
        expect(m.hasValidFrequencies, isTrue, reason: '${p.id} 频点不合法');
        for (final g in m.gainsDb) {
          expect(
            g,
            inInclusiveRange(
              EqualizerBandModel.minGainDb,
              EqualizerBandModel.maxGainDb,
            ),
            reason: p.id,
          );
        }
      }
    });

    test('每个预设往返 anequalizer 无损（预设数据可安全下发引擎）', () {
      for (final p in allPresets()) {
        final back = EqualizerBandModel.fromAnequalizerSettings(
          p.model.toAnequalizerSettings(enabled: true),
        );
        for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
          expect(
            back.frequencies[i],
            closeTo(p.model.frequencies[i], 0.02),
            reason: '${p.id} 段 $i 频点',
          );
          expect(
            back.gainsDb[i],
            closeTo(p.model.gainsDb[i], 0.02),
            reason: '${p.id} 段 $i 增益',
          );
        }
      }
    });

    test('听感预设 = 自定义频点 + 目标曲线采样（钉住 fullerBass 定义）', () {
      const anchors = [40.0, 80.0, 160.0, 320.0, 640.0, 1250.0, 2500.0, 5000.0];
      const target = [
        (freq: 20.0, gain: 5.0),
        (freq: 160.0, gain: 4.0),
        (freq: 400.0, gain: 1.5),
        (freq: 800.0, gain: 0.3),
        (freq: 1600.0, gain: 0.0),
        (freq: 20000.0, gain: 0.0),
      ];
      final p = allPresets().firstWhere((e) => e.id == 'fullerBass');
      expect(p.model.frequencies, anchors);
      expect(p.model.gainsDb, sampleEqCurve(anchors, target));
      // 频点不是 defaultFrequencies——预设不必死磕默认 8 段。
      expect(
        p.model.frequencies,
        isNot(equals(EqualizerBandModel.defaultFrequencies)),
      );
    });

    test('耳机校准参考数据不被误改（Harman / AutoEq 原始采样）', () {
      const expected = {
        'harman-over-ear-2018': (
          freqs: [26.3, 47.2, 215.4, 505.8, 1046.1, 3242.2, 6648.4, 12843.1],
          gains: [2.08, 1.53, -4.30, -2.12, -2.55, 7.16, 1.75, -7.84],
        ),
        'harman-in-ear-2019': (
          freqs: [27.7, 51.2, 252.0, 604.8, 1127.2, 3073.8, 5976.9, 10964.8],
          gains: [4.93, 3.22, -5.17, -3.68, -2.89, 6.43, 3.08, -5.66],
        ),
        'autoeq-in-ear': (
          freqs: [28.9, 64.9, 146.7, 325.6, 772.4, 3011.0, 6716.3, 12219.8],
          gains: [-1.78, -1.49, -1.49, -1.58, -1.31, 8.04, 4.31, -5.70],
        ),
      };
      for (final entry in expected.entries) {
        final p = allPresets().firstWhere((e) => e.id == entry.key);
        final ref = entry.value;
        for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
          expect(
            p.model.frequencies[i],
            closeTo(ref.freqs[i], 1e-9),
            reason: '${entry.key} 段 $i 频点',
          );
          expect(
            p.model.gainsDb[i],
            closeTo(ref.gains[i], 1e-9),
            reason: '${entry.key} 段 $i 增益',
          );
        }
      }
    });
  });
}
