import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/shared/motion/bm_overlay_routes.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/overlay/bm_overlays.dart';
import 'package:bilimusic/shared/ui/settings/bm_settings_group.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 锚定单选浮层：定位、勾选、关闭、动效与设置行接线。
void main() {
  const options = <BmSelectOption<String>>[
    BmSelectOption(value: 'a', label: '跟随系统'),
    BmSelectOption(value: 'b', label: '浅色'),
    BmSelectOption(value: 'c', label: '深色'),
  ];

  testWidgets('从锚点下方弹出：右缘对齐、只勾当前值', (tester) async {
    final host = await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: options,
      selected: 'b',
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pumpAndSettle();

    expect(_menu(), findsOneWidget);
    expect(host.pushed.last, isA<BmSelectMenuRoute<String>>());

    final anchor = tester.getRect(find.byKey(_anchorKey));
    final panel = tester.getRect(find.byType(BmMenuSurface));
    expect(panel.top, closeTo(anchor.bottom + BmTokens.s1, 0.01));
    expect(panel.right, closeTo(anchor.right, 0.01));
    expect(panel.width, 220);

    // 只有当前值一行有对勾。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final selectedRow = find.ancestor(
      of: find.text('浅色'),
      matching: find.byType(BmPressable),
    );
    expect(
      find.descendant(
        of: selectedRow.first,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    // 选项行高至少是触屏 44。
    final row = tester.getRect(
      find
          .ancestor(
            of: find.text('跟随系统'),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(row.height, greaterThanOrEqualTo(BmTokens.touchScreen));

    final scale = tester.widget<ScaleTransition>(_routeScale());
    expect(scale.scale.value, closeTo(1, 1e-6));
  });

  testWidgets('进场 120ms：首帧 0.96、中段介于 0.96 与 1 之间', (tester) async {
    final host = await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: options,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pump();

    expect(host.pushed.last, isA<BmSelectMenuRoute<String>>());
    final route = host.pushed.last as BmSelectMenuRoute<String>;
    expect(route.transitionDuration, BmMotion.small);
    expect(route.reverseTransitionDuration, BmMotion.small);
    expect(route.barrierColor, isNull);

    final first = tester.widget<ScaleTransition>(_routeScale()).scale.value;
    expect(first, closeTo(0.96, 0.01));

    await tester.pump(const Duration(milliseconds: 60));
    final mid = tester.widget<ScaleTransition>(_routeScale()).scale.value;
    expect(mid, greaterThan(first));
    expect(mid, lessThan(1));

    await tester.pumpAndSettle();
    final settled = tester.widget<ScaleTransition>(_routeScale()).scale.value;
    expect(settled, closeTo(1, 1e-6));
  });

  testWidgets('下方放不下时向上翻，底缘贴锚点上方', (tester) async {
    final host = await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 500, 240, 48),
      options: options,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pumpAndSettle();
    expect(host.pushed.last, isA<BmSelectMenuRoute<String>>());

    final anchor = tester.getRect(find.byKey(_anchorKey));
    final panel = tester.getRect(find.byType(BmMenuSurface));
    expect(panel.bottom, closeTo(anchor.top - BmTokens.s1, 0.01));
    expect(panel.top, greaterThanOrEqualTo(0));

    final scale = tester.widget<ScaleTransition>(_routeScale());
    expect(scale.alignment, Alignment.bottomRight);
  });

  testWidgets('选中条目后带值返回并关闭', (tester) async {
    String? result;
    final host = await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: options,
      onResult: (value) => result = value,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(result, 'c');
    expect(_menu(), findsNothing);
    expect(host.pushed.last, isNotNull);
  });

  testWidgets('Esc 关闭浮层', (tester) async {
    await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: options,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pumpAndSettle();
    expect(_menu(), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_menu(), findsNothing);
  });

  testWidgets('点浮层外关闭，返回 null', (tester) async {
    String? result = 'sentinel';
    await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: options,
      onResult: (value) => result = value,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pumpAndSettle();
    expect(_menu(), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(_menu(), findsNothing);
  });

  testWidgets('reduce motion：没有缩放，只保留 120ms 淡入', (tester) async {
    final host = await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: options,
      reduceMotion: true,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pump();

    expect(_routeScale(), findsNothing);
    expect(
      find.ancestor(of: _menu(), matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    final route = host.pushed.last as BmSelectMenuRoute<String>;
    expect(route.reduceMotion, isTrue);
    expect(route.transitionDuration, BmMotion.small);
  });

  testWidgets('选项超过高度上限时内部滚动', (tester) async {
    final many = <BmSelectOption<String>>[
      for (var i = 0; i < 24; i++) BmSelectOption(value: '$i', label: '选项 $i'),
    ];
    await _pumpHost(
      tester,
      anchorRect: const Rect.fromLTWH(300, 200, 240, 48),
      options: many,
    );

    await tester.tap(find.byKey(_anchorKey));
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(BmMenuSurface));
    expect(panel.height, lessThanOrEqualTo(BmTokens.selectMenuMaxHeight));
    expect(
      find.descendant(
        of: find.byType(BmMenuSurface),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('BmSettingsSelectRow：点整行开浮层、选完回写、不出现 BmSheet', (tester) async {
    final host = await _pumpSettingsHost(tester, options: options);

    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget); // 行尾当前值

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();

    expect(_menu(), findsOneWidget);
    expect(find.byType(BmSheet), findsNothing);
    expect(host.pushed.last, isA<BmSelectMenuRoute<String>>());

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(find.text('深色'), findsOneWidget);
    expect(find.text('浅色'), findsNothing);
    expect(_menu(), findsNothing);
  });
}

const Key _anchorKey = Key('bm-select-anchor');

/// 泛型组件不能用 `byType`（运行时类型是 `BmSelectMenu<String>`）。
Finder _menu() => find.byWidgetPredicate((widget) => widget is BmSelectMenu);

/// 路由自己的缩放层；面板行里的 `AnimatedScale` 是它的后代，不能混进来。
Finder _routeScale() =>
    find.ancestor(of: _menu(), matching: find.byType(ScaleTransition));

class _RouteProbe extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

class _Host {
  const _Host(this.observer);

  final _RouteProbe observer;

  List<Route<dynamic>> get pushed => observer.pushed;
}

Future<_Host> _pumpHost(
  WidgetTester tester, {
  required Rect anchorRect,
  required List<BmSelectOption<String>> options,
  String selected = 'b',
  bool reduceMotion = false,
  ValueChanged<String?>? onResult,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = ThemeRegistry.defaultTheme.light();
  final observer = _RouteProbe();

  final page = Stack(
    children: [
      Positioned(
        left: anchorRect.left,
        top: anchorRect.top,
        width: anchorRect.width,
        height: anchorRect.height,
        child: SizedBox(
          key: _anchorKey,
          child: Builder(
            builder: (context) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final value = await showBmSelectMenu<String>(
                    anchorContext: context,
                    options: options,
                    selected: selected,
                    width: 220,
                  );
                  onResult?.call(value);
                },
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      navigatorObservers: [observer],
      home: Builder(
        builder: (outerContext) {
          final body = Scaffold(body: page);
          if (!reduceMotion) return body;
          return MediaQuery(
            data: MediaQuery.of(outerContext).copyWith(disableAnimations: true),
            child: body,
          );
        },
      ),
    ),
  );
  return _Host(observer);
}

/// 设置行接线：用 StatefulBuilder 模拟 Provider 回写。
Future<_Host> _pumpSettingsHost(
  WidgetTester tester, {
  required List<BmSelectOption<String>> options,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final theme = ThemeRegistry.defaultTheme.light();
  final observer = _RouteProbe();
  var selected = 'b';

  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      navigatorObservers: [observer],
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: StatefulBuilder(
              builder: (context, setState) {
                return BmSettingsGroup(
                  title: '显示',
                  children: [
                    BmSettingsSelectRow<String>(
                      title: '外观',
                      subtitle: '跟随系统 / 浅色 / 深色',
                      icon: Icons.brightness_6_outlined,
                      options: options,
                      selected: selected,
                      onChanged: (value) {
                        setState(() => selected = value);
                      },
                      menuWidth: 220,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  return _Host(observer);
}
