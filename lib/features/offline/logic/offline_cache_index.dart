import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/offline_track.dart';
import 'package:bilimusic/features/offline/logic/offline_track_key.dart';

/// 已缓存曲目索引：把 `downloads` 表快照换算成 O(1) 的「是否已缓存」判断。
///
/// 精确命中用 `bvid_cid`，其中 cid 走 [offlineEffectiveCid]（与落库同一套
/// 规则：cid 缺失时取首分 P）。cid 完全未知（推荐流/搜索结果的稿件卡片）时
/// 按 bvid 兜底：只要这个稿件有离线记录就算已缓存。
///
/// bvid 兜底对多 P 视频可能命中任一分 P——「是否已缓存」只是多选态的提示，
/// 真正的跳过 / 重下判断由批量下载链路再做一次，所以这里接受这种近似。
class OfflineCacheIndex {
  OfflineCacheIndex(Iterable<OfflineTrack> tracks) {
    for (final track in tracks) {
      _keys.add(track.key);
      _bvids.add(track.bvid);
    }
  }

  /// 精确命中的 `bvid_cid` 集合。
  final Set<String> _keys = <String>{};

  /// 有任意离线记录的 bvid（cid 未知时兜底用）。
  final Set<String> _bvids = <String>{};

  bool get isEmpty => _keys.isEmpty;

  /// 该曲目是否已有离线缓存。
  bool contains(Music music) {
    final cid = offlineEffectiveCid(music);
    if (cid.isNotEmpty) return _keys.contains('${music.id}_$cid');
    return _bvids.contains(music.id);
  }
}
