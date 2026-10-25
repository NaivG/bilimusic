import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/search_result.dart';

void main() {
  group('SearchResult.fromJson', () {
    test('bili_user 解析为可进 UP 主页的 author 结果', () {
      final result = SearchResult.fromJson({
        'type': 'bili_user',
        'mid': 36081646,
        'uname': '洛天依',
        'usign': '世界第一位VOCALOID中文虚拟歌姬',
        'fans': 1982688,
        'videos': 45,
        'upic': '//i2.hdslb.com/bfs/face/example.jpg',
      }, SearchResultType.author);

      expect(result.id, '36081646');
      expect(result.type, SearchResultType.author);
      expect(result.title, '洛天依');
      expect(result.coverUrl, 'https://i2.hdslb.com/bfs/face/example.jpg');
      expect(result.subtitle, '198.3万粉丝 · 45投稿');
      expect(result.artist.mid, 36081646);
      expect(result.artist.name, '洛天依');
      expect(result.artist.hasMid, isTrue);
      expect(result.artist.face, 'https://i2.hdslb.com/bfs/face/example.jpg');
    });

    test('视频结果保留作者昵称作为 artist', () {
      final result = SearchResult.fromJson({
        'type': 'video',
        'bvid': 'BV1Hk4y1B7Cx',
        'title': '【<em class="keyword">洛天依</em>】生日会',
        'author': '洛天依',
        'mid': 36081646,
        'upic': '//i2.hdslb.com/bfs/face/example.jpg',
        'tag': 'VOCALOID',
        'pic': '//i0.hdslb.com/bfs/archive/example.jpg',
      }, SearchResultType.video);

      expect(result.id, 'BV1Hk4y1B7Cx');
      expect(result.title, '【洛天依】生日会');
      expect(result.artist.mid, 36081646);
      expect(result.artist.name, '洛天依');
      expect(result.subtitle, '洛天依 - VOCALOID');
    });
  });
}
