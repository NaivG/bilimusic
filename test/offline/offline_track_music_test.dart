import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/offline_track.dart';
import 'package:bilimusic/features/offline/logic/offline_track_music.dart';

void main() {
  OfflineTrack track() => OfflineTrack(
    bvid: 'BV1xx411c7mD',
    cid: '12345',
    title: '晴天',
    artist: '周杰伦',
    coverUrl: 'https://i0.hdslb.com/bfs/archive/cover.jpg',
    filePath: r'C:\Music\J\周杰伦 - 晴天 [12345].m4a',
    qualityId: '30280',
    fileSize: 1024,
    downloadedAt: DateTime(2026, 11, 2),
  );

  test('离线记录还原成播放队列条目时保留 bvid / cid / 标题 / 作者 / 封面', () {
    final music = musicFromOfflineTrack(track());

    expect(music.id, 'BV1xx411c7mD');
    expect(music.cid, '12345');
    expect(music.title, '晴天');
    expect(music.artist.name, '周杰伦');
    expect(music.coverUrl, 'https://i0.hdslb.com/bfs/archive/cover.jpg');
    // 同一首曲目按 (bvid, cid) 判等，必须与离线记录对得上。
    expect(music.key, 'BV1xx411c7mD_12345');
  });

  test('音质标签只翻译已知档位', () {
    expect(offlineQualityLabel('30216'), '64K');
    expect(offlineQualityLabel('30280'), '192K');
    expect(offlineQualityLabel('30251'), 'Hi-Res');
    expect(offlineQualityLabel('99999'), isNull);
    expect(offlineQualityLabel(''), isNull);
  });
}
