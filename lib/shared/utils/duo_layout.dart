import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:bilimusic/shared/utils/platform_helper.dart';

/// iPhone Duo 的系统布局数值（`ios/Runner/DuoFlutterViewController.swift`）。
///
/// Flutter 只拿得到普通安全区。iPhone Duo 上，竖栏在哪一边、栏该放在哪、
/// 状态栏 / 摄像头 / 折痕占了哪些地方，都由 UIKit 给出（iOS 27.1）。原生侧
/// 每次布局后读取、有变化才推过来；这里保存成可监听的值，外壳和页面按它
/// 摆放，不写死任何尺寸、不靠安全区阈值猜。
///
/// 其他平台、iOS 27.1 以下拿不到时 [current] 为 null，一切按原来的布局。
abstract final class DuoLayout {
  static const MethodChannel _channel = MethodChannel('bilimusic/duo_layout');

  /// 最新的系统布局数值。
  static final ValueNotifier<DuoLayoutSnapshot?> current = ValueNotifier(null);

  static bool _initialized = false;

  /// 开始接收。在 runApp 之前调用，首帧就用对的布局。
  static Future<void> initialize() async {
    if (!PlatformHelper.isIOS || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'update') _apply(call.arguments);
    });
    try {
      _apply(await _channel.invokeMethod<Object?>('get'));
    } on MissingPluginException {
      // 没有原生实现（比如测试宿主）：保持 null。
    } on PlatformException catch (e) {
      debugPrint('[DuoLayout] 读取失败：${e.message}');
    }
  }

  static void _apply(Object? arguments) {
    if (arguments is! Map) return;
    final next = DuoLayoutSnapshot.fromMap(arguments);
    if (next == null) return;
    current.value = next.keepingTopBarOf(current.value);
  }

  /// 当前窗口的布局数值；尺寸和窗口对不上（开合过渡中的旧值）时返回 null。
  ///
  /// 通过 [DuoLayoutScope] 依赖，数值变化时调用方会重建。
  static DuoLayoutSnapshot? of(BuildContext context) {
    final snapshot = DuoLayoutScope.snapshotOf(context);
    if (snapshot == null) return null;
    final size = MediaQuery.sizeOf(context);
    if ((snapshot.size.width - size.width).abs() > 1 ||
        (snapshot.size.height - size.height).abs() > 1) {
      return null;
    }
    return snapshot;
  }

  /// 竖栏；没有竖栏（或拿不到数值）时为 null。
  static VerticalBar? verticalBarOf(BuildContext context) =>
      of(context)?.verticalBar;

  /// 展开竖拿时状态栏那一行里放顶栏的位置；其他情况为 null。
  static TopBarLayout? topBarOf(BuildContext context) => of(context)?.topBar;
}

/// 让子树依赖 [DuoLayout.current]，数值变化时重建。放在外壳最外层。
class DuoLayoutScope
    extends InheritedNotifier<ValueNotifier<DuoLayoutSnapshot?>> {
  DuoLayoutScope({super.key, required super.child})
    : super(notifier: DuoLayout.current);

  static DuoLayoutSnapshot? snapshotOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DuoLayoutScope>();
    return scope?.notifier?.value;
  }
}

/// 系统占用 / 分割的一块区域。
@immutable
class ReservedRegion {
  const ReservedRegion(this.rect, {required this.active});

  final Rect rect;

  /// 是否正在生效（例如折痕只有半开时生效）。
  final bool active;

  @override
  bool operator ==(Object other) =>
      other is ReservedRegion && other.rect == rect && other.active == active;

  @override
  int get hashCode => Object.hash(rect, active);

  @override
  String toString() => 'ReservedRegion($rect${active ? '' : ', inactive'})';
}

/// 竖栏（合上，或展开横拿）。
@immutable
class VerticalBar {
  const VerticalBar({
    required this.onLeft,
    required this.width,
    required this.barTop,
    required this.barBottom,
  });

  /// 竖栏在左侧（否则在右侧）。
  final bool onLeft;

  /// 竖栏宽度，即这一侧的安全区宽度。
  final double width;

  /// 竖栏里放按钮的区域离屏幕顶边的距离：上面是摄像头和状态栏。
  final double barTop;

  /// 竖栏里放按钮的区域离屏幕底边的距离。
  final double barBottom;

  /// 把竖栏那一侧的安全区从子树里去掉：这一侧由竖栏占用。
  Widget removePadding({required BuildContext context, required Widget child}) {
    // padding 和 viewPadding 一起去掉，子树里不会重复让出这一侧。
    final data = MediaQuery.of(context)
        .removePadding(removeLeft: onLeft, removeRight: !onLeft)
        .removeViewPadding(removeLeft: onLeft, removeRight: !onLeft);
    return MediaQuery(data: data, child: child);
  }

  @override
  bool operator ==(Object other) =>
      other is VerticalBar &&
      other.onLeft == onLeft &&
      other.width == width &&
      other.barTop == barTop &&
      other.barBottom == barBottom;

  @override
  int get hashCode => Object.hash(onLeft, width, barTop, barBottom);

  @override
  String toString() =>
      'VerticalBar(${onLeft ? 'left' : 'right'}, $width, $barTop–$barBottom)';
}

/// 展开竖拿时，状态栏那一行里放顶栏的位置。
///
/// 这时状态栏只占右上角一块，系统给一条栏放进顶部的区域会让开它、并和
/// 时间那一行对齐（`UIView.LayoutRegion.bar(onEdge: .top, extent:)`）。
@immutable
class TopBarLayout {
  const TopBarLayout({
    required this.rowTop,
    required this.toolbarTop,
    required this.leading,
    required this.trailing,
    required this.statusBarHeight,
    required this.statusRect,
  });

  /// 页头按钮行（高 [rowExtent]）的顶边。
  final double rowTop;

  /// 导航栏工具栏（高 [toolbarExtent]）的顶边。
  final double toolbarTop;

  /// 左侧要让开的宽度（屏幕圆角）。
  final double leading;

  /// 右侧要让给状态栏的宽度（从屏幕右边缘算起）。
  final double trailing;

  /// 顶部安全区：这一行的底边，页面内容从这里开始。
  final double statusBarHeight;

  /// 状态栏占用的区域。
  final Rect statusRect;

  /// 页头按钮行的高度：44pt 的按钮。
  static const double rowExtent = 44;

  /// 导航栏工具栏的高度。
  static const double toolbarExtent = 56;

  @override
  bool operator ==(Object other) =>
      other is TopBarLayout &&
      other.rowTop == rowTop &&
      other.toolbarTop == toolbarTop &&
      other.leading == leading &&
      other.trailing == trailing &&
      other.statusBarHeight == statusBarHeight &&
      other.statusRect == statusRect;

  @override
  int get hashCode => Object.hash(
    rowTop,
    toolbarTop,
    leading,
    trailing,
    statusBarHeight,
    statusRect,
  );

  @override
  String toString() =>
      'TopBarLayout(row $rowTop, toolbar $toolbarTop, $leading–$trailing, '
      'height $statusBarHeight, status $statusRect)';
}

/// 原生侧一次推送的系统布局数值（逻辑像素）。
@immutable
class DuoLayoutSnapshot {
  const DuoLayoutSnapshot({
    required this.size,
    required this.safeArea,
    required this.verticalBarEdge,
    required this.sideBar,
    required this.topBarRow,
    required this.topBarToolbar,
    required this.occlusions,
    required this.divisions,
    required this.statusBarHidden,
    this.keptTopBar,
  });

  /// 窗口尺寸。
  final Size size;

  /// 普通安全区。
  final EdgeInsets safeArea;

  /// 竖栏所在的边：`left` / `right`，没有竖栏时为 null。
  final AxisDirection? verticalBarEdge;

  /// 竖栏里放一条栏的区域（到四条边的距离）；没有竖栏时为 null。
  final EdgeInsets? sideBar;

  /// 顶部放一条 [TopBarLayout.rowExtent] 高的栏的区域。
  final EdgeInsets topBarRow;

  /// 顶部放一条 [TopBarLayout.toolbarExtent] 高的栏的区域。
  final EdgeInsets topBarToolbar;

  /// 系统占用的区域（状态栏、摄像头），含未生效的。
  final List<ReservedRegion> occlusions;

  /// 分割区域（折痕），含未生效的。
  final List<ReservedRegion> divisions;

  /// 状态栏是否被隐藏。
  final bool statusBarHidden;

  /// 状态栏隐藏时沿用的顶栏位置，见 [keepingTopBarOf]。
  final TopBarLayout? keptTopBar;

  /// 由原生侧推来的 map 构造；数据不完整时返回 null。
  static DuoLayoutSnapshot? fromMap(Map<Object?, Object?> map) {
    final size = _doubles(map['size']);
    final safe = _insets(map['safeArea']);
    final topBars = map['topBars'];
    if (size == null || size.length != 2 || safe == null || topBars is! List) {
      return null;
    }
    if (topBars.length != 2) return null;
    final row = _insets(topBars[0]);
    final toolbar = _insets(topBars[1]);
    if (row == null || toolbar == null) return null;
    final edge = switch (map['verticalBarEdge']) {
      'left' => AxisDirection.left,
      'right' => AxisDirection.right,
      _ => null,
    };
    return DuoLayoutSnapshot(
      size: Size(size[0], size[1]),
      safeArea: safe,
      verticalBarEdge: edge,
      sideBar: edge == null ? null : _insets(map['sideBar']),
      topBarRow: row,
      topBarToolbar: toolbar,
      occlusions: _regions(map['occlusions']),
      divisions: _regions(map['divisions']),
      statusBarHidden: map['statusBarHidden'] == true,
    );
  }

  /// App 自己隐藏状态栏时（例如沉浸式页面），占用区域里不再有状态栏；
  /// 沿用状态栏显示时的顶栏位置，否则状态栏再出现时按钮会压到它。
  DuoLayoutSnapshot keepingTopBarOf(DuoLayoutSnapshot? previous) {
    if (!statusBarHidden || verticalBarEdge != null) return this;
    final kept = previous?.topBar;
    if (kept == null || previous!.size != size) return this;
    return DuoLayoutSnapshot(
      size: size,
      safeArea: safeArea,
      verticalBarEdge: verticalBarEdge,
      sideBar: sideBar,
      topBarRow: topBarRow,
      topBarToolbar: topBarToolbar,
      occlusions: occlusions,
      divisions: divisions,
      statusBarHidden: statusBarHidden,
      keptTopBar: kept,
    );
  }

  /// 竖栏；没有竖栏时为 null。
  VerticalBar? get verticalBar {
    final edge = verticalBarEdge;
    final bar = sideBar;
    if (edge == null || bar == null) return null;
    final onLeft = edge == AxisDirection.left;
    final width = onLeft ? safeArea.left : safeArea.right;
    if (width <= 0) return null;
    return VerticalBar(
      onLeft: onLeft,
      width: width,
      barTop: bar.top,
      barBottom: bar.bottom,
    );
  }

  /// 展开竖拿时状态栏那一行里放顶栏的位置。
  ///
  /// 条件：没有竖栏，并且顶边上只有一角被状态栏占用。
  TopBarLayout? get topBar {
    if (keptTopBar != null) return keptTopBar;
    if (verticalBarEdge != null) return null;
    final status = occlusions
        .where(
          (region) =>
              region.active &&
              region.rect.top <= 0 &&
              region.rect.width < size.width / 2,
        )
        .map((region) => region.rect)
        .firstOrNull;
    if (status == null || safeArea.top <= 0) return null;
    return TopBarLayout(
      rowTop: topBarRow.top,
      toolbarTop: topBarToolbar.top,
      leading: topBarRow.left,
      trailing: topBarRow.right,
      statusBarHeight: safeArea.top,
      statusRect: status,
    );
  }

  /// 正在生效的分割区域（半开时的折痕）。
  List<Rect> get activeDivisions => [
    for (final region in divisions)
      if (region.active) region.rect,
  ];

  /// 正在生效的竖向折痕（横拿半开时屏幕中间的一条）；没有时为 null。
  Rect? get verticalDivision =>
      activeDivisions.where((rect) => rect.height > rect.width).firstOrNull;

  @override
  bool operator ==(Object other) =>
      other is DuoLayoutSnapshot &&
      other.size == size &&
      other.safeArea == safeArea &&
      other.verticalBarEdge == verticalBarEdge &&
      other.sideBar == sideBar &&
      other.topBarRow == topBarRow &&
      other.topBarToolbar == topBarToolbar &&
      _listEquals(other.occlusions, occlusions) &&
      _listEquals(other.divisions, divisions) &&
      other.statusBarHidden == statusBarHidden &&
      other.keptTopBar == keptTopBar;

  @override
  int get hashCode => Object.hash(
    size,
    safeArea,
    verticalBarEdge,
    sideBar,
    topBarRow,
    topBarToolbar,
    Object.hashAll(occlusions),
    Object.hashAll(divisions),
    statusBarHidden,
    keptTopBar,
  );

  static List<double>? _doubles(Object? value) {
    if (value is! List) return null;
    final result = <double>[];
    for (final item in value) {
      if (item is! num) return null;
      result.add(item.toDouble());
    }
    return result;
  }

  /// `[上, 左, 下, 右]`。
  static EdgeInsets? _insets(Object? value) {
    final v = _doubles(value);
    if (v == null || v.length != 4) return null;
    return EdgeInsets.fromLTRB(v[1], v[0], v[3], v[2]);
  }

  /// `[[x, y, 宽, 高, 是否生效], ...]`。
  static List<ReservedRegion> _regions(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (_doubles(item) case final v? when v.length == 5)
          ReservedRegion(
            Rect.fromLTWH(v[0], v[1], v[2], v[3]),
            active: v[4] != 0,
          ),
    ];
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
