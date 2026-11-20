import 'dart:math' as math;

/// 首页分区卡片上限：张数与行数双约束。
class HomeSectionLimits {
  const HomeSectionLimits._();

  /// 「为你推荐」的卡片上限。
  static const int personalMaxCards = 8;

  /// 「为你推荐」横屏网格的行数上限。
  static const int personalMaxRows = 2;

  /// 「歌单」的卡片上限。
  static const int playlistMaxCards = 8;

  /// 「歌单」横屏网格的行数上限。
  static const int playlistMaxRows = 1;

  /// 横屏网格上限：张数与「行数 × 列数」取小。
  static int grid({
    required int maxCards,
    required int maxRows,
    required int columns,
  }) {
    if (columns <= 0) return 0;
    return math.min(maxCards, columns * maxRows);
  }

  /// 「为你推荐」在 [columns] 列网格里的上限。
  static int personalGrid(int columns) => grid(
    maxCards: personalMaxCards,
    maxRows: personalMaxRows,
    columns: columns,
  );

  /// 「歌单」在 [columns] 列网格里的上限。
  static int playlistGrid(int columns) => grid(
    maxCards: playlistMaxCards,
    maxRows: playlistMaxRows,
    columns: columns,
  );
}
