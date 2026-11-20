import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';
import 'package:bilimusic/features/taste/services/taste_profile_service.dart';

import 'taste_test_helpers.dart';

/// 记录调用次数并稍微延迟，暴露并发重建是否真的合并。
class _CountingBuilder extends TasteProfileBuilder {
  _CountingBuilder()
    : super(segmenter: fakeSegmenter, stopFilter: identityStopFilter);

  int calls = 0;

  @override
  Future<TasteProfile> build(
    List<ProfileSample> samples, {
    List<String> forcedTexts = const [],
    int topN = 48,
    int maxEdgesPerNode = 5,
    double forcedBoost = 2.5,
    DateTime? now,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return super.build(
      samples,
      forcedTexts: forcedTexts,
      topN: topN,
      maxEdgesPerNode: maxEdgesPerNode,
      forcedBoost: forcedBoost,
      now: now,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('并发 rebuild 只构建一次，两个调用方拿到同一份画像', () async {
    final builder = _CountingBuilder();
    final service = TasteProfileService(
      playlistService: PlaylistService(),
      builder: builder,
    );

    final results = await Future.wait([service.rebuild(), service.rebuild()]);

    expect(builder.calls, 1);
    expect(identical(results[0], results[1]), true);
  });

  test('ensureFresh 命中内存画像时不再重建', () async {
    final builder = _CountingBuilder();
    final service = TasteProfileService(
      playlistService: PlaylistService(),
      builder: builder,
    );

    await service.ensureFresh();
    await service.ensureFresh();

    expect(builder.calls, 1);
  });
}
