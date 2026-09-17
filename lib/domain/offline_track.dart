/// 离线缓存（已下载到本地磁盘的曲目）的数据模型。
///
/// 与 `musicCacheManager`（flutter_cache_manager 的临时缓存，stalePeriod 7 天 /
/// 最多 50 个对象，随时可能被回收）不同：离线缓存是**用户可见、可迁移**的长期
/// 存储，落在用户指定目录（桌面端）或应用私有外部目录（Android）。
library;

/// 一条离线记录，对应 `downloads` 表的一行。
class OfflineTrack {
  const OfflineTrack({
    required this.bvid,
    required this.cid,
    required this.title,
    required this.artist,
    required this.filePath,
    required this.qualityId,
    required this.fileSize,
    required this.downloadedAt,
  });

  /// 稿件 bvid
  final String bvid;

  /// 分 P cid（多 P 视频按分 P 各存一份；无分 P 时为空串）
  final String cid;

  final String title;
  final String artist;

  /// 落盘时的绝对路径（查表直接用这个，避免每次拼目录）
  final String filePath;

  /// 落盘时实际命中的音质代码（可能是回退档位，用于判断"要不要为更高音质重下"）
  final String qualityId;

  /// 文件字节数（用于占用统计；文件被外部改动时不重算）
  final int fileSize;

  final DateTime downloadedAt;

  /// 唯一键，与 [Music.key] 语义一致：`bvid_cid`
  String get key => '${bvid}_$cid';

  factory OfflineTrack.fromRow(Map<String, Object?> row) {
    return OfflineTrack(
      bvid: row['bvid']?.toString() ?? '',
      cid: row['cid']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      artist: row['artist']?.toString() ?? '',
      filePath: row['file_path']?.toString() ?? '',
      qualityId: row['quality_id']?.toString() ?? '',
      fileSize: (row['file_size'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['downloaded_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}
