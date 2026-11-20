import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/bili_image.dart';

void main() {
  group('biliImageUrl', () {
    test('正方形：追加 _1c 并精确裁切', () {
      expect(
        biliSquareUrl('http://i0.hdslb.com/bfs/archive/a.jpg', 96),
        'http://i0.hdslb.com/bfs/archive/a.jpg@96w_96h_1c',
      );
    });

    test('16:9：按宽度算高度', () {
      expect(
        biliWideUrl('https://i2.hdslb.com/bfs/archive/a.jpg', 1344),
        'https://i2.hdslb.com/bfs/archive/a.jpg@1344w_756h_1c',
      );
    });

    test('已有 B 站变换会被替换，保证幂等', () {
      const raw = 'https://i0.hdslb.com/bfs/archive/a.jpg@672w_378h';
      expect(
        biliSquareUrl(raw, 672),
        'https://i0.hdslb.com/bfs/archive/a.jpg@672w_672h_1c',
      );
      expect(
        biliSquareUrl(biliSquareUrl(raw, 96), 96),
        'https://i0.hdslb.com/bfs/archive/a.jpg@96w_96h_1c',
      );
    });

    test('保留 query / fragment', () {
      expect(
        biliSquareUrl('https://i0.hdslb.com/bfs/archive/a.jpg?x=1#frag', 96),
        'https://i0.hdslb.com/bfs/archive/a.jpg@96w_96h_1c?x=1#frag',
      );
    });

    test('协议相对地址补 https', () {
      expect(
        biliFaceUrl('//i1.hdslb.com/bfs/face/a.jpg', 96),
        'https://i1.hdslb.com/bfs/face/a.jpg@96w_96h_1c',
      );
    });

    test('非 B 站域名 / 空串 / 相对路径原样返回', () {
      expect(
        biliSquareUrl('https://example.com/a.jpg', 96),
        'https://example.com/a.jpg',
      );
      expect(biliSquareUrl('', 96), '');
      expect(biliSquareUrl('assets/a.jpg', 96), 'assets/a.jpg');
    });

    test('biliimg.com 域名同样处理', () {
      expect(
        biliSquareUrl('https://archive.biliimg.com/bfs/archive/a.jpg', 96),
        'https://archive.biliimg.com/bfs/archive/a.jpg@96w_96h_1c',
      );
    });
  });
}
