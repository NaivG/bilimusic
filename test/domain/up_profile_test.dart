import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/bili_following.dart';
import 'package:bilimusic/domain/up_profile.dart';

/// 歌手页页头资料的取用规则。
void main() {
  group('UpProfile.fromFollowing', () {
    test('关注列表条目带齐了页头要的字段', () {
      final up = UpProfile.fromFollowing(
        BiliFollowing.fromJson({
          'mid': 14082,
          'uname': '山新',
          'face': 'https://i0.hdslb.com/bfs/face/74c82cae.jpg',
          'sign': '都说了是天依爹地',
          'official_verify': {'type': 0, 'desc': '配音演员、声优'},
        }),
      );

      expect(up.mid, 14082);
      expect(up.name, '山新');
      expect(up.face, 'https://i0.hdslb.com/bfs/face/74c82cae.jpg');
      expect(up.sign, '都说了是天依爹地');
      expect(up.verifyDesc, '配音演员、声优');
      expect(up.isVerified, isTrue);
      expect(up.displayName, '山新');
      expect(up.description, '都说了是天依爹地');
    });
  });

  group('description', () {
    test('没签名时退到认证说明', () {
      const up = UpProfile(mid: 1, name: 'A', verifyDesc: '官方认证账号');

      expect(up.description, '官方认证账号');
    });

    test('签名和认证都没有时兜底', () {
      const up = UpProfile(mid: 1, name: 'A');

      expect(up.description, '这个人很神秘，什么都没写');
      expect(up.isVerified, isFalse);
    });
  });

  group('displayName / isVerified', () {
    test('昵称为空时用 mid 撑住页头', () {
      const up = UpProfile(mid: 420831218, name: '');

      expect(up.displayName, 'mid 420831218');
    });

    test('认证说明为空串不算认证', () {
      const up = UpProfile(mid: 1, name: 'A', verifyDesc: '');

      expect(up.isVerified, isFalse);
    });
  });
}
