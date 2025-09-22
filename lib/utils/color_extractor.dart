import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:color_thief_dart/color_thief_dart.dart';
import 'package:flutter/material.dart';

class ColorExtractor {
  /// 从网络图片URL提取主色调
  static Future<Color?> extractColorFromUrl(String imageUrl) async {
    try {
      // 下载图片数据
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        // 使用color_thief_dart提取主色调
        final palette = await getPaletteFromBytes(response.bodyBytes, 10, 6);
        
        if (palette != null && palette.isNotEmpty) {
          // 转换为Color对象并返回最亮的颜色作为主色调
          final colors = palette.map((color) => Color.fromRGBO(color[0], color[1], color[2], 1.0)).toList();
          return _getBrightestColor(colors);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error extracting color from image: $e');
      return null;
    }
  }

  /// 从颜色列表中找出最亮的颜色
  static Color _getBrightestColor(List<Color> colors) {
    Color brightest = colors[0];
    double maxBrightness = _calculateBrightness(brightest);

    for (int i = 1; i < colors.length; i++) {
      final brightness = _calculateBrightness(colors[i]);
      if (brightness > maxBrightness) {
        maxBrightness = brightness;
        brightest = colors[i];
      }
    }

    return brightest;
  }

  /// 计算颜色的亮度
  static double _calculateBrightness(Color color) {
    // 使用相对亮度公式计算亮度
    return (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) / 255;
  }
}