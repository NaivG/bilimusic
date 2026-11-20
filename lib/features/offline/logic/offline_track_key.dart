import 'package:bilimusic/domain/music.dart';

/// 离线记录归属的 cid。
///
/// 与落库（`OfflineCacheService.persistFromFile`）用的是**同一套规则**，
/// 优先 `music.cid`，缺失时退化到首分 P；两者都没有时返回空串。
String offlineEffectiveCid(Music music) {
  if (music.cid.isNotEmpty) return music.cid;
  if (music.pages.isNotEmpty) return music.pages.first.cid;
  return '';
}
