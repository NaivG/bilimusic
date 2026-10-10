import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/bili_following.dart';
import 'package:bilimusic/domain/music.dart';

/// 关注列表条目与 UP 主投稿条目的解析。
void main() {
  group('BiliFollowing.fromJson', () {
    test('解析完整的关系列表对象', () {
      final following = BiliFollowing.fromJson({
        'mid': 14082,
        'attribute': 2,
        'mtime': 1584271945,
        'uname': '山新',
        'face': 'https://i0.hdslb.com/bfs/face/74c82cae.jpg',
        'sign': '都说了是天依爹地',
        'official_verify': {'type': 0, 'desc': '配音演员、声优'},
        'vip': {'vipType': 2, 'vipStatus': 1},
      });

      expect(following.mid, 14082);
      expect(following.name, '山新');
      expect(following.face, 'https://i0.hdslb.com/bfs/face/74c82cae.jpg');
      expect(following.sign, '都说了是天依爹地');
      expect(following.verifyDesc, '配音演员、声优');
      expect(following.isVerified, isTrue);
      expect(following.isVip, isTrue);
      expect(following.followTime, 1584271945);
      expect(
        following.followedAt,
        DateTime.fromMillisecondsSinceEpoch(1584271945000),
      );
    });

    test('mid 是字符串也能认；缺字段时退化成空值而不是抛异常', () {
      final following = BiliFollowing.fromJson({'mid': '420831218'});

      expect(following.mid, 420831218);
      expect(following.name, '');
      expect(following.face, '');
      expect(following.verifyDesc, '');
      expect(following.isVerified, isFalse);
      expect(following.isVip, isFalse);
      expect(following.followTime, 0);
      expect(following.followedAt, isNull);
    });

    test('未认证（desc 为空串）不算认证；vipStatus 为 0 不算大会员', () {
      final following = BiliFollowing.fromJson({
        'mid': 1,
        'official_verify': {'type': -1, 'desc': ''},
        'vip': {'vipType': 0, 'vipStatus': 0},
      });

      expect(following.isVerified, isFalse);
      expect(following.isVip, isFalse);
    });
  });

  group('Music.fromSpaceArcJson', () {
    Map<String, dynamic> vlistItem({String length = '04:23'}) => {
      'bvid': 'BV1xx411c7mD',
      'title': 'Starlight【中字】',
      'author': '某UP主',
      'mid': 1234,
      'pic': 'http://i2.hdslb.com/bfs/archive/cover.jpg',
      'length': length,
      'created': 1700000000,
      'play': 12345,
    };

    test('bvid / 标题 / 作者 / 封面缩略后缀都对得上', () {
      final music = Music.fromSpaceArcJson(vlistItem(), album: '某UP主 的投稿');

      expect(music.id, 'BV1xx411c7mD');
      expect(music.title, 'Starlight【中字】');
      expect(music.artist.name, '某UP主');
      expect(music.artist.mid, 1234);
      expect(music.album, '某UP主 的投稿');
      expect(music.coverUrl, endsWith('@672w_378h'));
      expect(music.duration, const Duration(minutes: 4, seconds: 23));
      // 投稿列表不给 cid，取流时由 ApiService 按需回查详情补齐
      expect(music.cid, '');
      expect(music.audioUrl, '');
    });

    test('时长为 H:MM:SS 的直播回放也解析成秒', () {
      final music = Music.fromSpaceArcJson(vlistItem(length: '1:02:03'));

      expect(music.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    });

    test('时长文本异常时留 null，绝不猜出一个时长', () {
      for (final raw in ['', '--:--', '未知', '123', '1:2:3:4', '1:ab']) {
        expect(
          Music.fromSpaceArcJson(vlistItem(length: raw)).duration,
          isNull,
          reason: 'length="$raw" 应当解析为 null',
        );
      }
    });

    test('缺少封面时不拼缩略后缀；缺 bvid 时 id 是空串（由上层过滤）', () {
      final music = Music.fromSpaceArcJson({'title': '无封面'});

      expect(music.coverUrl, '');
      expect(music.id, '');
      expect(music.artist.name, '');
      expect(music.artist.displayName, '未知艺术家');
      expect(music.album, '');
    });
  });
}
