import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/storage/size_lru_cache.dart';

/// 大小 LRU 算法与预算表的纯逻辑测试。
///
/// 这里只覆盖 `size_lru_cache.dart`（纯 Dart，不碰文件系统 / Flutter）；
/// 真正落盘删除的 IO 行为在 `test/storage/size_bounded_cache_manager_test.dart`。
void main() {
  final baseTime = DateTime.utc(2026, 1, 1, 12);

  DateTime minutesLater(int minutes) =>
      baseTime.add(Duration(minutes: minutes));

  /// 构造一条缓存记录；`usedAt` 是相对 [baseTime] 的分钟偏移。
  CacheLruEntry entry(String relativePath, int bytes, {required int usedAt}) =>
      CacheLruEntry(
        relativePath: relativePath,
        bytes: bytes,
        lastUsed: minutesLater(usedAt),
        key: relativePath,
      );

  group('sortByLeastRecentlyUsed', () {
    test('按最近使用时间升序，最久未用的排在最前', () {
      final entries = [
        entry('newest.file', 1, usedAt: 30),
        entry('oldest.file', 1, usedAt: 0),
        entry('middle.file', 1, usedAt: 10),
      ];

      final sorted = sortByLeastRecentlyUsed(entries);

      expect(sorted.map((entry) => entry.relativePath).toList(), [
        'oldest.file',
        'middle.file',
        'newest.file',
      ]);
    });

    test('时间相同时按 relativePath 排序，顺序稳定且与输入顺序无关', () {
      final entries = [
        entry('b.file', 1, usedAt: 5),
        entry('c.file', 1, usedAt: 5),
        entry('a.file', 1, usedAt: 5),
      ];

      expect(
        sortByLeastRecentlyUsed(entries)
            .map((entry) => entry.relativePath)
            .toList(),
        ['a.file', 'b.file', 'c.file'],
      );
      expect(
        sortByLeastRecentlyUsed(entries.reversed)
            .map((entry) => entry.relativePath)
            .toList(),
        ['a.file', 'b.file', 'c.file'],
      );
    });

    test('不修改传入的列表', () {
      final entries = [
        entry('b.file', 1, usedAt: 1),
        entry('a.file', 1, usedAt: 0),
      ];
      final snapshot = List<CacheLruEntry>.of(entries);

      sortByLeastRecentlyUsed(entries);

      expect(entries, snapshot);
    });
  });

  group('totalBytesOf', () {
    test('空集合的总量是 0', () {
      expect(totalBytesOf(const <CacheLruEntry>[]), 0);
    });

    test('把所有条目的字节数相加', () {
      final entries = [
        entry('a.file', 3, usedAt: 0),
        entry('b.file', 4, usedAt: 1),
        entry('c.file', 5, usedAt: 2),
      ];

      expect(totalBytesOf(entries), 12);
    });
  });

  group('selectLruEvictions', () {
    test('总量小于预算时不淘汰任何条目', () {
      final entries = [
        entry('a.file', 300, usedAt: 0),
        entry('b.file', 300, usedAt: 1),
        entry('c.file', 300, usedAt: 2),
      ];

      expect(selectLruEvictions(entries, limitBytes: 1000), isEmpty);
    });

    test('总量刚好等于预算时不淘汰任何条目', () {
      final entries = [
        entry('a.file', 400, usedAt: 0),
        entry('b.file', 600, usedAt: 1),
      ];

      expect(selectLruEvictions(entries, limitBytes: 1000), isEmpty);
    });

    test('超预算时从最久未用开始删，删到总量不超过预算为止', () {
      final entries = [
        entry('a_oldest.file', 400, usedAt: 0),
        entry('b_middle.file', 300, usedAt: 10),
        entry('c_newest.file', 300, usedAt: 20),
      ];

      // 1000 - 400 = 600 ≤ 700，只淘汰最久未用的 a。
      final evicted = selectLruEvictions(entries, limitBytes: 700);

      expect(evicted.map((entry) => entry.relativePath).toList(), [
        'a_oldest.file',
      ]);
    });

    test('删掉最旧一条仍超预算时继续按 LRU 顺序淘汰，保留最新条目', () {
      final entries = [
        entry('tiny_oldest.file', 100, usedAt: 0),
        entry('big_middle.file', 600, usedAt: 10),
        entry('big_newest.file', 600, usedAt: 20),
      ];

      // 1300 - 100 = 1200 仍超预算，再删 big_middle → 600 ≤ 700。
      final evicted = selectLruEvictions(entries, limitBytes: 700);

      expect(evicted.map((entry) => entry.relativePath).toList(), [
        'tiny_oldest.file',
        'big_middle.file',
      ]);
    });

    test('limitBytes <= 0 表示不限量，永远返回空列表', () {
      final entries = [
        entry('a.file', 300, usedAt: 0),
        entry('b.file', 300, usedAt: 1),
      ];

      expect(selectLruEvictions(entries, limitBytes: 0), isEmpty);
      expect(selectLruEvictions(entries, limitBytes: -1), isEmpty);
    });

    test('单条记录本身就超预算时也会被淘汰', () {
      final entries = [entry('huge.file', 900, usedAt: 0)];

      final evicted = selectLruEvictions(entries, limitBytes: 100);

      expect(evicted.map((entry) => entry.relativePath).toList(), [
        'huge.file',
      ]);
    });

    test('输入顺序不影响到淘汰顺序', () {
      final entries = [
        entry('a.file', 300, usedAt: 0),
        entry('b.file', 300, usedAt: 1),
        entry('c.file', 300, usedAt: 2),
      ];

      final fromOriginal = selectLruEvictions(entries, limitBytes: 400);
      final fromReversed = selectLruEvictions(
        entries.reversed,
        limitBytes: 400,
      );

      expect(fromOriginal.map((entry) => entry.relativePath).toList(), [
        'a.file',
        'b.file',
      ]);
      expect(fromReversed.map((entry) => entry.relativePath).toList(), [
        'a.file',
        'b.file',
      ]);
    });
  });

  group('CacheBudget', () {
    // 静态字段是全局状态：每个用例前后都恢复默认值，避免互相污染。
    setUp(CacheBudget.resetToDefaults);
    tearDown(CacheBudget.resetToDefaults);

    test('默认预算是音乐 512 MiB、图片 256 MiB', () {
      expect(CacheBudget.bytesPerMb, 1024 * 1024);
      expect(CacheBudget.defaultMusicLimitBytes, 512 * CacheBudget.bytesPerMb);
      expect(CacheBudget.defaultImageLimitBytes, 256 * CacheBudget.bytesPerMb);
      expect(CacheBudget.musicLimitBytes, CacheBudget.defaultMusicLimitBytes);
      expect(CacheBudget.imageLimitBytes, CacheBudget.defaultImageLimitBytes);
    });

    test('可调范围是 64 MiB ~ 8 GiB', () {
      expect(CacheBudget.minLimitBytes, 64 * CacheBudget.bytesPerMb);
      expect(CacheBudget.maxLimitBytes, 8 * 1024 * CacheBudget.bytesPerMb);
    });

    test('clamp 把预算夹回可调范围内', () {
      expect(CacheBudget.clamp(0), CacheBudget.minLimitBytes);
      expect(
        CacheBudget.clamp(CacheBudget.minLimitBytes - 1),
        CacheBudget.minLimitBytes,
      );
      expect(
        CacheBudget.clamp(CacheBudget.minLimitBytes),
        CacheBudget.minLimitBytes,
      );
      expect(
        CacheBudget.clamp(300 * CacheBudget.bytesPerMb),
        300 * CacheBudget.bytesPerMb,
      );
      expect(
        CacheBudget.clamp(CacheBudget.maxLimitBytes),
        CacheBudget.maxLimitBytes,
      );
      expect(
        CacheBudget.clamp(CacheBudget.maxLimitBytes + 1),
        CacheBudget.maxLimitBytes,
      );
    });

    test('mbToBytes 按 MiB 换算', () {
      expect(CacheBudget.mbToBytes(0), 0);
      expect(CacheBudget.mbToBytes(1), 1024 * 1024);
      expect(CacheBudget.mbToBytes(512), CacheBudget.defaultMusicLimitBytes);
      expect(CacheBudget.mbToBytes(256), CacheBudget.defaultImageLimitBytes);
    });

    test('resetToDefaults 把运行时修改恢复成默认值', () {
      CacheBudget.musicLimitBytes = CacheBudget.mbToBytes(1024);
      CacheBudget.imageLimitBytes = CacheBudget.mbToBytes(64);

      CacheBudget.resetToDefaults();

      expect(CacheBudget.musicLimitBytes, CacheBudget.defaultMusicLimitBytes);
      expect(CacheBudget.imageLimitBytes, CacheBudget.defaultImageLimitBytes);
    });
  });
}
