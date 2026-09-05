import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:bilimusic/models/music.dart';

/// 轻量文本相似度：3-Gram + 128 位 SimHash + SWAR popcount。
///
/// 算法与 `E:\StudioProjects\tessera\lib\memory\simhash.dart` 同源，
/// 但**去掉 jieba 依赖**——bilimusic pubspec 没有 jieba，且音乐标题短/中英混排，
/// 字符级 3-Gram 反而更稳。
///
/// 用途：RoamingService 在 `/archive/related` 返回的候选歌单里按相似度
/// 排序，按 RoamStyle 选 top-K。
class TextSimHash {
  static const int dimensions = 128;

  /// 把字符串切成 3-Gram token 列表。
  ///
  /// - 长度 < 3 的字符串退化为整串 1 个 token
  /// - 含空白的 token 内部继续按字符切
  /// - 空白归一化为单空格
  static List<String> ngrams3(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];
    if (normalized.length < 3) return [normalized];

    final result = <String>[];
    for (var i = 0; i <= normalized.length - 3; i++) {
      result.add(normalized.substring(i, i + 3));
    }
    return result;
  }

  /// 计算文本的 128 位 SimHash 二进制字符串。
  ///
  /// 算法：
  /// ```
  /// tokens → 每个 token SHA256 种子 → 128 维高斯向量（确定性）
  /// → 累加 → 阈值化（≥0 → '1'，<0 → '0'）
  /// ```
  static String simhash(String text) {
    final tokens = ngrams3(text);
    if (tokens.isEmpty) return '0' * dimensions;

    final uniqueTokens = tokens.toSet();
    final vectors = <String, List<double>>{};
    for (final t in uniqueTokens) {
      vectors[t] = _randomVector(t);
    }

    final sum = List<double>.filled(dimensions, 0.0);
    for (final t in tokens) {
      final v = vectors[t]!;
      for (var i = 0; i < dimensions; i++) {
        sum[i] += v[i];
      }
    }

    final sb = StringBuffer();
    for (var i = 0; i < dimensions; i++) {
      sb.write(sum[i] >= 0 ? '1' : '0');
    }
    return sb.toString();
  }

  // 64-bit SWAR popcount 常量（用 BigInt 字符串构造，避开 dart2js 53 位限制）。
  static final _popM1 = BigInt.parse('5555555555555555', radix: 16);
  static final _popM2 = BigInt.parse('3333333333333333', radix: 16);
  static final _popM4 = BigInt.parse('0f0f0f0f0f0f0f0f', radix: 16);
  static final _popM7f = BigInt.parse('7f', radix: 16);

  /// 64-bit SWAR popcount（统计二进制 1 的个数）。
  ///
  /// BigInt 实现：在 Web (dart2js) 上 64 位 int 字面量无法精确表示，
  /// 且 BigInt→int 会在 > 53 位时静默截断。所以整路径走 BigInt，最后才落回 int。
  static int _popcount64(BigInt x) {
    x = x - ((x >> 1) & _popM1);
    x = (x & _popM2) + ((x >> 2) & _popM2);
    x = (x + (x >> 4)) & _popM4;
    x = x + (x >> 8);
    x = x + (x >> 16);
    x = x + (x >> 32);
    return (x & _popM7f).toInt();
  }

  /// 将 64 位二进制字符串解析为有符号 64 位 BigInt。
  static BigInt _parseBits64(String s) {
    return BigInt.parse(s, radix: 2).toSigned(64);
  }

  /// 两条 128 位 SimHash 之间的汉明距离（高 64 + 低 64 XOR + popcount）。
  ///
  /// 比逐字符比较快约 10x。
  static int hammingFast(String a, String b) {
    assert(
      a.length == dimensions && b.length == dimensions,
      'SimHash 位串长度必须为 $dimensions',
    );
    final hiA = _parseBits64(a.substring(0, 64));
    final loA = _parseBits64(a.substring(64, 128));
    final hiB = _parseBits64(b.substring(0, 64));
    final loB = _parseBits64(b.substring(64, 128));
    return _popcount64(hiA ^ hiB) + _popcount64(loA ^ loB);
  }

  /// 把 Music 拍平成 simhash 输入文本：`title + artist + album`，缺失字段跳过。
  static String musicToText(Music m) {
    final parts = <String>[
      m.title,
      if (m.artist.isNotEmpty) m.artist,
      if (m.album.isNotEmpty) m.album,
    ];
    return parts.join(' ');
  }

  // ── 内部：确定性高斯随机向量 ──

  /// Box-Muller 生成标准正态随机数。
  static double _gauss(Random rng) {
    final u1 = rng.nextDouble();
    final u2 = rng.nextDouble();
    return sqrt(-2.0 * log(max(u1, 1e-10))) * cos(2.0 * pi * u2);
  }

  /// 用 token 的 SHA256 作为种子，生成 128 维确定性高斯向量。
  /// 同一 token 始终得到同一向量。
  static List<double> _randomVector(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes);
    final seed =
        BigInt.parse(digest.toString(), radix: 16) % BigInt.from(1 << 31);

    final rng = Random(seed.toInt());
    final v = <double>[];
    for (var i = 0; i < dimensions; i++) {
      v.add(_gauss(rng));
    }

    // 归一化到单位向量
    final magnitude = sqrt(v.fold(0.0, (sum, x) => sum + x * x));
    if (magnitude > 0) {
      for (var i = 0; i < dimensions; i++) {
        v[i] /= magnitude;
      }
    }
    return v;
  }
}
