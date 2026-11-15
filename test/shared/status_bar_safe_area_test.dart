import 'package:bilimusic/shared/ui/sections/status_bar_safe_area.dart';
import 'package:bilimusic/shared/utils/duo_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 顶部状态栏里页头的摆放。数值取自 iOS 27.1 的 iPhone Duo 模拟器展开竖拿
/// （669×951，顶部安全区 82）：系统给 44pt 顶部栏的区域是上 26、右 144，
/// 给 56pt 工具栏的区域是上 24。
void main() {
  const layout = TopBarLayout(
    rowTop: 26,
    toolbarTop: 24,
    leading: 16,
    trailing: 144,
    statusBarHeight: 82,
    statusRect: Rect.fromLTWH(525, 0, 144, 82),
  );

  group('StatusBarHeaderInset.extraPadding', () {
    test('标签页页头：按钮行落到系统给的顶边，右侧补足到让开时间', () {
      // 首页页头：自身上内边距 16、左右 22，外层没有边距。
      expect(
        StatusBarHeaderInset.extraPadding(
          layout: layout,
          contentTop: 0,
          outerRightMargin: 0,
          ownTopPadding: 16,
          ownRightPadding: 22,
        ),
        const EdgeInsets.only(top: 10, right: 122),
      );
    });

    test('外层已有边距时只补差额', () {
      // 发现页：页头自身没有左右内边距，外层左右各 22。
      expect(
        StatusBarHeaderInset.extraPadding(
          layout: layout,
          contentTop: 0,
          outerRightMargin: 22,
          ownTopPadding: 16,
          ownRightPadding: 0,
        ),
        const EdgeInsets.only(top: 10, right: 122),
      );
    });

    test('已经够低 / 够宽时不再补', () {
      expect(
        StatusBarHeaderInset.extraPadding(
          layout: layout,
          contentTop: 24,
          outerRightMargin: 0,
          ownTopPadding: 16,
          ownRightPadding: 200,
        ),
        EdgeInsets.zero,
      );
    });
  });
}
