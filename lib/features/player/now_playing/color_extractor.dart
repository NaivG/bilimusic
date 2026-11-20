import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_image.dart';

/// 从封面图里取主色。
///
/// 把像素量化到4bit/通道的桶里统计数量，取最大桶的平均色，而不是从调色板里挑最亮的一档。
/// 网络图走 [imageCacheManager]，与背景虚化层共用同一份磁盘缓存。
class ColorExtractor {
  ColorExtractor._();

  /// 最近取过的封面主色。重进详情页 / 来回切歌时不用再下载解码，
  /// 纯色背景也就不会先闪一下黑。
  static final Map<String, Color> _cache = <String, Color>{};
  static const int _cacheLimit = 64;

  /// 取网络封面的主色；空地址 / 下载失败 / 解码失败返回 null。
  static Future<Color?> extractColorFromUrl(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    final cached = cachedColorOf(imageUrl);
    if (cached != null) return cached;

    try {
      final file = await imageCacheManager.getSingleFile(
        biliSquareUrl(imageUrl, 64),
        headers: NetworkConfig.biliHeaders,
      );
      final color = await extractColorFromBytes(await file.readAsBytes());
      if (color != null) _remember(imageUrl, color);
      return color;
    } catch (e) {
      debugPrint('Error extracting color from image: $e');
      return null;
    }
  }

  /// 已取过色的封面可以直接拿到结果；没取过返回 null。
  static Color? cachedColorOf(String imageUrl) => _cache[imageUrl];

  /// 从编码后的图片字节里取主色。
  static Future<Color?> extractColorFromBytes(Uint8List bytes) async {
    // 只解到 64px 宽：取色只看色块占比，原图尺寸解码又慢又占内存。
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 64,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        return dominantColorFromRgba(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          width: image.width,
          height: image.height,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// 从 RGBA 原始像素里取占比最高的颜色。
  ///
  /// 跳过半透明与接近纯白的像素：透明边和白色底会把整块背景染成灰。
  static Color? dominantColorFromRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) return null;
    final pixelCount = width * height;
    if (rgba.length < pixelCount * 4) return null;

    // 4bit/通道 → 16 × 16 × 16 个桶；计数与三通道累加分开存，最后取均值。
    final counts = Uint32List(4096);
    final redSums = Uint32List(4096);
    final greenSums = Uint32List(4096);
    final blueSums = Uint32List(4096);

    for (var i = 0; i < pixelCount; i++) {
      final offset = i * 4;
      if (rgba[offset + 3] < 125) continue;
      final red = rgba[offset];
      final green = rgba[offset + 1];
      final blue = rgba[offset + 2];
      if (red > 250 && green > 250 && blue > 250) continue;

      final bucket = ((red >> 4) << 8) | ((green >> 4) << 4) | (blue >> 4);
      counts[bucket] += 1;
      redSums[bucket] += red;
      greenSums[bucket] += green;
      blueSums[bucket] += blue;
    }

    var best = 0;
    for (var i = 1; i < counts.length; i++) {
      if (counts[i] > counts[best]) best = i;
    }
    final count = counts[best];
    if (count == 0) return null;

    return Color.fromARGB(
      255,
      redSums[best] ~/ count,
      greenSums[best] ~/ count,
      blueSums[best] ~/ count,
    );
  }

  static void _remember(String imageUrl, Color color) {
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[imageUrl] = color;
  }
}
