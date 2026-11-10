import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';
import 'package:bilimusic/features/taste/services/taste_worker.dart';

import 'taste_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TasteProfile profileOf(List<(String, double)> kws) => TasteProfile(
    keywords: [for (final (t, w) in kws) TasteKeyword(term: t, weight: w)],
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );

  TasteWorker buildWorker({
    Duration idleTimeout = const Duration(minutes: 5),
  }) => TasteWorker(
    idleTimeout: idleTimeout,
    segmenter: fakeSegmenter,
    stopFilter: identityStopFilter,
  );

  test('画像构建在 worker isolate 里跑，之后复用同一个 worker', () async {
    final worker = buildWorker();
    addTearDown(worker.dispose);
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    final first = await worker.buildProfile(
      const [
        ProfileSample(text: 'jazz piano', weight: 1.0),
        ProfileSample(text: 'jazz blues', weight: 1.0),
      ],
      forcedTexts: const ['深夜'],
      now: now,
    );

    expect(first.updatedAt, now);
    expect(first.sampleCount, 2);
    expect(first.keywords.map((k) => k.term), containsAll(['jazz', '深夜']));
    // forcedBoost 让歌单名里的词反超常规模样词
    expect(first.keywords.first.term, '深夜');
    expect(worker.isActive, true);
    expect(worker.spawnCount, 1);

    final second = await worker.buildProfile(const [
      ProfileSample(text: 'rock guitar', weight: 1.0),
    ], now: now);
    expect(second.sampleCount, 1);
    // 第二次请求仍复用同一个 worker，没有重新拉起
    expect(worker.spawnCount, 1);
  });

  test('空样本不拉起 worker，直接返回空画像', () async {
    final worker = buildWorker();
    addTearDown(worker.dispose);
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    final profile = await worker.buildProfile(const [], now: now);

    expect(profile.isEmpty, true);
    expect(profile.updatedAt, now);
    expect(worker.isActive, false);
    expect(worker.spawnCount, 0);
  });

  test('空闲超时后 worker 自动退出，下次请求重新拉起', () async {
    final worker = buildWorker(idleTimeout: const Duration(milliseconds: 150));
    addTearDown(worker.dispose);

    await worker.buildProfile(const [
      ProfileSample(text: 'jazz piano', weight: 1.0),
    ]);
    expect(worker.isActive, true);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(worker.isActive, false);

    await worker.buildProfile(const [
      ProfileSample(text: 'jazz piano', weight: 1.0),
    ]);
    expect(worker.isActive, true);
    expect(worker.spawnCount, 2);
  });

  test('并发请求共享同一次拉起', () async {
    final worker = buildWorker();
    addTearDown(worker.dispose);
    final profile = profileOf([('jazz', 1.0)]);
    final items = [music('a', 'jazz piano'), music('b', 'heavy metal')];

    final results = await Future.wait([
      worker.scoreTracks(items, profile),
      worker.scoreTracks(items, profile),
    ]);

    expect(worker.spawnCount, 1);
    expect(results[0], results[1]);
  });

  test('口味分在 worker 里算；空画像 / 空候选不拉起 worker', () async {
    final worker = buildWorker();
    addTearDown(worker.dispose);

    final empty = await worker.scoreTracks([
      music('a', 'jazz'),
    ], TasteProfile(updatedAt: DateTime.now()));
    expect(empty, isEmpty);
    expect(worker.isActive, false);

    final scores = await worker.scoreTracks([
      music('a', 'jazz piano'),
      music('b', 'heavy metal'),
    ], profileOf([('jazz', 1.0), ('piano', 0.5)]));

    expect(scores.length, 2);
    expect(scores[music('a', 'jazz piano').key], greaterThan(0));
    expect(scores[music('b', 'heavy metal').key], 0);
    expect(worker.spawnCount, 1);
  });

  test('dispose 后拒绝新请求', () async {
    final worker = buildWorker();
    final profile = profileOf([('jazz', 1.0)]);

    await worker.scoreTracks([music('a', 'jazz piano')], profile);
    await worker.dispose();
    expect(worker.isActive, false);

    expect(
      worker.scoreTracks([music('a', 'jazz piano')], profile),
      throwsStateError,
    );
  });
}
