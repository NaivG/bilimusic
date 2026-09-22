import 'dart:math' as math;

import 'package:bilimusic/features/player/logic/compressor_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  group('CompressorSettingsModel 默认值', () {
    test('defaults() 与 lavfi 默认完全一致', () {
      final m = CompressorSettingsModel.defaults();
      // threshold: 0.125 (lavfi default) → ≈ -18.06 dB
      expect(m.thresholdDb, closeTo(20 * math.log(0.125) / math.ln10, 1e-9));
      expect(m.ratio, AcompressorSettings.ratioDefault);
      expect(m.attackMs, AcompressorSettings.attackDefault);
      expect(m.releaseMs, AcompressorSettings.releaseDefault);
      // makeup: 1.0 (lavfi default) → 0 dB
      expect(m.makeupDb, 0.0);
    });

    test('flat() == defaults()', () {
      expect(
        CompressorSettingsModel.flat().thresholdDb,
        CompressorSettingsModel.defaults().thresholdDb,
      );
      expect(
        CompressorSettingsModel.flat().ratio,
        CompressorSettingsModel.defaults().ratio,
      );
    });
  });

  group('CompressorSettingsModel 边界收敛', () {
    test('thresholdDb 越界 → 收敛到 [-60, 0]', () {
      expect(
        CompressorSettingsModel(
          thresholdDb: 99,
          ratio: 2,
          attackMs: 20,
          releaseMs: 250,
          makeupDb: 0,
        ).thresholdDb,
        0.0,
      );
      expect(
        CompressorSettingsModel(
          thresholdDb: -999,
          ratio: 2,
          attackMs: 20,
          releaseMs: 250,
          makeupDb: 0,
        ).thresholdDb,
        -60.0,
      );
    });

    test('ratio 越界 → 收敛到 [1, 20]', () {
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 0.1,
          attackMs: 20,
          releaseMs: 250,
          makeupDb: 0,
        ).ratio,
        1.0,
      );
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 99,
          attackMs: 20,
          releaseMs: 250,
          makeupDb: 0,
        ).ratio,
        20.0,
      );
    });

    test('attackMs 越界 → 收敛到 lavfi 范围 [0.01, 2000]', () {
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 2,
          attackMs: 0,
          releaseMs: 250,
          makeupDb: 0,
        ).attackMs,
        0.01,
      );
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 2,
          attackMs: 99999,
          releaseMs: 250,
          makeupDb: 0,
        ).attackMs,
        2000.0,
      );
    });

    test('releaseMs 越界 → 收敛到 lavfi 范围 [0.01, 9000]', () {
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 2,
          attackMs: 20,
          releaseMs: 0,
          makeupDb: 0,
        ).releaseMs,
        0.01,
      );
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 2,
          attackMs: 20,
          releaseMs: 99999,
          makeupDb: 0,
        ).releaseMs,
        9000.0,
      );
    });

    test('makeupDb 越界 → 收敛到 UI 范围 [0, 24]', () {
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 2,
          attackMs: 20,
          releaseMs: 250,
          makeupDb: 99,
        ).makeupDb,
        24.0,
      );
      expect(
        CompressorSettingsModel(
          thresholdDb: -18,
          ratio: 2,
          attackMs: 20,
          releaseMs: 250,
          makeupDb: -10,
        ).makeupDb,
        0.0,
      );
    });
  });

  group('CompressorSettingsModel 不可变更新', () {
    test('withXxx() 只改对应字段', () {
      final base = CompressorSettingsModel.defaults();
      final t = base.withThresholdDb(-12);
      expect(t.thresholdDb, -12);
      expect(t.ratio, base.ratio);
      expect(t.attackMs, base.attackMs);
      expect(t.releaseMs, base.releaseMs);
      expect(t.makeupDb, base.makeupDb);

      final r = base.withRatio(8);
      expect(r.ratio, 8);
      expect(r.thresholdDb, base.thresholdDb);

      final a = base.withAttackMs(50);
      expect(a.attackMs, 50);
      expect(a.releaseMs, base.releaseMs);

      final rel = base.withReleaseMs(500);
      expect(rel.releaseMs, 500);
      expect(rel.attackMs, base.attackMs);

      final mu = base.withMakeupDb(6);
      expect(mu.makeupDb, 6);
      expect(mu.thresholdDb, base.thresholdDb);
    });

    test('基础字段未被覆盖', () {
      final base = CompressorSettingsModel(
        thresholdDb: -12,
        ratio: 4,
        attackMs: 30,
        releaseMs: 300,
        makeupDb: 2,
      );
      final next = base.withThresholdDb(-6);
      expect(next.thresholdDb, -6);
      expect(next.ratio, 4);
      expect(next.attackMs, 30);
      expect(next.releaseMs, 300);
      expect(next.makeupDb, 2);
    });
  });

  group('amplitudeToDb / dbToAmplitude', () {
    test('amplitudeToDb(1) = 0 dBFS', () {
      expect(CompressorSettingsModel.amplitudeToDb(1.0), closeTo(0.0, 1e-9));
    });

    test('dbToAmplitude(0) = 1.0（穿 dB↔amp 一次回到 0 dB）', () {
      expect(CompressorSettingsModel.dbToAmplitude(0), 1.0);
    });

    test('amplitudeToDb(0.5) ≈ -6.02 dB', () {
      expect(
        CompressorSettingsModel.amplitudeToDb(0.5),
        closeTo(-6.0206, 1e-3),
      );
    });

    test('round-trip: amp → dB → amp 保真（无明显舍入误差）', () {
      for (final amp in [0.001, 0.01, 0.125, 0.5, 1.0]) {
        final db = CompressorSettingsModel.amplitudeToDb(amp);
        final back = CompressorSettingsModel.dbToAmplitude(db);
        expect(back, closeTo(amp, 1e-9));
      }
    });

    test('amplitudeToDb(0) 返回 floor（防 log10(-inf)）', () {
      expect(CompressorSettingsModel.amplitudeToDb(0), -120.0);
      expect(CompressorSettingsModel.amplitudeToDb(-1), -120.0);
    });

    test('amplitudeToDb 自定义 floor', () {
      expect(CompressorSettingsModel.amplitudeToDb(0, floor: -60), -60.0);
    });
  });

  group('CompressorSettingsModel ↔ mpv.AcompressorSettings', () {
    test('toAcompressorSettings(enabled=true) 把 dB 字段转回 amp', () {
      final m = CompressorSettingsModel(
        thresholdDb: -18,
        ratio: 2,
        attackMs: 20,
        releaseMs: 250,
        makeupDb: 0,
      );
      final s = m.toAcompressorSettings(enabled: true);
      expect(s.enabled, true);
      // threshold -18 dB → amp ≈ 0.125
      expect(s.threshold, closeTo(0.125, 1e-3));
      expect(s.ratio, 2.0);
      expect(s.attack, 20.0);
      expect(s.release, 250.0);
      // makeup 0 dB → amp = 1.0
      expect(s.makeup, closeTo(1.0, 1e-9));
    });

    test('toAcompressorSettings 不修改用户未触碰的 lavfi 字段', () {
      final m = CompressorSettingsModel.defaults();
      final s = m.toAcompressorSettings(enabled: false);
      // 这些是 UI 不暴露的字段，必须保持 lavfi 默认以免与 codec 落盘形状冲突。
      expect(s.knee, AcompressorSettings.kneeDefault);
      expect(s.level_in, AcompressorSettings.level_inDefault);
      expect(s.level_sc, AcompressorSettings.level_scDefault);
      expect(s.link, AcompressorLink.average);
      expect(s.mode, AcompressorMode.downward);
      expect(s.detection, AcompressorDetection.rms);
      expect(s.mix, AcompressorSettings.mixDefault);
    });

    test('fromAcompressorSettings(null) 回退默认（绝不抛错）', () {
      final m = CompressorSettingsModel.fromAcompressorSettings(null);
      expect(
        m.thresholdDb,
        closeTo(
          CompressorSettingsModel.amplitudeToDb(
            AcompressorSettings.thresholdDefault,
          ),
          1e-9,
        ),
      );
      expect(m.ratio, AcompressorSettings.ratioDefault);
      expect(m.attackMs, AcompressorSettings.attackDefault);
      expect(m.releaseMs, AcompressorSettings.releaseDefault);
      expect(m.makeupDb, closeTo(0.0, 1e-9));
    });

    test('round-trip：编辑 → toSettings → fromSettings 不丢值', () {
      final edited = CompressorSettingsModel(
        thresholdDb: -12,
        ratio: 4,
        attackMs: 50,
        releaseMs: 400,
        makeupDb: 3,
      );
      final restored = CompressorSettingsModel.fromAcompressorSettings(
        edited.toAcompressorSettings(enabled: true),
      );
      expect(restored.thresholdDb, closeTo(-12.0, 1e-3));
      expect(restored.ratio, 4.0);
      expect(restored.attackMs, 50.0);
      expect(restored.releaseMs, 400.0);
      expect(restored.makeupDb, closeTo(3.0, 1e-3));
    });

    test('round-trip 在极端值（UI 边界）仍保真', () {
      for (final thresholdDb in [-60.0, 0.0]) {
        for (final ratio in [1.0, 20.0]) {
          for (final makeupDb in [0.0, 24.0]) {
            final m = CompressorSettingsModel(
              thresholdDb: thresholdDb,
              ratio: ratio,
              attackMs: 20,
              releaseMs: 250,
              makeupDb: makeupDb,
            );
            final restored = CompressorSettingsModel.fromAcompressorSettings(
              m.toAcompressorSettings(enabled: false),
            );
            expect(restored.thresholdDb, closeTo(thresholdDb, 1e-3));
            expect(restored.ratio, ratio);
            expect(restored.makeupDb, closeTo(makeupDb, 1e-3));
          }
        }
      }
    });
  });
}
