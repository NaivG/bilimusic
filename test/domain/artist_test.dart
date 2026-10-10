import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';

/// 创作者（UP 主）解析与旧数据迁移。
void main() {
  group('Artist 解析', () {
    test('owner 对象：mid / name / face 逐项取出', () {
      final artist = Artist.fromOwner({
        'mid': 1749710516,
        'name': '超级爱下雨天',
        'face': 'https://i2.hdslb.com/bfs/face/x.jpg',
      });

      expect(artist.mid, 1749710516);
      expect(artist.name, '超级爱下雨天');
      expect(artist.face, 'https://i2.hdslb.com/bfs/face/x.jpg');
      expect(artist.hasMid, isTrue);
    });

    test('扁平写法：视频搜索读 author/upic，用户搜索读 uname', () {
      final video = Artist.fromFlat({
        'mid': '153911381',
        'author': '清影音乐库',
        'upic': 'https://i2.hdslb.com/bfs/face/y.jpg',
      });
      expect(video.mid, 153911381);
      expect(video.name, '清影音乐库');

      final user = Artist.fromFlat({
        'mid': 1745584728,
        'uname': '杰威尔音乐',
        'upic': '//i1.hdslb.com/bfs/face/z.jpg',
      }, nameKey: 'uname');
      expect(user.name, '杰威尔音乐');
      // 图片域会回协议相对的 URL，直接塞给图片组件会炸
      expect(user.face, 'https://i1.hdslb.com/bfs/face/z.jpg');
    });

    test('mid 可能是字符串或缺失，统一成 int', () {
      expect(Artist.fromFlat({'mid': '42', 'author': 'A'}).mid, 42);
      expect(Artist.fromFlat({'author': 'A'}).mid, 0);
      expect(Artist.fromFlat({'author': 'A'}).hasMid, isFalse);
    });

    test('只有空白昵称时 displayName 走兜底', () {
      expect(const Artist().displayName, '未知艺术家');
      expect(const Artist(name: '   ').displayName, '未知艺术家');
      expect(const Artist(name: '周杰伦').displayName, '周杰伦');
    });
  });

  group('Music.artist JSON 往返', () {
    test('新形状：artist 是对象，mid / 昵称 / 头像都留得住', () {
      final original = Music(
        id: 'BV1xx411c7mD',
        cid: '1',
        title: '晴天',
        artist: const Artist(mid: 6452, name: '周杰伦', face: 'https://x/f.jpg'),
        album: '叶惠美',
        coverUrl: '',
        audioUrl: '',
      );

      final json = original.toJson();
      expect(json['artist'], isA<Map<String, dynamic>>());
      // 旧的平铺字段不再写出去
      expect(json.containsKey('ownerMid'), isFalse);
      expect(json.containsKey('ownerFace'), isFalse);

      final restored = Music.fromJson(json);
      expect(restored.artist.mid, 6452);
      expect(restored.artist.name, '周杰伦');
      expect(restored.artist.face, 'https://x/f.jpg');
    });

    test('老形状（≤1.10.x）：artist 是昵称字符串，mid / 头像在旁边两个字段里', () {
      final restored = Music.fromJson({
        'id': 'BV1xx411c7mD',
        'cid': '1',
        'title': '晴天',
        'artist': '周杰伦',
        'ownerMid': 6452,
        'ownerFace': 'https://x/f.jpg',
        'album': '叶惠美',
        'coverUrl': '',
        'duration': '269',
        'audioUrl': '',
      });

      expect(restored.artist.mid, 6452);
      expect(restored.artist.name, '周杰伦');
      expect(restored.artist.face, 'https://x/f.jpg');
      expect(restored.artist.displayName, '周杰伦');
      // 头像在旧数据里是可选字段，缺了不该抛
      expect(Music.fromJson({'artist': 'A'}).artist.mid, 0);
      expect(Music.fromJson(const {}).artist.name, '');
    });

    test('老数据里 artist 缺失 / 为 null 时留空，displayName 兜底', () {
      final restored = Music.fromJson({'id': 'BV1', 'artist': null});

      expect(restored.artist.name, '');
      expect(restored.artist.displayName, '未知艺术家');
    });
  });
}
