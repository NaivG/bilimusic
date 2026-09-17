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
