import 'package:bilimusic/shared/utils/svg_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// SVG path 解析：相对命令、隐式重复、贝塞尔反射与圆弧。
void main() {
  test('相对命令与绝对命令得到同一形状', () {
    final absolute = svgPathFromData('M1 1 L3 1 L3 3 Z');
    final relative = svgPathFromData('M1 1 l2 0 l0 2 z');
    expect(relative.getBounds(), absolute.getBounds());
    expect(absolute.getBounds(), const Rect.fromLTRB(1, 1, 3, 3));
  });

  test('M 之后的坐标对按 L 隐式重复', () {
    final path = svgPathFromData('M0 0 10 0 10 10');
    expect(path.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
  });

  test('H / V 命令', () {
    final path = svgPathFromData('M0 0 H10 V10 H0 Z');
    expect(path.getBounds(), const Rect.fromLTRB(0, 0, 10, 10));
  });

  test('小写 h / v 是相对位移', () {
    final relative = svgPathFromData('M1 1 h2 v2 h-2 z');
    expect(relative.getBounds(), const Rect.fromLTRB(1, 1, 3, 3));
  });

  test('S 反射上一段三次贝塞尔的控制点', () {
    final shorthand = svgPathFromData('M0 0 C0 10 10 10 10 0 S20 -10 20 0');
    final explicit = svgPathFromData(
      'M0 0 C0 10 10 10 10 0 C10 -10 20 -10 20 0',
    );
    expect(shorthand.getBounds(), explicit.getBounds());
  });

  test('T 反射上一段二次贝塞尔的控制点', () {
    final shorthand = svgPathFromData('M0 0 Q5 10 10 0 T20 0');
    final explicit = svgPathFromData('M0 0 Q5 10 10 0 Q15 -10 20 0');
    expect(shorthand.getBounds(), explicit.getBounds());
  });

  test('A 圆弧命令', () {
    final path = svgPathFromData('M0 0 A5 5 0 0 1 10 0');
    final bounds = path.getBounds();
    expect(bounds.width, closeTo(10, 0.001));
    expect(bounds.height, closeTo(5, 0.001));
  });

  test('非法数据抛 FormatException', () {
    expect(() => svgPathFromData('M0'), throwsFormatException);
    expect(() => svgPathFromData('X0 0'), throwsFormatException);
    expect(
      () => svgPathFromData('M0 0 A5 5 0 2 1 10 0'),
      throwsFormatException,
    );
    // Z 之后没有新命令时不能把坐标当成隐式重复（否则会死循环）。
    expect(() => svgPathFromData('M0 0 Z 1 1'), throwsFormatException);
  });
}
