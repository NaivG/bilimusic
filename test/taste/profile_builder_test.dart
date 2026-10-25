import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';

import 'taste_test_helpers.dart';

void main() {
  group('TasteProfileBuilder', () {
    test('加权词频：跨样本词排最前，归一化后最高权重为 1', () async {
      final profile = await fakeBuilder().build([
        const ProfileSample(text: 'jazz piano jazz', weight: 1.0),
        const ProfileSample(text: 'jazz blues', weight: 1.0),
      ]);

      expect(profile.keywords.first.term, 'jazz');
      expect(profile.keywords.first.weight, 1.0);
      expect(profile.sampleCount, 2);
    });

    test('文档频率过滤：只在一个样本出现的词被丢弃', () async {
      final profile = await fakeBuilder().build([
        const ProfileSample(text: 'jazz piano', weight: 1.0),
        const ProfileSample(text: 'jazz blues', weight: 1.0),
      ]);

      final terms = profile.keywords.map((k) => k.term).toSet();
      expect(terms, contains('jazz'));
      expect(terms, isNot(contains('piano'))); // df = 1
      expect(terms, isNot(contains('blues'))); // df = 1
    });

    test('forcedTexts：单源词绕过 df 过滤并拿到加成，能反超常规模样词', () async {
      final profile = await fakeBuilder().build(
        [
          const ProfileSample(text: 'jazz piano', weight: 1.0),
          const ProfileSample(text: 'jazz blues', weight: 1.0),
        ],
        forcedTexts: const ['学习'],
      );

      final byTerm = {for (final k in profile.keywords) k.term: k.weight};
      expect(byTerm.containsKey('学习'), true);
      // jazz 总分 2.0（两样本各 1.0×(1+ln1)），forcedBoost=2.5 反超
      expect(byTerm['学习']! > byTerm['jazz']!, true);
    });

    test('样本权重生效：同样出现两次，重样本推高词条分', () async {
      final profile = await fakeBuilder().build([
        const ProfileSample(text: 'alpha beta', weight: 1.0),
        const ProfileSample(text: 'alpha', weight: 3.0),
        const ProfileSample(text: 'beta', weight: 1.0),
      ]);

      // alpha = 1.0 + 3.0 = 4.0，beta = 1.0 + 1.0 = 2.0，df 均为 2
      final byTerm = {for (final k in profile.keywords) k.term: k.weight};
      expect(byTerm['alpha']! > byTerm['beta']!, true);
    });

    test('topN 截断', () async {
      final profile = await fakeBuilder().build([
        const ProfileSample(text: 'aa bb cc dd', weight: 1.0),
        const ProfileSample(text: 'aa bb cc dd', weight: 1.0),
      ], topN: 2);

      expect(profile.keywords.length, 2);
    });

    test('共现边：同歌出现的词形成边，Jaccard 归一化', () async {
      final profile = await fakeBuilder().build([
        const ProfileSample(text: 'jazz piano', weight: 1.0),
        const ProfileSample(text: 'jazz piano', weight: 1.0),
        const ProfileSample(text: 'jazz blues', weight: 1.0),
        const ProfileSample(text: 'jazz blues', weight: 1.0),
      ]);

      final jazzPiano = _edgeOf(profile, 'jazz', 'piano');
      final jazzBlues = _edgeOf(profile, 'jazz', 'blues');
      expect(jazzPiano, isNotNull);
      expect(jazzBlues, isNotNull);
      expect(jazzPiano!.support, 2);
      expect(jazzPiano.weight, closeTo(0.5, 1e-9));
      expect(jazzBlues!.support, 2);
      expect(jazzBlues.weight, closeTo(0.5, 1e-9));
      expect(_edgeOf(profile, 'piano', 'blues'), isNull);
    });

    test('共现支持度不足 2 的边被丢弃', () async {
      final profile = await fakeBuilder().build([
        const ProfileSample(text: 'jazz piano', weight: 1.0),
        const ProfileSample(text: 'jazz piano', weight: 1.0),
        const ProfileSample(text: 'jazz blues', weight: 1.0),
        const ProfileSample(text: 'jazz blues', weight: 1.0),
        const ProfileSample(text: 'piano blues', weight: 1.0),
      ]);

      expect(_edgeOf(profile, 'piano', 'blues'), isNull);
    });

    test('forcedTexts 不再污染 df；歌单独有词是孤立节点', () async {
      final profile = await fakeBuilder().build(
        [
          const ProfileSample(text: 'jazz piano', weight: 1.0),
          const ProfileSample(text: 'jazz piano', weight: 1.0),
          const ProfileSample(text: 'jazz blues', weight: 1.0),
          const ProfileSample(text: 'jazz blues', weight: 1.0),
        ],
        forcedTexts: const ['jazz', '深夜'],
      );

      final jazz = profile.keywords.firstWhere((k) => k.term == 'jazz');
      final night = profile.keywords.firstWhere((k) => k.term == '深夜');
      expect(jazz.df, 4); // 真实文档频率，不是 1 << 20
      expect(night.df, 0);
      expect(_edgeOf(profile, 'jazz', 'piano'), isNotNull);
      expect(_edgeOf(profile, '深夜', 'jazz'), isNull);
    });

    test('每节点共现边数受 maxEdgesPerNode 限制', () async {
      final profile = await fakeBuilder().build([
        for (var i = 0; i < 2; i++) ...[
          const ProfileSample(text: 'center aa', weight: 1.0),
          const ProfileSample(text: 'center bb', weight: 1.0),
          const ProfileSample(text: 'center cc', weight: 1.0),
          const ProfileSample(text: 'center dd', weight: 1.0),
        ],
      ], maxEdgesPerNode: 2);

      expect(profile.edges.length, 2);
      expect(
        profile.edges.every((e) => e.a == 'center' || e.b == 'center'),
        true,
      );
    });

    test('空输入 → 空画像', () async {
      final profile = await fakeBuilder().build(const []);
      expect(profile.isEmpty, true);
    });

    test('确定性：同输入两次构建结果一致', () async {
      const samples = [
        ProfileSample(text: 'jazz piano', weight: 1.0),
        ProfileSample(text: 'jazz blues', weight: 2.0),
        ProfileSample(text: 'rock guitar', weight: 1.5),
      ];
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final a = await fakeBuilder().build(samples, now: now);
      final b = await fakeBuilder().build(samples, now: now);
      expect(a.toJson(), b.toJson());
    });
  });
}

TasteEdge? _edgeOf(TasteProfile profile, String a, String b) {
  for (final edge in profile.edges) {
    if ((edge.a == a && edge.b == b) || (edge.a == b && edge.b == a)) {
      return edge;
    }
  }
  return null;
}
