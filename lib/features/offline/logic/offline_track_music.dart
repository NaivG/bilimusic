import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/offline_track.dart';

/// 把一条离线记录还原成可进入播放队列的 [Music]。
Music musicFromOfflineTrack(OfflineTrack track) {
  return Music(
    id: track.bvid,
    cid: track.cid,
    title: track.title,
    artist: Artist(name: track.artist),
    album: '',
    coverUrl: track.coverUrl,
    audioUrl: '',
  );
}

const Map<String, String> _qualityLabels = {
  '30216': '64K',
  '30232': '132K',
  '30280': '192K',
  '30250': '杜比',
  '30251': 'Hi-Res',
};

/// 离线记录音质代码的短标签；未知档位返回 null（UI 不显示角标）。
String? offlineQualityLabel(String qualityId) => _qualityLabels[qualityId];
