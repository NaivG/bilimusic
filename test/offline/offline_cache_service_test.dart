import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/offline_track.dart';
import 'package:bilimusic/features/offline/services/offline_cache_service.dart';

/// 离线缓存命名与音质判定的纯逻辑单测。
///
/// 这两块是离线缓存里最容易"静默出错"的部分：文件名里的 Windows 非法字符、
/// 超长截断、以及"已有文件音质够不够用"的档位比较。落盘/网络部分需要
/// Flutter binding 与真实 DB，不在这里覆盖（靠 App 内实测）。
void main() {
  Music music({String title = '标题', String artist = '歌手', String id = 'BV1x'}) {
    return Music(
      id: id,
      cid: '100',
      title: title,
      artist: artist,
      album: '',
      coverUrl: '',
      audioUrl: '',
    );
  }

  group('sanitizeFileName', () {
    test('Windows 非法字符全部替换为下划线', () {
      final out = OfflineCacheService.sanitizeFileName('a/b\\c:d*e?f"g<h>i|j');
      expect(out.contains(RegExp(r'[\\/:*?"<>|]')), isFalse);
      expect(out, 'a_b_c_d_e_f_g_h_i_j');
    });

    test('折叠空白并去掉结尾的点与空格（Windows 不允许结尾点/空格）', () {
      expect(OfflineCacheService.sanitizeFileName('  A   B ...  '), 'A B');
    });

    test('超长名称按字符截断到 80（中文最坏 240 字节，仍在 255 上限内）', () {
      final out = OfflineCacheService.sanitizeFileName('中' * 200);
      expect(out.length, 80);
      expect(out.codeUnits.every((c) => c > 0x2000), isTrue);
    });
  });

  group('bucketOf', () {
    test('ASCII 字母数字取大写首字符', () {
      expect(OfflineCacheService.bucketOf('rick astley - never'), 'R');
      expect(OfflineCacheService.bucketOf('7 rings'), '7');
    });

    test('中文与符号统一进下划线桶', () {
      expect(OfflineCacheService.bucketOf('周杰伦 - 晴天'), '_');
      expect(OfflineCacheService.bucketOf('【官方 MV】xx'), '_');
      expect(OfflineCacheService.bucketOf(''), '_');
    });
  });

  group('buildFileName', () {
    test('形如「歌手 - 标题 [cid]」，并净化标题里的非法字符', () {
      final out = OfflineCacheService.buildFileName(
        music(title: 'A/B:C', artist: 'Rick Astley'),
        '137649199',
      );
      expect(out, 'Rick Astley - A_B_C [137649199]');
    });

    test('缺歌手/标题时用兜底值，cid 为空则不带方括号', () {
      expect(
        OfflineCacheService.buildFileName(
          music(title: '  ', artist: '  ', id: 'BV1abc'),
          '',
        ),
        '未知艺术家 - BV1abc',
      );
    });
  });

  group('音质档位判定', () {
    // 直接构造服务实例：isQualitySufficient 只读静态档位表，不碰 DB/网络。
    final service = OfflineCacheService();

    test('已有档位 >= 请求档位时够用', () {
      expect(
        service.isQualitySufficient(_track('30280'), '30232'),
        isTrue,
        reason: '192K 文件可直接满足 132K 请求',
      );
      expect(service.isQualitySufficient(_track('30280'), '30280'), isTrue);
      expect(
        service.isQualitySufficient(_track('30250'), '30251'),
        isFalse,
        reason: '杜比不能顶替 Hi-Res，需要重下',
      );
    });

    test('已有档位低于请求档位时不够用（触发重下）', () {
      expect(service.isQualitySufficient(_track('30216'), '30280'), isFalse);
    });

    test('未知档位不做判断，直接用已有文件', () {
      expect(service.isQualitySufficient(_track('30216'), '99999'), isTrue);
    });
  });
}

/// 测试用的最小离线记录（只关心 qualityId，其余字段填占位值）。
OfflineTrack _track(String qualityId) => OfflineTrack(
  bvid: 'BV1x',
  cid: '100',
  title: '标题',
  artist: '歌手',
  filePath: r'C:\offline\标题.m4a',
  qualityId: qualityId,
  fileSize: 1024,
  downloadedAt: DateTime(2026),
);
