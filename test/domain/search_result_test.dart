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

    test('标题里的 HTML 实体还原成原文（与 BV 直取一致）', () {
      final result = SearchResult.fromJson({
        'type': 'video',
        'bvid': 'BV1NPGd6wE4g',
        'title':
            '【中译版】[MV] ABM - &#x27;[呀啦啦啦]ヤラララ&#x27; '
            '(YARARARA) feat. 重音テト',
        'author': 'ABM',
        'tag': 'VOCALOID',
        'pic': '//i0.hdslb.com/bfs/archive/example.jpg',
      }, SearchResultType.video);

      expect(
        result.title,
        "【中译版】[MV] ABM - '[呀啦啦啦]ヤラララ' (YARARARA) feat. 重音テト",
      );
    });

    test('高亮标签与 HTML 实体一起还原，且只还原一层', () {
      final result = SearchResult.fromJson({
        'type': 'video',
        'bvid': 'BV1xx411c7mD',
        'title':
            '<em class="keyword">A&amp;B</em> - &#x27;x&#x27; '
            '&lt;live&gt; &amp;#x27;',
        'author': 'A&amp;B',
        'tag': 'Rock&nbsp;Live',
      }, SearchResultType.video);

      expect(result.title, "A&B - 'x' <live> &#x27;");
      expect(result.subtitle, 'A&B - Rock Live');
    });

    test('用户结果的昵称与签名同样还原实体', () {
      final result = SearchResult.fromJson({
        'type': 'bili_user',
        'mid': 1,
        'uname': 'A&amp;B',
        'usign': '&quot;hello&quot;',
        'fans': 0,
        'videos': 0,
      }, SearchResultType.author);

      expect(result.title, 'A&B');
      expect(result.subtitle, '"hello"');
    });
  });
}
