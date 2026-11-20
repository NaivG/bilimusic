/// 按字节预算淘汰的 LRU 算法与预算表（纯 Dart）。
library;

/// 缓存中的一条记录：缓存目录内的相对路径、占用字节数与最近使用时间。
///
/// 与 `flutter_cache_manager` 的 `CacheObject` 对应。
class CacheLruEntry {
  const CacheLruEntry({
    required this.relativePath,
    required this.bytes,
    required this.lastUsed,
    this.key,
  });

  /// 缓存目录内的相对路径（`CacheObject.relativePath`），也是淘汰时的唯一标识。
  final String relativePath;

  /// 文件实际占用的字节数。
  final int bytes;

  /// 最近一次被使用的时间（`CacheObject.touched`）。
  final DateTime lastUsed;

  /// 缓存 key（`CacheObject.key`），仅用于日志排查。
  final String? key;

  @override
  String toString() =>
      'CacheLruEntry($relativePath, $bytes B, '
      'lastUsed=${lastUsed.toIso8601String()})';
}

/// 按「最久未使用在前」排序。
///
/// 时间相同的按 [CacheLruEntry.relativePath] 排，保证同样的输入永远得到
/// 同样的淘汰顺序。
List<CacheLruEntry> sortByLeastRecentlyUsed(Iterable<CacheLruEntry> entries) {
  final sorted = entries.toList()
    ..sort((a, b) {
      final byTime = a.lastUsed.compareTo(b.lastUsed);
      return byTime != 0 ? byTime : a.relativePath.compareTo(b.relativePath);
    });
  return sorted;
}

/// 所有条目的字节数之和。
int totalBytesOf(Iterable<CacheLruEntry> entries) {
  var total = 0;
  for (final entry in entries) {
    total += entry.bytes;
  }
  return total;
}

/// 选出需要淘汰的条目：从最久未使用的开始丢，直到总量不超过 [limitBytes]。
///
/// [limitBytes] <= 0 表示不限量，永远返回空列表（调用方用这个语义做「关闭上限」）。
/// 返回列表按淘汰顺序排列，调用方可以逐条删除并在中途放弃（比如文件正被占用）。
List<CacheLruEntry> selectLruEvictions(
  Iterable<CacheLruEntry> entries, {
  required int limitBytes,
}) {
  if (limitBytes <= 0) return const <CacheLruEntry>[];
  final sorted = sortByLeastRecentlyUsed(entries);
  var total = totalBytesOf(sorted);
  final evicted = <CacheLruEntry>[];
  for (final entry in sorted) {
    if (total <= limitBytes) break;
    evicted.add(entry);
    total -= entry.bytes;
  }
  return evicted;
}

/// 音乐 / 图片缓存的大小预算（字节）。
///
/// 默认音乐 512 MiB、图片 256 MiB；具体值来自设置页
/// （`SettingsManager.musicCacheLimitMb` / `imageCacheLimitMb`），由组合根
/// `lib/app/app_providers.dart` 在启动时与设置变化时写入这里。
abstract final class CacheBudget {
  static const int bytesPerMb = 1024 * 1024;

  /// 用户可调范围：64 MiB ~ 8 GiB。
  static const int minLimitBytes = 64 * bytesPerMb;
  static const int maxLimitBytes = 8 * 1024 * bytesPerMb;

  static const int defaultMusicLimitBytes = 512 * bytesPerMb;
  static const int defaultImageLimitBytes = 256 * bytesPerMb;

  /// 音乐临时缓存预算；<= 0 表示不限量。
  static int musicLimitBytes = defaultMusicLimitBytes;

  /// 图片缓存预算；<= 0 表示不限量。
  static int imageLimitBytes = defaultImageLimitBytes;

  /// 把任意字节数夹到 [minLimitBytes, maxLimitBytes]。
  static int clamp(int bytes) {
    if (bytes < minLimitBytes) return minLimitBytes;
    if (bytes > maxLimitBytes) return maxLimitBytes;
    return bytes;
  }

  /// MB 转字节（设置页存的是整数 MB）。
  static int mbToBytes(int mb) => mb * bytesPerMb;

  /// 测试用：恢复出厂默认值。
  static void resetToDefaults() {
    musicLimitBytes = defaultMusicLimitBytes;
    imageLimitBytes = defaultImageLimitBytes;
  }
}
