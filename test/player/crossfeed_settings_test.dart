import 'package:bilimusic/features/player/logic/crossfeed_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  group('CrossfeedSettingsModel 默认值', () {
    test('defaults() 与 lavfi 默认完全一致（strength=0.2 / range=0.5）', () {
      final m = CrossfeedSettingsModel.defaults();
      expect(m.strength, CrossfeedSettings.strengthDefault);
      expect(m.range, CrossfeedSettings.rangeDefault);
    });

    test('flat() == defaults()', () {
      expect(
        CrossfeedSettingsModel.flat().strength,
        CrossfeedSettingsModel.defaults().strength,
      );
      expect(
        CrossfeedSettingsModel.flat().range,
        CrossfeedSettingsModel.defaults().range,
      );
    });
  });

  group('CrossfeedSettingsModel 边界收敛', () {
    test('strength 越界 → 收敛到 [0, 1]', () {
      final hi = CrossfeedSettingsModel(strength: 1.7, range: 0.5);
      expect(hi.strength, 1.0);

      final lo = CrossfeedSettingsModel(strength: -0.3, range: 0.5);
      expect(lo.strength, 0.0);
    });

    test('range 越界 → 收敛到 [0, 1]', () {
      final hi = CrossfeedSettingsModel(strength: 0.2, range: 99);
      expect(hi.range, 1.0);

      final lo = CrossfeedSettingsModel(strength: 0.2, range: -99);
      expect(lo.range, 0.0);
    });
  });

  group('CrossfeedSettingsModel 不可变更新', () {
    test('withStrength() 不影响 range', () {
      final m = CrossfeedSettingsModel.defaults();
      final next = m.withStrength(0.8);
      expect(next.strength, 0.8);
      expect(next.range, m.range);
      expect(m.strength, CrossfeedSettings.strengthDefault);
    });

    test('withRange() 不影响 strength', () {
      final m = CrossfeedSettingsModel.defaults();
      final next = m.withRange(0.1);
      expect(next.range, 0.1);
      expect(next.strength, m.strength);
    });
  });

  group('CrossfeedSettingsModel ↔ mpv.CrossfeedSettings', () {
    test('toCrossfeedSettings(enabled=false) 给出非 enabled 的同参数包', () {
      final m = CrossfeedSettingsModel(strength: 0.4, range: 0.3);
      final s = m.toCrossfeedSettings(enabled: false);
      expect(s.enabled, false);
      expect(s.strength, 0.4);
      expect(s.range, 0.3);
      // 未触碰的 lavfi 字段走默认
      expect(s.level_in, CrossfeedSettings.level_inDefault);
      expect(s.level_out, CrossfeedSettings.level_outDefault);
      expect(s.slope, CrossfeedSettings.slopeDefault);
      expect(s.block_size, CrossfeedSettings.block_sizeDefault);
    });

    test('toCrossfeedSettings(enabled=true) 携带 enabled=true', () {
      final m = CrossfeedSettingsModel.defaults();
      final s = m.toCrossfeedSettings(enabled: true);
      expect(s.enabled, true);
    });

    test('fromCrossfeedSettings(null) 回退默认（绝不抛错）', () {
      final m = CrossfeedSettingsModel.fromCrossfeedSettings(null);
      expect(m.strength, CrossfeedSettings.strengthDefault);
      expect(m.range, CrossfeedSettings.rangeDefault);
    });

    test('round-trip：编辑 → toSettings → fromSettings 不丢值', () {
      final edited = CrossfeedSettingsModel(strength: 0.42, range: 0.77);
      final restored = CrossfeedSettingsModel.fromCrossfeedSettings(
        edited.toCrossfeedSettings(enabled: true),
      );
      expect(restored.strength, 0.42);
      expect(restored.range, 0.77);
    });

    test('round-trip 在边界值上仍保真（0 / 1）', () {
      for (final s in [0.0, 1.0]) {
        for (final r in [0.0, 1.0]) {
          final m = CrossfeedSettingsModel(strength: s, range: r);
          final restored = CrossfeedSettingsModel.fromCrossfeedSettings(
            m.toCrossfeedSettings(enabled: false),
          );
          expect(restored.strength, s);
          expect(restored.range, r);
        }
      }
    });
  });
}
