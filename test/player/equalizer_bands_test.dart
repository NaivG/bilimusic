import 'dart:math' as math;

import 'package:bilimusic/features/player/logic/equalizer_bands.dart';
import 'package:bilimusic/features/settings/ui/audio_dsp_page.dart';
import 'package:bilimusic/features/settings/ui/widgets/equalizer_curve.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  /// 把模型拖到各种极端位置（贴着邻段下限 / 全局上下限），
  /// 用于验证切分不变量在最坏情况下依然成立。
  EqualizerBandModel extremeModel() {
    var m = EqualizerBandModel.flat();
    m = m.withBand(0, frequency: 20);
    m = m.withBand(1, frequency: 22); // 会被收敛到 32·1.1 = 35.2
    m = m.withBand(2, frequency: 36);
    m = m.withBand(3, frequency: 300);
    m = m.withBand(4, frequency: 280); // 收敛到 300/1.1
    m = m.withBand(5, frequency: 1000);
    m = m.withBand(6, frequency: 15000);
    m = m.withBand(7, frequency: 20000);
    return m;
  }

  group('EqualizerBandModel 频段切分', () {
    test('默认模型：8 段区间无缝铺满 [20Hz, 20kHz]，互不重叠也无空隙', () {
      final m = EqualizerBandModel.flat();

      expect(m.regionLeft(0), EqualizerBandModel.minFrequency);
      expect(m.regionRight(7), EqualizerBandModel.maxFrequency);
      for (var i = 0; i < EqualizerBandModel.bandCount - 1; i++) {
        expect(
          m.regionRight(i),
          closeTo(m.regionLeft(i + 1), 1e-9),
          reason: '频段 $i 与 ${i + 1} 的切分边界应重合',
        );
        expect(
          m.regionLeft(i),
          lessThan(m.regionRight(i)),
          reason: '频段 $i 的区间必须为正宽度',
        );
      }
    });

    test('极端拖拽后切分依然无缝、不重叠', () {
      final m = extremeModel();

      for (var i = 0; i < EqualizerBandModel.bandCount - 1; i++) {
        expect(m.regionRight(i), closeTo(m.regionLeft(i + 1), 1e-6));
      }
      // 频点严格递增且满足最小间隔
      for (var i = 1; i < EqualizerBandModel.bandCount; i++) {
        expect(
          m.frequencies[i],
          greaterThanOrEqualTo(m.frequencies[i - 1] * 1.1),
        );
      }
    });

    test('半带宽（-3dB 足点）不越出自己的切分区间（核心防重叠不变量）', () {
      for (final m in [EqualizerBandModel.flat(), extremeModel()]) {
        for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
          final f = m.frequencies[i];
          final w = m.bandwidthOf(i);
          final left = f - w / 2;
          final right = f + w / 2;
          if (i > 0) {
            expect(
              left,
              greaterThanOrEqualTo(m.regionLeft(i) - 1e-6),
              reason: '频段 $i 的 -3dB 足点踩进了左邻区间',
            );
          }
          if (i < EqualizerBandModel.bandCount - 1) {
            expect(
              right,
              lessThanOrEqualTo(m.regionRight(i) + 1e-6),
              reason: '频段 $i 的 -3dB 足点踩进了右邻区间',
            );
          }
        }
      }
    });

    test('首段贴 20Hz 的退化情形由最小带宽兜底，且不破坏右侧切分边界', () {
      final m = EqualizerBandModel.flat().withBand(0, frequency: 20);
      final f = m.frequencies[0];
      final w = m.bandwidthOf(0);
      // w 被 _minBandwidthHz 抬到 1Hz，-3dB 足点向左最多探出全域下限
      // 0.5Hz（20Hz 以下本就不可闻），向右绝不能越过切分边界。
      expect(
        f - w / 2,
        greaterThanOrEqualTo(EqualizerBandModel.minFrequency - 0.5),
      );
      expect(f + w / 2, lessThanOrEqualTo(m.regionRight(0) + 1e-6));
    });

    test('频点收敛：不可拖过邻段（最小间隔），也不可拖出全域', () {
      final m = EqualizerBandModel.flat(); // 32, 64, 125, 250, ...

      // 拖向左邻：收敛到 32·1.1
      expect(m.withBand(1, frequency: 31).frequencies[1], closeTo(35.2, 1e-9));
      // 拖向右邻：收敛到 250/1.1
      expect(
        m.withBand(2, frequency: 1e9).frequencies[2],
        closeTo(250 / 1.1, 1e-9),
      );
      // 全域边界
      expect(m.withBand(0, frequency: 5).frequencies[0], 20.0);
      expect(m.withBand(7, frequency: 25000).frequencies[7], 20000.0);
      // 区间内正常取值
      expect(m.withBand(3, frequency: 300).frequencies[3], 300.0);
    });

    test('增益收敛到 ±12 dB', () {
      final m = EqualizerBandModel.flat();
      expect(m.withBand(0, gainDb: 30).gainsDb[0], 12.0);
      expect(m.withBand(0, gainDb: -30).gainsDb[0], -12.0);
    });
  });

  group('EqualizerBandModel 响应曲线', () {
    test('段中心处恰好等于该段增益', () {
      var m = EqualizerBandModel.flat();
      for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
        m = m.withBand(i, gainDb: 6.0 + i);
      }
      for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
        expect(
          m.bandGainDbAt(i, m.frequencies[i]),
          closeTo(m.gainsDb[i], 1e-9),
        );
      }
    });

    test('邻段中心处的串扰远小于该段增益（带宽不糊到别人地盘）', () {
      var m = EqualizerBandModel.flat();
      for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
        m = m.withBand(i, gainDb: 12);
      }
      for (var i = 1; i < EqualizerBandModel.bandCount; i++) {
        final bleed = m.bandGainDbAt(i - 1, m.frequencies[i]);
        expect(
          bleed,
          lessThan(12 * 0.35),
          reason: '频段 ${i - 1} 在频段 $i 中心处的串扰过大',
        );
      }
    });

    test('合成响应 = 各段响应之和（级联滤波器在 dB 域相加）', () {
      final m = EqualizerBandModel.flat()
          .withBand(0, gainDb: 8)
          .withBand(3, gainDb: -6)
          .withBand(6, gainDb: 4);
      for (final f in [30.0, 100.0, 440.0, 1500.0, 8000.0, 18000.0]) {
        var sum = 0.0;
        for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
          sum += m.bandGainDbAt(i, f);
        }
        expect(m.combinedGainDbAt(f), closeTo(sum, 1e-9));
      }
    });

    test('合成响应在对数频率轴上平滑连续（无直上直下的台阶）', () {
      final m = EqualizerBandModel.flat()
          .withBand(0, gainDb: 12)
          .withBand(1, gainDb: -10)
          .withBand(2, gainDb: 9)
          .withBand(3, gainDb: -7)
          .withBand(4, gainDb: 11)
          .withBand(5, gainDb: -12)
          .withBand(6, gainDb: 10)
          .withBand(7, gainDb: -9);

      const samples = 800;
      var prev = m.combinedGainDbAt(EqualizerBandModel.minFrequency);
      for (var i = 1; i <= samples; i++) {
        final t = i / samples;
        final f =
            EqualizerBandModel.minFrequency *
            math.pow(
              EqualizerBandModel.maxFrequency / EqualizerBandModel.minFrequency,
              t,
            );
        final v = m.combinedGainDbAt(f);
        // 对数轴上 800 采样的相邻差应远小于单段增益幅度；
        // 若频段之间出现台阶，这里会出现接近增益绝对值的跳变。
        expect(
          (v - prev).abs(),
          lessThan(0.5),
          reason: 'f=$f 处合成响应出现跳变（Δ=${v - prev}）',
        );
        prev = v;
      }
    });
  });

  group('EqualizerBandModel 与 anequalizer 互转', () {
    test('toAnequalizerSettings 产出 8 段双通道 Butterworth peaking 参数', () {
      final m = EqualizerBandModel.flat()
          .withBand(0, gainDb: 6)
          .withBand(7, frequency: 12000, gainDb: -4);
      final s = m.toAnequalizerSettings(enabled: true);

      expect(s.enabled, true);
      final bands = s.bands;
      expect(bands.length, 8);
      for (var i = 0; i < 8; i++) {
        expect(
          bands[i].frequency,
          closeTo(m.frequencies[i], 0.02),
          reason: '频段 $i 频点',
        );
        expect(bands[i].gain, closeTo(m.gainsDb[i], 0.02), reason: '频段 $i 增益');
        expect(bands[i].bandwidth, closeTo(m.bandwidthOf(i), 0.02));
        expect(bands[i].type.wireValue, 0, reason: '统一使用 Butterworth t=0');
      }
      // params 串里每个逻辑频段带 c0/c1 两个通道
      expect('c0'.allMatches(s.params).length, 8);
      expect('c1'.allMatches(s.params).length, 8);
    });

    test('往返：模型 → 引擎参数 → 模型，频点与增益无损', () {
      final m = extremeModel()
          .withBand(2, gainDb: 5.5)
          .withBand(5, gainDb: -8.5);
      final s = m.toAnequalizerSettings(enabled: true);
      final back = EqualizerBandModel.fromAnequalizerSettings(s);

      for (var i = 0; i < EqualizerBandModel.bandCount; i++) {
        expect(back.frequencies[i], closeTo(m.frequencies[i], 0.02));
        expect(back.gainsDb[i], closeTo(m.gainsDb[i], 0.02));
      }
    });

    test('null / 段数不足 / 频点乱序的坏数据一律退回平坦默认', () {
      expect(
        EqualizerBandModel.fromAnequalizerSettings(null).gainsDb,
        everyElement(0.0),
      );

      // 只有 4 段的残缺参数
      final partial = (const AnequalizerSettings()).withBands([
        for (var i = 0; i < 4; i++)
          AnequalizerBand(frequency: 100.0 * (i + 1), bandwidth: 50, gain: 3),
      ]);
      expect(
        EqualizerBandModel.fromAnequalizerSettings(partial).frequencies,
        EqualizerBandModel.defaultFrequencies,
      );

      // 频点倒序（违反最小间隔）
      final unordered = (const AnequalizerSettings()).withBands([
        const AnequalizerBand(frequency: 1000, bandwidth: 100, gain: 1),
        const AnequalizerBand(frequency: 500, bandwidth: 100, gain: -1),
        ...List.generate(
          6,
          (i) => AnequalizerBand(
            frequency: 2000.0 * (i + 1),
            bandwidth: 100,
            gain: 0,
          ),
        ),
      ]);
      expect(
        EqualizerBandModel.fromAnequalizerSettings(unordered).gainsDb,
        everyElement(0.0),
      );
    });
  });

  group('EqualizerCurve 组件', () {
    testWidgets('渲染不抛错；拖拽回调收到经模型收敛的频点 / 增益', (tester) async {
      var model = EqualizerBandModel.flat();
      final changedBands = <int>{};
      var dragEnds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: EqualizerCurve(
                model: model,
                enabled: true,
                onBandChanged: (band, {frequency, gainDb}) {
                  changedBands.add(band);
                  model = model.withBand(
                    band,
                    frequency: frequency,
                    gainDb: gainDb,
                  );
                },
                onDragEnd: () => dragEnds++,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      // 从曲线中部（≈632Hz，最近的是 500Hz 段）向右下拖动：
      // 频点应被收敛在 500Hz 段的合法区间内，增益被收敛到 ±12dB。
      final center = tester.getCenter(find.byType(EqualizerCurve));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await gesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 20));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      // 双击识别器在松手后还会挂一个 kDoubleTapTimeout 的倒计时，
      // 推进假时钟把它消化掉，否则测试结束时残留 pending timer。
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(changedBands, isNotEmpty);
      expect(dragEnds, 1);
      final i = changedBands.first;
      final (low, high) = model.frequencyRange(i);
      expect(model.frequencies[i], inExclusiveRange(low - 1e-9, high + 1e-9));
      expect(model.gainsDb[i], inInclusiveRange(-12.0, 12.0));
      expect(model.gainsDb[i], isNot(0.0), reason: '向下拖动应改变增益');
    });
  });

  group('AudioDspPage 冒烟', () {
    testWidgets('默认渲染：开关 + 曲线 + 重置，无引擎写入路径', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AudioDspPage())),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('启用均衡器'), findsOneWidget);
      expect(find.byType(EqualizerCurve), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);
      // 默认（未配置过 anequalizer）开关应为关
      final sw = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('启用均衡器'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(sw.value, false);
    });
  });
}
