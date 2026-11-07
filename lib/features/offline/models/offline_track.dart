/// 离线缓存相关的 UI 侧模型。
///
/// [OfflineTrack] 是纯共享数据模型，按分层约定放在 `lib/domain/`，
/// 这里只 re-export 一次，方便 feature 内统一从 `models/` 引入。
library;

export 'package:bilimusic/domain/offline_track.dart';

/// 下载进度快照。`total <= 0` 表示服务端未给 Content-Length，只能显示已下载量。
class DownloadProgress {
  const DownloadProgress({
    required this.key,
    required this.title,
    required this.received,
    required this.total,
  });

  final String key;
  final String title;
  final int received;
  final int total;

  /// 0.0 ~ 1.0；总长未知时返回 null，UI 应显示不确定进度条。
  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  bool get isIndeterminate => total <= 0;
}

/// 批量离线缓存的结果统计。
class OfflineBatchResult {
  const OfflineBatchResult({
    this.downloaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.cancelled = false,
    this.errors = const [],
  });

  /// 本次新下载（或升级音质重下）成功的曲目数。
  final int downloaded;

  /// 已有足够音质的离线文件、被跳过的曲目数。
  final int skipped;

  /// 下载失败的曲目数。
  final int failed;

  /// 用户是否中途取消了剩余曲目。
  final bool cancelled;

  /// 失败原因摘要（最多保留前几条，避免对话框无限变长）。
  final List<String> errors;

  /// 已处理的曲目数（成功 + 跳过 + 失败）。
  int get processed => downloaded + skipped + failed;
}
