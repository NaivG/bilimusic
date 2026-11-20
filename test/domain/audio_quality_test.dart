import 'package:bilimusic/domain/audio_quality.dart';
import 'package:flutter_test/flutter_test.dart';

/// 音质代码 → 档位展示信息。
void main() {
  test('已知音质代码映射到对应档位', () {
    final hires = AudioQualityInfo.of('30251');
    expect(hires.kind, AudioQualityKind.hiResLossless);
    expect(hires.label, 'Hi-Res 无损');
    expect(hires.showsLosslessIcon, isTrue);
    expect(hires.showsLabel, isTrue);

    final dolby = AudioQualityInfo.of('30250');
    expect(dolby.kind, AudioQualityKind.dolbyAtmos);
    expect(dolby.label, '杜比全景声');
    expect(dolby.showsLabel, isFalse);
    expect(dolby.showsLosslessIcon, isFalse);

    expect(AudioQualityInfo.of('30280').label, '192K HQ');
    expect(AudioQualityInfo.of('30232').label, '132K SQ');
    expect(AudioQualityInfo.of('30216').label, '64K AAC-HE');
  });

  test('未知代码按 192K HQ 兜底', () {
    expect(AudioQualityInfo.of(''), same(AudioQualityInfo.fallback));
    expect(AudioQualityInfo.of('99999').label, '192K HQ');
    expect(AudioQualityInfo.of('99999').kind, AudioQualityKind.standard);
  });
}
