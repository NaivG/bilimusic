import 'dart:convert';

import 'package:bilimusic/features/player/logic/effects_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

void main() {
  group('EffectsCodec.decode', () {
    test('空 Map 解码出全禁用的默认包（curated 槽位全部补齐）', () {
      final e = EffectsCodec.decode(const {});

      expect(e.superequalizer?.enabled, false);
      expect(e.superequalizer?.params, isEmpty);
      expect(e.acompressor?.enabled, false);
      expect(e.acompressor?.threshold, AcompressorSettings.thresholdDefault);
      expect(e.bass?.enabled, false);
      expect(e.bass?.gain, 0.0);
      expect(e.bass?.frequency, BassSettings.frequencyDefault);
      expect(e.treble?.enabled, false);
      expect(e.crossfeed?.enabled, false);
      expect(e.crystalizer?.enabled, false);
      expect(e.extrastereo?.enabled, false);
      expect(e.asubboost?.enabled, false);
      expect(e.aexciter?.enabled, false);
      expect(e.aecho?.enabled, false);
      expect(e.aecho?.delays, const AechoSettings().delays);
      expect(e.aecho?.decays, const AechoSettings().decays);
      expect(e.alimiter?.enabled, false);
      expect(e.alimiter?.limit, AlimiterSettings.limitDefault);
      expect(e.surround?.enabled, false);
      expect(e.surround?.angle, SurroundSettings.angleDefault);
      expect(e.loudnorm?.enabled, false);
      expect(e.loudnorm?.linear, true);
    });

    test('部分键缺失时缺什么补什么默认值（向前向后兼容）', () {
      final e = EffectsCodec.decode({
        'bass': {'enabled': true, 'gain': 5.5},
      });

      expect(e.bass?.enabled, true);
      expect(e.bass?.gain, 5.5);
      // 缺失的键回默认
      expect(e.bass?.frequency, BassSettings.frequencyDefault);
      // 未提到的槽位仍是禁用默认
      expect(e.treble?.enabled, false);
      expect(e.loudnorm?.enabled, false);
    });

    test('类型不对的值不抛错，回默认', () {
      final e = EffectsCodec.decode({
        'bass': '不是 Map',
        'eq': {'params': '也不是 Map'},
      });

      expect(e.bass?.enabled, false);
      expect(e.superequalizer?.params, isEmpty);
    });

    test('eq params 的 num 值归一成 double，非法键忽略', () {
      final e = EffectsCodec.decode({
        'eq': {
          'enabled': true,
          'params': {'1b': 2, '9b': 0.5, 'bad': 'x'},
        },
      });

      expect(e.superequalizer?.enabled, true);
      expect(e.superequalizer?.params['1b'], 2.0);
      expect(e.superequalizer?.params['9b'], 0.5);
      expect(e.superequalizer?.params.containsKey('bad'), false);
    });

    test('缺 aneq 键的旧数据按默认值补齐（向前兼容）', () {
      final e = EffectsCodec.decode({
        'eq': {'enabled': true},
      });

      expect(e.anequalizer?.enabled, false);
      expect(e.anequalizer?.params, isEmpty);
    });

    test('缺 exciter / echo / limiter / surround 键的旧数据按默认值补齐', () {
      final e = EffectsCodec.decode({
        'subboost': {'enabled': true, 'boost': 4},
      });

      expect(e.asubboost?.enabled, true);
      expect(e.aexciter?.enabled, false);
      expect(e.aecho?.enabled, false);
      expect(e.alimiter?.enabled, false);
      expect(e.surround?.enabled, false);
      // 未提到的槽位（连 subboost 之外的新键都没有）不影响已有槽位
      expect(e.aexciter?.amount, AexciterSettings.amountDefault);
    });

    test('aneq 槽位编码 / 解码往返（params 字符串透传）', () {
      final settings = const AnequalizerSettings()
          .withBands([
            const AnequalizerBand(frequency: 32, bandwidth: 18, gain: 6),
            const AnequalizerBand(frequency: 10000, bandwidth: 4000, gain: -3),
          ])
          .copyWith(enabled: true);

      final json = EffectsCodec.encode(AudioEffects(anequalizer: settings));
      expect(json['aneq'], {'enabled': true, 'params': settings.params});

      final decoded = EffectsCodec.decode(json);
      expect(decoded.anequalizer?.enabled, true);
      expect(decoded.anequalizer?.params, settings.params);
      // params 里的频段信息无损（经扩展解析回来仍是两段）
      expect(decoded.anequalizer!.bands.length, 2);
      expect(decoded.anequalizer!.bands[0].frequency, 32.0);
      expect(decoded.anequalizer!.bands[1].gain, -3.0);
    });
  });

  group('EffectsCodec.encode', () {
    test('编码结果是纯 JSON 可序列化的 Map', () {
      final base = EffectsCodec.decode(const {});
      final edited = base.copyWith(
        bass: (base.bass!).copyWith(enabled: true, gain: 3.5, frequency: 120),
      );

      final json = EffectsCodec.encode(edited);
      // 不抛 + 形状稳定
      expect(jsonEncode(json), isA<String>());
      expect(json['bass'], {'enabled': true, 'gain': 3.5, 'frequency': 120.0});
    });

    test('disabled 但配置过参数的槽位保留参数（关闭不丢配置）', () {
      final base = EffectsCodec.decode(const {});
      final edited = base.copyWith(
        bass: (base.bass!).copyWith(enabled: false, gain: 6),
      );

      final decoded = EffectsCodec.decode(EffectsCodec.encode(edited));
      expect(decoded.bass?.enabled, false);
      expect(decoded.bass?.gain, 6.0);
    });

    test('echo 存 lavfi 原始列表串（不拆成数字，roundtrip 才不会被格式化改动）', () {
      final base = EffectsCodec.decode(const {});
      final edited = base.copyWith(
        aecho: (base.aecho!).copyWith(enabled: true, delays: '250'),
      );

      final json = EffectsCodec.encode(edited);
      expect(json['echo'], {
        'enabled': true,
        'decays': const AechoSettings().decays,
        'delays': '250',
        'in_gain': AechoSettings.in_gainDefault,
        'out_gain': AechoSettings.out_gainDefault,
      });
      // 多段列表原样往返
      final multi = base.copyWith(
        aecho: (base.aecho!).copyWith(delays: '1000|250'),
      );
      final decoded = EffectsCodec.decode(EffectsCodec.encode(multi));
      expect(decoded.aecho?.delays, '1000|250');
    });

    test('surround 只编码声场姿态四项，其余字段停在构造默认值', () {
      final base = EffectsCodec.decode(const {});
      final edited = base.copyWith(
        surround: (base.surround!).copyWith(
          enabled: true,
          angle: 180,
          focus: -0.5,
          overlap: 0.8,
          smooth: 0.3,
        ),
      );

      final json = EffectsCodec.encode(edited);
      expect(
        (json['surround'] as Map).keys,
        containsAll(<String>['enabled', 'angle', 'focus', 'overlap', 'smooth']),
      );
      // 未编码的字段（声道布局 / LFE / 窗函数…）在 decode 侧按构造默认重建
      final decoded = EffectsCodec.decode(json);
      expect(decoded, edited);
      expect(decoded.surround?.chl_out, const SurroundSettings().chl_out);
      expect(decoded.surround?.win_size, const SurroundSettings().win_size);
    });
  });

  group('EffectsCodec roundtrip', () {
    test('默认补齐 → 编辑 → 编码 → 解码 保真', () {
      final base = EffectsCodec.decode(const {});
      final edited = base.copyWith(
        superequalizer: (base.superequalizer!).copyWith(
          enabled: true,
          params: const {'1b': 1.5, '9b': 0.8, '18b': 0.6},
        ),
        acompressor: (base.acompressor!).copyWith(
          enabled: true,
          threshold: 0.1,
          ratio: 4,
          attack: 15,
          release: 300,
          makeup: 2,
          knee: 3,
        ),
        bass: (base.bass!).copyWith(enabled: true, gain: 3.5, frequency: 120),
        treble: (base.treble!).copyWith(
          enabled: true,
          gain: -2,
          frequency: 4000,
        ),
        crossfeed: (base.crossfeed!).copyWith(enabled: true, strength: 0.4),
        crystalizer: (base.crystalizer!).copyWith(enabled: true, i: 3),
        extrastereo: (base.extrastereo!).copyWith(enabled: true, m: 3),
        asubboost: (base.asubboost!).copyWith(enabled: true, boost: 4),
        loudnorm: (base.loudnorm!).copyWith(
          enabled: true,
          i: -16,
          lra: 11,
          tp: -1.5,
          linear: false,
        ),
        anequalizer: (base.anequalizer!).copyWith(
          enabled: true,
          params: (const AnequalizerSettings()).withBands(const [
            AnequalizerBand(frequency: 64, bandwidth: 36, gain: 4),
            AnequalizerBand(frequency: 3000, bandwidth: 1500, gain: -2),
          ]).params,
        ),
        aexciter: (base.aexciter!).copyWith(
          enabled: true,
          amount: 4,
          drive: 6,
          freq: 9000,
        ),
        aecho: (base.aecho!).copyWith(
          enabled: true,
          decays: '0.35',
          delays: '480',
          in_gain: 0.5,
          out_gain: 0.4,
        ),
        alimiter: (base.alimiter!).copyWith(
          enabled: true,
          limit: 0.8,
          attack: 2,
          release: 120,
        ),
        surround: (base.surround!).copyWith(
          enabled: true,
          angle: 45,
          focus: 0.6,
          overlap: 0.9,
          smooth: 0.2,
        ),
      );

      final decoded = EffectsCodec.decode(EffectsCodec.encode(edited));
      expect(decoded, edited);
    });

    test('经 JSON 串一次往返（真实落盘路径）仍然保真', () {
      final base = EffectsCodec.decode(const {});
      final edited = base.copyWith(
        loudnorm: (base.loudnorm!).copyWith(enabled: true, i: -18),
      );

      final raw = jsonEncode(EffectsCodec.encode(edited));
      final restored = EffectsCodec.decode(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      expect(restored, edited);
    });

    test('与当前一致的重复提交不会改值（配合服务层相等短路）', () {
      final e = EffectsCodec.decode(const {});
      final again = EffectsCodec.decode(EffectsCodec.encode(e));
      expect(again, e);
    });
  });
}
