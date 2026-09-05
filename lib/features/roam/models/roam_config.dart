import 'package:bilimusic/models/roam_style.dart';
import 'package:bilimusic/services/player_coordinator.dart';

/// 漫游会话的紧凑可序列化配置（v2，plain text）。
///
/// v2 起不再携带源歌单 ID：种子经用户挑选与推荐洗牌后，原始歌单已无参考意义。
///
/// 线上格式（分隔符 `-`）：
/// ```
/// {version}-{kind}-{style}-{threshold}-{seedCount}-{bvid1}-{bvid2}-...
/// ```
/// - `version`: 当前为 `2`
/// - `kind`: 固定为 `r`
/// - `style`: `s` / `b` / `e`
/// - `threshold`: 1 位整数，范围 `1`-`5`
/// - `seedCount`: 1 位整数，范围 `1`-`9`
/// - `bvidN`: 已剥离 `BV1` 前缀
///
/// 不包含 `cid`——种子经 [RoamingService.fetchBatch] 构造时 cid 总为空，
/// 且 [RoamingService.resolveSeed] 在 cid 缺失/不匹配时回退到首分P。
///
/// 示例：
/// ```
/// 2-r-b-2-1-xAVezxEkw
/// 2-r-b-2-3-xAVezxEkw-QwU7BREo6-GzV36pE5h
/// ```
class RoamConfig {
  static const int currentVersion = 2;
  static const String kindTag = 'r';
  static const int maxSeeds = 9;

  final int version;
  final RoamStyle style;
  final int refillThreshold;
  final List<String> seeds;

  const RoamConfig({
    required this.version,
    required this.style,
    required this.refillThreshold,
    required this.seeds,
  });

  /// 序列化为单行紧凑字符串。
  String toPlainText() {
    final buf = StringBuffer()
      ..write(version)
      ..write('-')
      ..write(kindTag)
      ..write('-')
      ..write(_styleCode(style))
      ..write('-')
      ..write(refillThreshold)
      ..write('-')
      ..write(seeds.length);
    for (final bvid in seeds) {
      buf
        ..write('-')
        ..write(_stripBv1(bvid));
    }
    return buf.toString();
  }

  /// 反序列化。任一字段不合法或解析失败时返回 `null`。
  static RoamConfig? fromPlainText(String input) {
    if (input.isEmpty) return null;
    final parts = input.split('-');
    // header 5 + 至少 1 颗种子 → 总长 ≥ 6
    if (parts.length < 6) return null;

    final version = int.tryParse(parts[0]);
    if (version == null || version != currentVersion) return null;
    if (parts[1] != kindTag) return null;

    final style = _styleFromCode(parts[2]);
    if (style == null) return null;

    final threshold = int.tryParse(parts[3]);
    if (threshold == null || threshold < 1 || threshold > 5) return null;

    final seedCount = int.tryParse(parts[4]);
    if (seedCount == null || seedCount < 1 || seedCount > maxSeeds) {
      return null;
    }

    // header 5 + seedCount 颗种子 → 总长恰好等于 5 + seedCount
    if (parts.length != 5 + seedCount) return null;

    final seeds = <String>[];
    for (var i = 0; i < seedCount; i++) {
      final shortBvid = parts[5 + i];
      if (shortBvid.isEmpty) return null;
      seeds.add(_restoreBv1(shortBvid));
    }

    return RoamConfig(
      version: version,
      style: style,
      refillThreshold: threshold,
      seeds: seeds,
    );
  }

  /// 从当前协调器状态构造。`!c.isRoaming` 时返回 `null`。
  static RoamConfig? fromCoordinator(PlayerCoordinator c) {
    if (!c.isRoaming) return null;
    final style = c.roamStyle;
    if (style == null) return null;

    final seeds = <String>[
      for (final m in c.roamSeeds)
        if (m.id.isNotEmpty) m.id,
    ];
    if (seeds.isEmpty || seeds.length > maxSeeds) return null;

    return RoamConfig(
      version: currentVersion,
      style: style,
      refillThreshold: c.roamRefillThreshold ?? 2,
      seeds: seeds,
    );
  }

  static String _stripBv1(String bvid) =>
      bvid.startsWith('BV1') ? bvid.substring(3) : bvid;

  static String _restoreBv1(String s) => s.startsWith('BV1') ? s : 'BV1$s';

  static String _styleCode(RoamStyle s) => switch (s) {
    RoamStyle.similar => 's',
    RoamStyle.balanced => 'b',
    RoamStyle.explore => 'e',
  };

  static RoamStyle? _styleFromCode(String c) => switch (c) {
    's' => RoamStyle.similar,
    'b' => RoamStyle.balanced,
    'e' => RoamStyle.explore,
    _ => null,
  };
}
