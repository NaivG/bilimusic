import 'package:bilimusic/shared/utils/duo_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// DuoLayoutSnapshot：解析原生侧推来的系统数值，换算出竖栏、状态栏那一行
/// 的顶栏位置和折痕。数值取自 iOS 27.1 的 iPhone Duo 模拟器（见
/// 《iPhone Duo 布局规范》的实测表）。
void main() {
  Map<String, Object?> payload({
    required List<double> size,
    required List<double> safe,
    String edge = 'none',
    List<double>? sideBar,
    List<List<double>> topBars = const [
      [24, 16, 0, 16],
      [24, 16, 0, 16],
    ],
    List<List<double>> occlusions = const [],
    List<List<double>> divisions = const [],
    bool statusBarHidden = false,
  }) => {
    'size': size,
    'safeArea': safe,
    'verticalBarEdge': edge,
    'sideBar': ?sideBar,
    'topBars': topBars,
    'occlusions': occlusions,
    'divisions': divisions,
    'statusBarHidden': statusBarHidden,
  };

  final folded = payload(
    size: [466, 678],
    safe: [24, 0, 34, 84],
    edge: 'right',
    sideBar: [174, 394, 34, 24],
    topBars: [
      [24, 2.3, 610, 84],
      [24, 2.3, 598, 84],
    ],
    occlusions: [
      [399.7, 29.3, 37, 37, 1],
      [382, 0, 84, 174, 1],
    ],
  );

  final unfoldedPortrait = payload(
    size: [669, 951],
    safe: [82, 0, 83, 0],
    topBars: [
      [26, 16, 881, 144],
      [24, 16, 871, 144],
    ],
    occlusions: [
      [525, 0, 144, 82, 1],
      [611, 677.3, 37, 58, 0],
    ],
    divisions: [
      [0, 455.5, 669, 40, 0],
    ],
  );

  final halfOpenLandscape = payload(
    size: [951, 669],
    safe: [24, 0, 34, 84],
    edge: 'right',
    sideBar: [124, 879, 34, 24],
    occlusions: [
      [867, 0, 84, 124, 1],
    ],
    divisions: [
      [455.5, 0, 40, 669, 1],
    ],
  );

  DuoLayoutSnapshot parse(Map<String, Object?> map) =>
      DuoLayoutSnapshot.fromMap(map)!;

  test('合上：右侧竖栏，按钮区从状态栏下面开始', () {
    final snapshot = parse(folded);
    expect(
      snapshot.verticalBar,
      const VerticalBar(onLeft: false, width: 84, barTop: 174, barBottom: 34),
    );
    expect(snapshot.topBar, isNull);
    expect(snapshot.verticalDivision, isNull);
  });

  test('展开竖拿：没有竖栏，状态栏那一行放顶栏', () {
    final snapshot = parse(unfoldedPortrait);
    expect(snapshot.verticalBar, isNull);
    expect(
      snapshot.topBar,
      const TopBarLayout(
        rowTop: 26,
        toolbarTop: 24,
        leading: 16,
        trailing: 144,
        statusBarHeight: 82,
        statusRect: Rect.fromLTWH(525, 0, 144, 82),
      ),
    );
    // 内屏摄像头和横向折痕都没有生效。
    expect(snapshot.activeDivisions, isEmpty);
  });

  test('横拿半开：竖栏在右，折痕在屏幕中间', () {
    final snapshot = parse(halfOpenLandscape);
    expect(snapshot.verticalBar?.barTop, 124);
    expect(snapshot.topBar, isNull);
    expect(snapshot.verticalDivision, const Rect.fromLTWH(455.5, 0, 40, 669));
  });

  test('状态栏被隐藏时沿用之前的顶栏位置', () {
    final shown = parse(unfoldedPortrait);
    final hidden = parse(
      payload(
        size: [669, 951],
        safe: [0, 0, 34, 0],
        topBars: [
          [26, 16, 881, 16],
          [24, 16, 871, 16],
        ],
        statusBarHidden: true,
      ),
    );
    expect(hidden.topBar, isNull);
    expect(hidden.keepingTopBarOf(shown).topBar, shown.topBar);
    // 窗口尺寸变了（开合）就不再沿用。
    expect(hidden.keepingTopBarOf(parse(folded)).topBar, isNull);
  });

  test('普通 iPhone：没有竖栏，顶边整条是状态栏，不算状态栏那一行', () {
    final snapshot = parse(
      payload(
        size: [402, 874],
        safe: [62, 0, 34, 0],
        occlusions: [
          [0, 0, 402, 62, 1],
        ],
      ),
    );
    expect(snapshot.verticalBar, isNull);
    expect(snapshot.topBar, isNull);
  });

  test('数据不完整时返回 null', () {
    expect(DuoLayoutSnapshot.fromMap({}), isNull);
    expect(
      DuoLayoutSnapshot.fromMap({
        'size': [466, 678],
        'safeArea': [24, 0, 34, 84],
        'topBars': [
          [24, 2.3, 610, 84],
        ],
      }),
      isNull,
    );
  });
}
