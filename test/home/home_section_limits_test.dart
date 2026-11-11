import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/home/logic/home_section_limits.dart';

/// 首页分区卡片上限：张数与行数双约束。
void main() {
  group('网格上限', () {
    test('取张数与「行数 × 列数」中更小的一支', () {
      expect(HomeSectionLimits.grid(maxCards: 8, maxRows: 2, columns: 4), 8);
      expect(HomeSectionLimits.grid(maxCards: 8, maxRows: 2, columns: 3), 6);
      expect(HomeSectionLimits.grid(maxCards: 8, maxRows: 1, columns: 4), 4);
    });

    test('列数很多时仍受张数封顶', () {
      expect(HomeSectionLimits.grid(maxCards: 8, maxRows: 1, columns: 12), 8);
    });

    test('列数非正时不出卡片', () {
      expect(HomeSectionLimits.grid(maxCards: 8, maxRows: 2, columns: 0), 0);
      expect(HomeSectionLimits.grid(maxCards: 8, maxRows: 2, columns: -1), 0);
    });
  });

  group('为你推荐', () {
    test('最多 8 张', () {
      expect(HomeSectionLimits.personalMaxCards, 8);
    });

    test('横屏 4 列 2 行 = 8 张，3 列只放得下 6 张', () {
      expect(HomeSectionLimits.personalGrid(4), 8);
      expect(HomeSectionLimits.personalGrid(3), 6);
    });
  });

  group('歌单', () {
    test('最多 8 张', () {
      expect(HomeSectionLimits.playlistMaxCards, 8);
    });

    test('横屏只占 1 行：4 列 4 张、3 列 3 张', () {
      expect(HomeSectionLimits.playlistGrid(4), 4);
      expect(HomeSectionLimits.playlistGrid(3), 3);
    });

    test('列数多于 8 时按 8 张封顶', () {
      expect(HomeSectionLimits.playlistGrid(10), 8);
    });
  });
}
