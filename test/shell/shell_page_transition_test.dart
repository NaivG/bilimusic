import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/app/shells/landscape/landscape_content_stage.dart';
import 'package:bilimusic/app/shells/shell_widgets.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/shared/motion/bm_page_switcher.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 竖屏壳页面区「同一槽位必须保持 element 身份」的回归测试。
void main() {
  test('有效默认值：alwaysShowMiniPlayer 为 false（SettingsState 的 true 只是兜底）', () {
    // SettingsState 构造参数默认 true（settings_provider.dart:52），但真实
    // 状态来自 SettingsManager（settings_provider.dart:132），其后端默认
    // 值是 false（settings_manager.dart:62、259-260）。
    expect(SettingsManager.DEFAULT_ALWAYS_SHOW_MINI_PLAYER, isFalse);
  });

  testWidgets('槽位类型稳定（chromeInset 恒 >0）：push 正常播过渡', (tester) async {
    final harness = await _pumpSlot(tester, bottom: 158);

    harness.changePage('b', bottom: 158);
    await tester.pump();

    // t=0：旧页仍在树上，新页自右侧整幅滑入。
    expect(
      find.byKey(const ValueKey('probe-a')),
      findsOneWidget,
      reason: '过渡期间旧页必须仍在树上',
    );
    expect(_translation(tester, 'b'), const Offset(1, 0));

    await tester.pump(const Duration(milliseconds: 100));
    expect(_translation(tester, 'b').dx, inExclusiveRange(0, 1));
    expect(_translation(tester, 'a').dx, lessThan(0));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('probe-a')), findsNothing);
    expect(_translation(tester, 'b'), Offset.zero);
  });

  testWidgets('槽位类型稳定（chromeInset 恒为 0）：push 同样正常播过渡', (tester) async {
    final harness = await _pumpSlot(tester, bottom: 0);

    harness.changePage('b', bottom: 0);
    await tester.pump();

    expect(find.byKey(const ValueKey('probe-a')), findsOneWidget);
    expect(_translation(tester, 'b'), const Offset(1, 0));

    await tester.pump(const Duration(milliseconds: 100));
    expect(_translation(tester, 'b').dx, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('probe-a')), findsNothing);
  });

  testWidgets('横屏内容区槽位类型稳定（LandscapeContentStage）：换页正常播过渡', (tester) async {
    // 横屏壳把 `shellPageSwitcher` 放在 LandscapeContentStage 的
    // `Positioned.fill` 里（landscape_content_stage.dart:44），没有竖屏那种
    // 条件 MediaQuery 包装，所以过渡不受影响。
    final key = GlobalKey<_LandscapeHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeRegistry.defaultTheme.light(),
        home: Scaffold(body: _LandscapeHarness(key: key)),
      ),
    );
    await tester.pumpAndSettle();

    key.currentState!.changePage('b');
    await tester.pump();

    expect(find.byKey(const ValueKey('probe-a')), findsOneWidget);
    expect(_translation(tester, 'b'), const Offset(1, 0));

    await tester.pump(const Duration(milliseconds: 100));
    expect(_translation(tester, 'b').dx, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('probe-a')), findsNothing);
  });

  testWidgets('回归：chromeInset 158 → 0 换页，过渡照常播、旧页在过渡中仍在树', (tester) async {
    // 真实场景：默认 alwaysShowMiniPlayer=false 时，从 4 个主页面
    // （bottom = portraitBottomBudget）进入任何二级页面（bottom = 0）。
    final harness = await _pumpSlot(tester, bottom: 158);

    harness.changePage('b', bottom: 0);
    await tester.pump();

    // 槽位类型恒定（始终有 MediaQuery）：切换器状态存活，过渡正常启动。
    expect(find.byKey(const ValueKey('probe-a')), findsOneWidget);
    expect(_translation(tester, 'b'), const Offset(1, 0));

    await tester.pump(const Duration(milliseconds: 100));
    expect(_translation(tester, 'b').dx, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('probe-a')), findsNothing);
    expect(_translation(tester, 'b'), Offset.zero);
  });

  testWidgets('回归：chromeInset 0 → 158 换页，同样正常播过渡', (tester) async {
    // 真实场景：从二级页面返回 4 个主页面之一。
    final harness = await _pumpSlot(tester, bottom: 0);

    harness.changePage('b', bottom: 158);
    await tester.pump();

    expect(find.byKey(const ValueKey('probe-a')), findsOneWidget);
    expect(_translation(tester, 'b'), const Offset(1, 0));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('probe-a')), findsNothing);
  });

  testWidgets('回归：同一 pageKey 下 chromeInset 158 → 0，页面状态保留', (tester) async {
    // 真实场景：从主页面进入详情页。basePageKey 不变（detail 被 baseEntry
    // 跳过），但 currentPage == detail 让 chromeInset 变 0；底层页面不能被
    // 重建，否则滚动位置、列表状态全部丢失。
    final harness = await _pumpSlot(tester, bottom: 158);
    final before = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('page-state-a')),
    );

    harness.changeInset(0);
    await tester.pump();

    final after = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('page-state-a')),
    );
    expect(after.instanceId, before.instanceId);
    expect(before.mounted, isTrue);
  });

  testWidgets('对照：同一 pageKey 下 chromeInset 158 → 94（都 >0），页面状态保留', (
    tester,
  ) async {
    // 真实场景：alwaysShowMiniPlayer=true 时主页面 ↔ 二级页面，
    // 两种 inset 都 >0，槽位类型不变，不丢状态。
    final harness = await _pumpSlot(tester, bottom: 158);
    final before = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('page-state-a')),
    );

    harness.changeInset(94);
    await tester.pump();

    final after = tester.state<_ProbePageState>(
      find.byKey(const ValueKey('page-state-a')),
    );
    expect(after.instanceId, before.instanceId);
  });
}

/// 页面区槽位：复刻 `portrait_shell.dart` 中
/// `NotificationListener > shellPageSwitcher > applyShellChromeInset` 这一段。
class _SlotHarness extends StatefulWidget {
  const _SlotHarness({super.key, required this.bottom});

  final double bottom;

  @override
  State<_SlotHarness> createState() => _SlotHarnessState();
}

class _SlotHarnessState extends State<_SlotHarness> {
  late double _bottom = widget.bottom;
  Key _pageKey = const ValueKey('a');
  BmPageTransitionKind _kind = BmPageTransitionKind.push;
  int _direction = 1;

  void changePage(
    String name, {
    required double bottom,
    BmPageTransitionKind kind = BmPageTransitionKind.push,
  }) {
    setState(() {
      _pageKey = ValueKey(name);
      _bottom = bottom;
      _kind = kind;
      _direction = 1;
    });
  }

  void changeInset(double bottom) => setState(() => _bottom = bottom);

  @override
  Widget build(BuildContext context) {
    final name = (_pageKey as ValueKey<String>).value;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        NotificationListener<ScrollNotification>(
          onNotification: (_) => false,
          child: shellPageSwitcher(
            key: _pageKey,
            kind: _kind,
            direction: _direction,
            child: applyShellChromeInset(
              context,
              bottom: _bottom,
              child: _ProbePage(key: ValueKey('page-state-$name'), name: name),
            ),
          ),
        ),
      ],
    );
  }
}

/// 横屏内容区槽位：`LandscapeContentStage` + `shellPageSwitcher`。
class _LandscapeHarness extends StatefulWidget {
  const _LandscapeHarness({super.key});

  @override
  State<_LandscapeHarness> createState() => _LandscapeHarnessState();
}

class _LandscapeHarnessState extends State<_LandscapeHarness> {
  Key _pageKey = const ValueKey('a');

  void changePage(String name) => setState(() => _pageKey = ValueKey(name));

  @override
  Widget build(BuildContext context) {
    final name = (_pageKey as ValueKey<String>).value;
    return LandscapeContentStage(
      libraryOpen: false,
      queueOpen: false,
      onCloseDrawers: () {},
      page: shellPageSwitcher(
        key: _pageKey,
        kind: BmPageTransitionKind.push,
        direction: 1,
        child: _ProbePage(key: ValueKey('page-state-$name'), name: name),
      ),
      libraryDrawer: const SizedBox.shrink(),
      queuePanel: const SizedBox.shrink(),
    );
  }
}

/// 带实例号的探针页面：`instanceId` 变化即证明 State 被销毁重建。
class _ProbePage extends StatefulWidget {
  const _ProbePage({required this.name, super.key});

  final String name;

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  static int _created = 0;

  late final int instanceId = ++_created;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: ValueKey('probe-${widget.name}'),
      child: ColoredBox(color: Theme.of(context).colorScheme.surface),
    );
  }
}

Future<_SlotHarnessState> _pumpSlot(
  WidgetTester tester, {
  required double bottom,
}) async {
  final key = GlobalKey<_SlotHarnessState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeRegistry.defaultTheme.light(),
      home: Scaffold(
        body: _SlotHarness(key: key, bottom: bottom),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Finder _page(String name) => find.byKey(ValueKey('probe-$name'));

Offset _translation(WidgetTester tester, String name) => tester
    .widget<FractionalTranslation>(
      find
          .ancestor(
            of: _page(name),
            matching: find.byType(FractionalTranslation),
          )
          .first,
    )
    .translation;
