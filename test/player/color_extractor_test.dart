import 'dart:convert';
import 'dart:typed_data';

import 'package:bilimusic/features/player/now_playing/color_extractor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ColorExtractor：主色口径（占比最高，而非最亮）与图片字节解码。
void main() {
  // 20×20 PNG：80% #3B6EA5 + 20% #FFF200（亮黄）。按旧「最亮」口径会取到黄，
  // 现在必须取到占比最高的蓝。
  const mixedPng =
      'iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAIAAAAC64paAAAAIklEQVR42mO0zlvKQC5gYqAA'
      'jGoe1TyqmdqaGf9/GnF+BgBvGwNmU/RY4QAAAABJRU5ErkJggg==';

  Uint8List rgbaPixels(List<List<int>> pixels) {
    return Uint8List.fromList([for (final pixel in pixels) ...pixel]);
  }

  group('dominantColorFromRgba', () {
    test('取占比最高的颜色，不被更亮的颜色带偏', () {
      final rgba = rgbaPixels([
        for (var i = 0; i < 12; i++) const [0x3B, 0x6E, 0xA5, 0xFF],
        for (var i = 0; i < 4; i++) const [0xFF, 0xF2, 0x00, 0xFF],
      ]);

      expect(
        ColorExtractor.dominantColorFromRgba(rgba, width: 4, height: 4),
        const Color(0xFF3B6EA5),
      );
    });

    test('跳过半透明与接近纯白的像素', () {
      final rgba = rgbaPixels([
        const [0xFF, 0x00, 0x00, 0x00], // 全透明红
        const [0xFF, 0xFF, 0xFF, 0xFF], // 纯白
        const [0x00, 0xC8, 0x00, 0xFF], // 绿
        const [0x00, 0xC8, 0x00, 0xFF], // 绿
      ]);

      expect(
        ColorExtractor.dominantColorFromRgba(rgba, width: 2, height: 2),
        const Color(0xFF00C800),
      );
    });

    test('全是白色或数据不足时返回 null', () {
      final white = rgbaPixels([
        for (var i = 0; i < 4; i++) const [0xFF, 0xFF, 0xFF, 0xFF],
      ]);
      expect(
        ColorExtractor.dominantColorFromRgba(white, width: 2, height: 2),
        isNull,
      );
      expect(
        ColorExtractor.dominantColorFromRgba(Uint8List(4), width: 2, height: 2),
        isNull,
      );
    });
  });

  testWidgets('编码后的图片字节会被真正解码，而不是当 RGBA 直接读', (tester) async {
    await tester.runAsync(() async {
      final color = await ColorExtractor.extractColorFromBytes(
        base64Decode(mixedPng),
      );
      expect(color, const Color(0xFF3B6EA5));
    });
  });
}
