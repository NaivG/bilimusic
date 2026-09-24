import 'dart:math' as math;

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/logic/audio_effects_service.dart';
import 'package:bilimusic/features/player/logic/equalizer_bands.dart';
import 'package:bilimusic/features/settings/ui/audio_dsp_page.dart';
import 'package:bilimusic/features/settings/ui/widgets/compressor_curve.dart';
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

    testWidgets('窄视口：曲线区按下即抓最近频段；顶部滚动条只滚不抓，滚过后同一坐标抓到滚过来的频段', (tester) async {
      // 竖屏手机（shortestSide < 600）→ 触屏档 → 内容被撑到 ~573dp > 视口：
      // 可滚，顶部出现专用滚动条；曲线区按下即抓最近频段（没有热区）。
      // 默认 800×600 视口走的是指针档，所以下面必须显式把视口拧到竖屏，
      // 否则整个场景不会出现。
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var model = EqualizerBandModel.flat();
      final changedBands = <int>{};
      var dragEnds = 0;

      Future<void> pumpCurve() => tester.pumpWidget(
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

      await pumpCurve();
      expect(tester.takeException(), isNull);

      // 触屏档布局契约（与 equalizer_curve.dart 的几何常量对齐，
      // 改 _EqMetrics.touch.minBandSpacing 时这里跟着改）：
      // _minDefaultDeltaT 取默认频点里**最紧的一对 64↔125**（不是 64↔32），
      // 52dp ⇒ plot 宽 52/Δt ≈ 536.6dp；节点 x = 6 + t(f)·plotW，
      // t = ln(f/20)/ln(1000)。
      const spacing = 52.0;
      const leftPad = 6.0;
      const rightGutter = 30.0;
      final dT = math.log(125 / 64) / math.log(1000);
      final plotW = spacing / dT;
      final contentW = plotW + leftPad + rightGutter;
      final maxScroll = contentW - 360;
      double flatNodeX(int i) =>
          leftPad +
          math.log(EqualizerBandModel.defaultFrequencies[i] / 20) /
              math.log(1000) *
              plotW;

      final origin = tester.getTopLeft(find.byType(EqualizerCurve));
      Future<TestGesture> pressAt(Offset local) =>
          tester.startGesture(origin + local);

      // ── ① 曲线区（旧版热区之间的「留白」）按下并横拖：现在就是抓最近 ──
      var g = await pressAt(Offset((flatNodeX(0) + flatNodeX(1)) / 2, 118));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(changedBands, isNotEmpty, reason: '曲线区按下即抓最近频段，不再按列收热区');
      expect(dragEnds, 1);
      final band = changedBands.first;
      expect(model.gainsDb[band], 0.0, reason: '纯横向拖动不该改增益');
      final (low, high) = model.frequencyRange(band);
      expect(
        model.frequencies[band],
        inExclusiveRange(low - 1e-9, high + 1e-9),
        reason: '频点被横向拖走并被收敛在该频段的合法区间',
      );

      // ── ② 顶部滚动条（触屏档 topPad=16，按进 y=8 就是点击带）：按在滑块
      //       上（scroll=0 时滑块从 0 铺到 ~207dp，x=20 在其上）相对拖动
      //       → 只有滚动：零频点回调、零提交。拖到换算超出 maxScroll，
      //       收敛在滚到头。 ────────────────────────────────────────
      g = await pressAt(const Offset(20, 8));
      await tester.pump(const Duration(milliseconds: 400));
      for (var k = 0; k < 4; k++) {
        await g.moveBy(const Offset(60, 0));
        await tester.pump(const Duration(milliseconds: 400));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(changedBands, {band}, reason: '拖滚动条不该碰到任何频点');
      expect(dragEnds, 1, reason: '拖滚动条不是编辑，不该提交');

      // ── ③ 滚动真的发生了：滚到头后，10kHz 段被送到视口 x =
      //       flatNodeX(7) − maxScroll 处；在这里按下抓到的必须是它，
      //       而不是原来在那个坐标附近的 1kHz 段（已被滚出视口左侧）。
      //       要 move **两次**：越过 slop 的那一下只触发 onPanStart，
      //       频点回调在后续的 update 里发。 ────────────────────────
      g = await pressAt(Offset(flatNodeX(7) - maxScroll, 118));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(changedBands, {band, 7}, reason: '滚过来的是 10kHz 段，同一坐标抓到的应该是它');
      expect(model.gainsDb[7], isNot(0.0), reason: '纵向拖动应改变增益');
      expect(dragEnds, 2);
    });

    testWidgets('窄视口：按在滚动条轨道上（滑块之外）先跳转再拖动', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

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

      const spacing = 52.0;
      const leftPad = 6.0;
      const rightGutter = 30.0;
      final dT = math.log(125 / 64) / math.log(1000);
      final plotW = spacing / dT;
      final maxScroll = plotW + leftPad + rightGutter - 360;
      double flatNodeX(int i) =>
          leftPad +
          math.log(EqualizerBandModel.defaultFrequencies[i] / 20) /
              math.log(1000) *
              plotW;

      final origin = tester.getTopLeft(find.byType(EqualizerCurve));
      Future<TestGesture> pressAt(Offset local) =>
          tester.startGesture(origin + local);

      // 滑块宽 ≈ 207dp：按 x=300 落在滑块之外 → 轨道跳转，滑块中心对齐到
      // 按下处 ⇒ scroll = (300−103.7)/122.5 × 212.6 ≈ 340 → 钳到最大。
      final g = await pressAt(const Offset(300, 8));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await g.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(changedBands, isEmpty, reason: '滚动条跳转不该碰到任何频点');
      expect(dragEnds, 0, reason: '滚动条跳转不是编辑，不该提交');

      // 跳转真的落到了头：10kHz 段出现在视口 x = flatNodeX(7) − maxScroll。
      final g2 = await pressAt(Offset(flatNodeX(7) - maxScroll, 118));
      await tester.pump(const Duration(milliseconds: 400));
      await g2.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 400));
      await g2.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 400));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(changedBands, {7}, reason: '跳转滚到头后，同一坐标抓到的应该是 10kHz 段');
      expect(model.gainsDb[7], isNot(0.0));
      expect(dragEnds, 1);
    });
  });

  group('AudioDspPage 冒烟', () {
    /// 页面上 9 个折叠模块的头部标题（顺序即信号链顺序）。
    const moduleTitles = [
      '均衡器',
      '交叉回馈',
      '压缩器',
      '低频激励',
      '高频谐波激励',
      '回声',
      '限幅器',
      '立体声宽度',
      '环绕上混',
    ];

    /// 给一个较高的 viewport：ListView 懒构建，视口外的模块不会挂载，
    /// 断言会扑空。
    void enlargeViewport(WidgetTester tester, double height) {
      tester.view.physicalSize = Size(1080, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    testWidgets('默认渲染：9 个同构折叠模块全部收起，无引擎写入路径', (tester) async {
      enlargeViewport(tester, 2400);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AudioDspPage())),
      );
      expect(tester.takeException(), isNull);

      // ── 9 个模块头一字不差地都在 ────────────────────────────
      for (final title in moduleTitles) {
        expect(find.text(title), findsOneWidget, reason: '缺少模块「$title」');
      }

      // 头部的开关与正文无关：收起时 9 个开关照常可见（这就是
      // 「收起也能一眼看完全部开关」的前提）。
      expect(find.byType(Switch), findsNWidgets(9));

      // ── 正文整棵卸载（不是隐藏）─────────────────────────────
      // 全部未启用 → 全部收起，正文连树都没进。
      expect(find.byType(EqualizerCurve), findsNothing);
      expect(find.byTooltip('预设'), findsNothing);
      expect(find.text('重置'), findsNothing);

      // 头部第二行是参数快照，不是重复的开 / 关状态。
      expect(find.text('8 段 · 平直'), findsOneWidget);
    });

    testWidgets('点头部展开 / 收起：正文挂载与卸载，开关数量不变', (tester) async {
      enlargeViewport(tester, 2400);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AudioDspPage())),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('均衡器'));
      await tester.pumpAndSettle();

      expect(find.byType(EqualizerCurve), findsOneWidget);
      expect(find.byTooltip('预设'), findsOneWidget);
      expect(find.text('重置'), findsNWidgets(1));
      // 展开只动正文，不增减头部。
      expect(find.byType(Switch), findsNWidgets(9));

      // 再点一次收起：正文卸载、重置入口消失，头部原样留着。
      await tester.tap(find.text('均衡器'));
      await tester.pumpAndSettle();

      expect(find.byType(EqualizerCurve), findsNothing);
      expect(find.text('重置'), findsNothing);
      expect(find.byType(Switch), findsNWidgets(9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('已启用的效果器默认展开，未启用的收起', (tester) async {
      enlargeViewport(tester, 2400);

      // 预置「只开着压缩器」的效果包：展开态没有被手动点过，
      // 因此应当直接落到「跟开关走」这条推导上。
      final svc = AudioEffectsService();
      svc.effects.value = const AudioEffects().copyWith(
        acompressor: AcompressorSettings(enabled: true),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioEffectsServiceProvider.overrideWithValue(svc)],
          child: const MaterialApp(home: AudioDspPage()),
        ),
      );
      expect(tester.takeException(), isNull);

      expect(find.byType(CompressorCurve), findsOneWidget);
      expect(find.byType(EqualizerCurve), findsNothing);
      expect(find.text('重置'), findsNWidgets(1));
      // 开关状态与展开状态一致：9 个开关，只有压缩器那个是开的。
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.where((s) => s.value), hasLength(1));
    });
  });
}
