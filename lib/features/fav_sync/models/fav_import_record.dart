/// 收藏夹导入记录
/// 跟踪每个 Bilibili 收藏夹到本地歌单的导入/同步状态
class FavImportRecord {
  /// Bilibili 收藏夹 media_id
  final int folderMediaId;

  /// 收藏夹标题（便于显示，不用于匹配）
  final String folderTitle;

  /// 对应的本地歌单 ID
  final String playlistId;

  /// 上次成功导入的时间
  final DateTime lastImportedAt;

  /// 成功导入的歌曲数
  final int importedCount;

  /// 失败的歌曲数（失效/跳过）
  final int failedCount;

  /// 同步状态
  final ImportStatus status;

  const FavImportRecord({
    required this.folderMediaId,
    required this.folderTitle,
    required this.playlistId,
    required this.lastImportedAt,
    this.importedCount = 0,
    this.failedCount = 0,
    this.status = ImportStatus.pending,
  });

  FavImportRecord copyWith({
    int? folderMediaId,
    String? folderTitle,
    String? playlistId,
    DateTime? lastImportedAt,
    int? importedCount,
    int? failedCount,
    ImportStatus? status,
  }) {
    return FavImportRecord(
      folderMediaId: folderMediaId ?? this.folderMediaId,
      folderTitle: folderTitle ?? this.folderTitle,
      playlistId: playlistId ?? this.playlistId,
      lastImportedAt: lastImportedAt ?? this.lastImportedAt,
      importedCount: importedCount ?? this.importedCount,
      failedCount: failedCount ?? this.failedCount,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'folderMediaId': folderMediaId,
    'folderTitle': folderTitle,
    'playlistId': playlistId,
    'lastImportedAt': lastImportedAt.millisecondsSinceEpoch,
    'importedCount': importedCount,
    'failedCount': failedCount,
    'status': status.name,
  };

  factory FavImportRecord.fromJson(Map<String, dynamic> json) {
    return FavImportRecord(
      folderMediaId: json['folderMediaId'] ?? 0,
      folderTitle: json['folderTitle'] ?? '',
      playlistId: json['playlistId'] ?? '',
      lastImportedAt: DateTime.fromMillisecondsSinceEpoch(
        json['lastImportedAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      importedCount: json['importedCount'] ?? 0,
      failedCount: json['failedCount'] ?? 0,
      status: ImportStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ImportStatus.pending,
      ),
    );
  }
}

/// 导入同步状态
enum ImportStatus {
  /// 未导入过
  pending,

  /// 已同步（与 Bilibili 收藏夹一致）
  synced,

  /// 有更新（收藏夹内容可能已变化）
  outdated,
}
