import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/shared/motion/bm_page_switcher.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// [BmPageSwitcher] 的方向化几何、层级、reduce motion 与连续换键。
void main() {
  testWidgets('tab：新页 0.04 视差 + 双淡，240ms 后只留新页', (tester) async {
    final harness = await _pump(tester);

    harness.show('b', BmPageTransitionKind.tab);
    await tester.pump();

    expect(_translation(tester, 'a'), Offset.zero);
    expect(_translation(tester, 'b'), const Offset(0.04, 0));
    expect(_opacity(tester, 'a'), 1);
    expect(_opacity(tester, 'b'), 0);

    await tester.pump(const Duration(milliseconds: 120));
    final incoming = _translation(tester, 'b');
    expect(incoming.dx, inExclusiveRange(0, 0.04));
    expect(_translation(tester, 'a').dx, lessThan(0));
    expect(_opacity(tester, 'a'), inExclusiveRange(0, 1));
    expect(_opacity(tester, 'b'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
    expect(_translation(tester, 'b'), Offset.zero);
    expect(_opacity(tester, 'b'), 1);
  });

  testWidgets('tab 反向：direction -1 时新页从左侧 0.04 进入', (tester) async {
    final harness = await _pump(tester);
    harness.show('b', BmPageTransitionKind.tab, direction: -1);
    await tester.pump();
    expect(_translation(tester, 'b'), const Offset(-0.04, 0));
    expect(_translation(tester, 'a'), Offset.zero);
  });

  testWidgets('push：新页从 1.0 滑入，旧页退到 -0.3 并压暗', (tester) async {
    final harness = await _pump(tester);

    harness.show('b', BmPageTransitionKind.push);
    await tester.pump();

    expect(_translation(tester, 'b'), const Offset(1, 0));
    expect(_translation(tester, 'a'), Offset.zero);
    // t=0 时 dim 透明度为 0，覆盖层还没出现。
    expect(_dimOverlay(tester, 'a'), isNull);

    await tester.pump(const Duration(milliseconds: 100));
    final incoming = _translation(tester, 'b');
    final outgoing = _translation(tester, 'a');
    expect(incoming.dx, inExclusiveRange(0, 1));
    expect(outgoing.dx, inInclusiveRange(-0.3, 0));
    final dim = _dimOverlay(tester, 'a');
    expect(dim, isNotNull);
    expect(dim!.a, greaterThan(0));

    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
    expect(_translation(tester, 'b'), Offset.zero);
  });

  testWidgets('push / pop 在 300ms 窗口内结束，旧页不悬挂', (tester) async {
    final harness = await _pump(tester);

    harness.show('b', BmPageTransitionKind.push);
    await tester.pump();

    // 窗口内：旧页仍在，新页尚未归位。
    await tester.pump(const Duration(milliseconds: 280));
    expect(_page('a'), findsOneWidget);
    expect(_translation(tester, 'b').dx, greaterThan(0));

    // 窗口结束：旧页随过渡一起出树，不依赖 pumpAndSettle 兜底。
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump();
    expect(_page('a'), findsNothing);
    expect(_translation(tester, 'b'), Offset.zero);

    harness.show('c', BmPageTransitionKind.pop, direction: -1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump();
    expect(_page('b'), findsNothing);
    expect(_translation(tester, 'c'), Offset.zero);
  });

  testWidgets('页面区域自带裁剪：视差不会画到容器之外', (tester) async {
    final harness = await _pump(tester);
    harness.show('b', BmPageTransitionKind.push);
    await tester.pump();

    final switcher = find.byType(BmPageSwitcher);
    final clip = find
        .ancestor(
          of: find.byKey(const Key('bm-page-switcher-stack')),
          matching: find.byType(ClipRect),
        )
        .first;

    // 裁剪区与页面区域同尺寸；t=0 时新页整页在右缘之外，只能靠裁剪挡住。
    final area = tester.getRect(switcher);
    expect(tester.getRect(clip), area);
    expect(
      tester.getRect(_page('b')).left,
      greaterThanOrEqualTo(area.right - 0.01),
    );
  });

  testWidgets('pop：回归页从 -0.3 回来，旧页向右滑出且盖在上层', (tester) async {
    final harness = await _pump(tester);

    harness.show('b', BmPageTransitionKind.pop, direction: -1);
    await tester.pump();

    expect(_translation(tester, 'b'), const Offset(-0.3, 0));
    expect(_translation(tester, 'a'), Offset.zero);

    final stack = tester.widget<Stack>(
      find.byKey(const Key('bm-page-switcher-stack')),
    );
    expect(stack.children.first.key, const ValueKey('b'));
    expect(stack.children.last.key, const ValueKey('a'));

    await tester.pump(const Duration(milliseconds: 100));
    expect(_translation(tester, 'b').dx, inExclusiveRange(-0.3, 0));
    expect(_translation(tester, 'a').dx, greaterThan(0));
    expect(_dimOverlay(tester, 'a'), isNotNull);

    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
  });

  testWidgets('push：下层旧页裁到新页左缘之外，透明底不漏出叠影', (tester) async {
    final harness = await _pump(tester);
    final size = tester.getSize(find.byType(BmPageSwitcher));

    harness.show('b', BmPageTransitionKind.push);
    await tester.pump();

    // t=0：新页整幅还在右缘之外，旧页整幅可见；上层新页不裁。
    expect(_bandClip(tester, 'a'), isNotNull);
    expect(_bandRect(tester, 'a'), Offset.zero & size);
    expect(_bandClip(tester, 'b'), isNull);

    await tester.pump(const Duration(milliseconds: 100));
    final dx = _translation(tester, 'b').dx;
    expect(dx, inExclusiveRange(0, 1));
    final band = _bandRect(tester, 'a');
    expect(band.left, 0);
    expect(band.right, closeTo(size.width * dx, 0.01));
    expect(band.bottom, size.height);
    expect(_bandClip(tester, 'b'), isNull);

    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
  });

  testWidgets('pop：下层回归页裁到退出页左缘之外，边界不叠影', (tester) async {
    final harness = await _pump(tester);
    final size = tester.getSize(find.byType(BmPageSwitcher));

    harness.show('b', BmPageTransitionKind.pop, direction: -1);
    await tester.pump();

    // t=0：退出的旧页整幅盖在上面，回归页没有可见带。
    expect(_bandRect(tester, 'b').width, closeTo(0, 0.01));
    expect(_bandClip(tester, 'a'), isNull);

    await tester.pump(const Duration(milliseconds: 100));
    final outgoingDx = _translation(tester, 'a').dx;
    expect(outgoingDx, inExclusiveRange(0, 1));
    final band = _bandRect(tester, 'b');
    expect(band.left, 0);
    expect(band.right, closeTo(size.width * outgoingDx, 0.01));
    expect(_bandClip(tester, 'a'), isNull);

    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
  });

  testWidgets('tab / replace：交叉淡化，不做下层可见带裁剪', (tester) async {
    for (final kind in [
      BmPageTransitionKind.tab,
      BmPageTransitionKind.replace,
    ]) {
      final harness = await _pump(tester);
      harness.show('b', kind);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(_bandClip(tester, 'a'), isNull, reason: '$kind 的旧页不该被裁');
      expect(_bandClip(tester, 'b'), isNull, reason: '$kind 的新页不该被裁');

      await tester.pumpAndSettle();
      expect(_page('a'), findsNothing);
    }
  });

  testWidgets('reduce motion：push 退化为双淡，不做可见带裁剪', (tester) async {
    final harness = await _pump(tester, reduceMotion: true);
    harness.show('b', BmPageTransitionKind.push);
    await tester.pump();

    expect(_bandClip(tester, 'a'), isNull);
    expect(_bandClip(tester, 'b'), isNull);

    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
  });

  testWidgets('像素回归：push 时旧页不会从新页的透明底漏出来', (tester) async {
    // 真实页面是「Scaffold 背景透明、透出壳层背景」，所以不能只靠 Stack
    // 的层级；这里用透明页面 + 纯色探针，直接看合成后的像素。
    const background = Color(0xFFFFFFFF);
    const incomingMark = Color(0xFF00FF00);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeRegistry.defaultTheme.light(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: ColoredBox(color: background, child: const _GhostHarness()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = tester.state<_GhostHarnessState>(find.byType(_GhostHarness));
    state.show('b', BmPageTransitionKind.push);
    await tester.pump();

    // 弹簧前段很快；等新页左缘扫进屏幕、但还没盖到旧页右侧探针时取样。
    for (var i = 0; i < 20; i++) {
      if (_translation(tester, 'b').dx < 0.4) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    final incomingDx = _translation(tester, 'b').dx;
    final outgoingDx = _translation(tester, 'a').dx;
    final width = tester.getSize(find.byType(BmPageSwitcher)).width;
    final seam = width * incomingDx;

    final redX = (650 + outgoingDx * width).round();
    final blueX = (250 + outgoingDx * width).round();
    final greenX = (230 + incomingDx * width).round();
    expect(redX, greaterThan(seam + 20), reason: '红色探针此时必须在新页覆盖区内');
    expect(blueX, lessThan(seam - 20), reason: '蓝色探针此时必须在新页左缘之外');
    expect(incomingDx, lessThan(0.4));

    final shot = await _capture(tester, boundaryKey);
    expect(
      shot.pixel(redX, 150),
      background,
      reason: '被新页盖住的旧页内容必须被裁掉，不能透过新页的透明底露出来',
    );
    expect(shot.pixel(greenX, 70), incomingMark, reason: '新页自己的内容照常绘制');
    final strip = shot.pixel(blueX, 350);
    expect(strip.b, greaterThan(0.7), reason: '旧页在视差带里仍然可见');
    expect(strip.r, lessThan(0.2));
    expect(strip.g, lessThan(0.2));

    await tester.pumpAndSettle();
  });

  testWidgets('replace：纯淡入淡出，无位移', (tester) async {
    final harness = await _pump(tester);
    harness.show('b', BmPageTransitionKind.replace, direction: 0);
    await tester.pump();

    expect(_translation(tester, 'a'), Offset.zero);
    expect(_translation(tester, 'b'), Offset.zero);
    expect(_opacity(tester, 'b'), 0);
    expect(_dimOverlay(tester, 'a'), isNull);

    await tester.pump(const Duration(milliseconds: 90));
    expect(_opacity(tester, 'b'), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
  });

  testWidgets('同一 pageKey 重建不播动画，也不丢页面状态', (tester) async {
    final harness = await _pump(tester);
    harness.rebuildSamePage();
    await tester.pump();

    expect(_page('a'), findsOneWidget);
    expect(_page('b'), findsNothing);
    expect(
      tester
          .widget<Stack>(find.byKey(const Key('bm-page-switcher-stack')))
          .children,
      hasLength(1),
    );
  });

  testWidgets('连续换键只保留最后一对旧/新页', (tester) async {
    final harness = await _pump(tester);
    harness.show('b', BmPageTransitionKind.push);
    await tester.pump(const Duration(milliseconds: 40));
    harness.show('c', BmPageTransitionKind.push);
    await tester.pump();

    expect(_page('a'), findsNothing);
    expect(_page('b'), findsOneWidget);
    expect(_page('c'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(_page('b'), findsNothing);
    expect(_page('c'), findsOneWidget);
  });

  testWidgets('A→B→A 快速换键不触发 Duplicate keys', (tester) async {
    final harness = await _pump(tester);
    harness.show('b', BmPageTransitionKind.tab);
    await tester.pump(const Duration(milliseconds: 40));
    harness.show('a', BmPageTransitionKind.tab);
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(_page('a'), findsOneWidget);
    expect(_page('b'), findsNothing);
  });

  testWidgets('reduce motion：只淡入淡出，≤120ms 完成', (tester) async {
    final harness = await _pump(tester, reduceMotion: true);
    harness.show('b', BmPageTransitionKind.push);
    await tester.pump();

    expect(_translation(tester, 'a'), Offset.zero);
    expect(_translation(tester, 'b'), Offset.zero);
    expect(_dimOverlay(tester, 'a'), isNull);
    expect(_opacity(tester, 'b'), 0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(_opacity(tester, 'b'), inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(_page('a'), findsNothing);
    expect(_page('b'), findsOneWidget);
  });

  testWidgets('reduce motion 下 tab 也不产生位移', (tester) async {
    final harness = await _pump(tester, reduceMotion: true);
    harness.show('b', BmPageTransitionKind.tab);
    await tester.pump();
    expect(_translation(tester, 'b'), Offset.zero);
    expect(_translation(tester, 'a'), Offset.zero);
  });
}

Future<_HarnessState> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  final key = GlobalKey<_HarnessState>();
  final theme = ThemeRegistry.defaultTheme.light();
  Widget host = MaterialApp(
    theme: theme,
    home: Scaffold(body: _Harness(key: key)),
  );
  if (reduceMotion) {
    host = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: host,
    );
  }
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
  return key.currentState!;
}

class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Key _pageKey = const ValueKey('a');
  BmPageTransitionKind _kind = BmPageTransitionKind.tab;
  int _direction = 1;

  void show(String name, BmPageTransitionKind kind, {int direction = 1}) {
    setState(() {
      _pageKey = ValueKey(name);
      _kind = kind;
      _direction = direction;
    });
  }

  void rebuildSamePage() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final name = (_pageKey as ValueKey<String>).value;
    return BmPageSwitcher(
      pageKey: _pageKey,
      kind: _kind,
      direction: _direction,
      child: _Page(name: name),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: ValueKey('content-$name'),
      child: ColoredBox(color: Theme.of(context).colorScheme.surface),
    );
  }
}

Finder _page(String name) => find.byKey(ValueKey('content-$name'));

Finder _translationFinder(String name) => find
    .ancestor(of: _page(name), matching: find.byType(FractionalTranslation))
    .first;

Offset _translation(WidgetTester tester, String name) =>
    tester.widget<FractionalTranslation>(_translationFinder(name)).translation;

double _opacity(WidgetTester tester, String name) {
  final finder = find.ancestor(of: _page(name), matching: find.byType(Opacity));
  if (finder.evaluate().isEmpty) return 1;
  return tester.widget<Opacity>(finder.first).opacity;
}

/// 旧页的压暗层：dim 覆盖是页面里的第二个 ColoredBox。
Color? _dimOverlay(WidgetTester tester, String name) {
  final boxes = tester
      .widgetList<ColoredBox>(
        find.descendant(
          of: _translationFinder(name),
          matching: find.byType(ColoredBox),
        ),
      )
      .toList();
  if (boxes.length < 2) return null;
  return boxes.last.color;
}

/// 下层页面的可见带裁剪器（上层页面与不裁剪的过渡都返回 null）。
CustomClipper<Rect>? _bandClip(WidgetTester tester, String name) {
  final clips = tester.widgetList<ClipRect>(
    find.ancestor(of: _page(name), matching: find.byType(ClipRect)),
  );
  for (final clip in clips) {
    if (clip.clipper != null) return clip.clipper;
  }
  return null;
}

/// 当前可见带的实际像素矩形。
Rect _bandRect(WidgetTester tester, String name) {
  final clipper = _bandClip(tester, name);
  expect(clipper, isNotNull, reason: '页面 $name 没有可见带裁剪器');
  return clipper!.getClip(tester.getSize(find.byType(BmPageSwitcher)));
}

Future<_Shot> _capture(WidgetTester tester, GlobalKey boundaryKey) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final image = await tester.runAsync(boundary.toImage);
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return _Shot(image!, data!.buffer.asUint8List());
}

/// 一帧截图；[pixel] 用逻辑坐标取色（`toImage` 默认 pixelRatio 1）。
class _Shot {
  _Shot(this.image, this.bytes);

  final ui.Image image;
  final Uint8List bytes;

  Color pixel(int x, int y) {
    final offset = (y * image.width + x) * 4;
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }
}

/// 像素探针宿主：透明页面，只放几块纯色，用来观察两页合成结果。
class _GhostHarness extends StatefulWidget {
  const _GhostHarness();

  @override
  State<_GhostHarness> createState() => _GhostHarnessState();
}

class _GhostHarnessState extends State<_GhostHarness> {
  Key _pageKey = const ValueKey('a');
  BmPageTransitionKind _kind = BmPageTransitionKind.tab;
  int _direction = 1;

  void show(String name, BmPageTransitionKind kind, {int direction = 1}) {
    setState(() {
      _pageKey = ValueKey(name);
      _kind = kind;
      _direction = direction;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (_pageKey as ValueKey<String>).value;
    return BmPageSwitcher(
      pageKey: _pageKey,
      kind: _kind,
      direction: _direction,
      child: _GhostPage(name: name),
    );
  }
}

/// 透明底页面：a 放红（右侧，会被新页盖住）与蓝（左侧，留在视差带里），
/// b 放绿（新页自己的内容）。
class _GhostPage extends StatelessWidget {
  const _GhostPage({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: ValueKey('content-$name'),
      child: Stack(
        children: [
          if (name == 'a') ...[
            const Positioned(
              left: 600,
              top: 100,
              width: 100,
              height: 100,
              child: ColoredBox(color: Color(0xFFFF0000)),
            ),
            const Positioned(
              left: 200,
              top: 300,
              width: 100,
              height: 100,
              child: ColoredBox(color: Color(0xFF0000FF)),
            ),
          ],
          if (name == 'b')
            const Positioned(
              left: 200,
              top: 40,
              width: 60,
              height: 60,
              child: ColoredBox(color: Color(0xFF00FF00)),
            ),
        ],
      ),
    );
  }
}
