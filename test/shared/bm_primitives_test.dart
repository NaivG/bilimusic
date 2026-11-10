import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/chrome/bm_dock.dart';
import 'package:bilimusic/shared/ui/controls/bm_switch.dart';
import 'package:bilimusic/shared/ui/sections/bm_section_header.dart';
import 'package:bilimusic/shared/ui/settings/bm_settings_group.dart';
import 'package:bilimusic/shared/ui/surfaces/bm_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Theater 原语：浮动 Dock / 开关 / 分区标题 / 设置组 / 白卡。
void main() {
  final theme = ThemeRegistry.defaultTheme.light();
  final colors = theme.extension<BmColors>()!;

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BmDock', () {
    const items = <BmDockItem>[
      BmDockItem(icon: Icons.home_outlined, label: '首页'),
      BmDockItem(icon: Icons.explore_outlined, label: '发现'),
      BmDockItem(icon: Icons.person_outline_rounded, label: '我的'),
      BmDockItem(icon: Icons.settings_outlined, label: '设置'),
    ];
    const dockWidth = 360.0;
    final slot = dockWidth / items.length;

    Future<void> pumpDock(
      WidgetTester tester, {
      int selectedIndex = 0,
      bool reduceMotion = false,
      ValueChanged<int>? onSelected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: BmMotionScope(
                reduceMotion: reduceMotion,
                child: SizedBox(
                  width: dockWidth,
                  child: BmDock(
                    items: items,
                    selectedIndex: selectedIndex,
                    onSelected: onSelected ?? (_) {},
                    blur: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder lens() => find.byKey(BmDock.lensKey);

    Color lensColor(WidgetTester tester) {
      final container = tester.widget<AnimatedContainer>(lens());
      return (container.decoration! as BoxDecoration).color!;
    }

    double lensCenterX(WidgetTester tester) => tester.getCenter(lens()).dx;

    double slotCenterX(WidgetTester tester, int index) =>
        tester.getTopLeft(find.byType(BmDock)).dx + slot * (index + 0.5);

    int argb(Color color) => color.toARGB32();

    testWidgets('60 高、30 圆角胶囊、项高 46、胶囊 88 × 56', (tester) async {
      await pumpDock(tester);

      expect(tester.getSize(find.byType(BmDock)).height, BmTokens.dockHeight);
      expect(
        BmTokens.dockRadius,
        BorderRadius.circular(BmTokens.dockHeight / 2),
      );
      expect(BmTokens.dockItemHeight, 46);
      expect(
        tester.getSize(lens()),
        const Size(BmTokens.dockItemWidth, BmTokens.dockItemHeightActive),
      );
    });

    testWidgets('选中项 accentDeep 图标 + accentSoftStrong 胶囊，居中于该项', (
      tester,
    ) async {
      await pumpDock(tester);

      expect(
        argb(tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color!),
        argb(colors.accentDeep),
      );
      expect(
        argb(tester.widget<Icon>(find.byIcon(Icons.explore_outlined)).color!),
        argb(colors.textSecondary),
      );
      expect(argb(lensColor(tester)), argb(colors.accentSoftStrong));
      expect(lensCenterX(tester), closeTo(slotCenterX(tester, 0), 0.5));
    });

    testWidgets('悬停隔壁项：胶囊滑过去、预览色变淡，移出滑回选中项', (tester) async {
      await pumpDock(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.text('发现')));
      await tester.pumpAndSettle();

      expect(lensCenterX(tester), closeTo(slotCenterX(tester, 1), 0.5));
      expect(argb(lensColor(tester)), argb(colors.accentSoft));
      expect(
        argb(tester.widget<Icon>(find.byIcon(Icons.explore_outlined)).color!),
        argb(colors.textPrimary),
      );
      // 选中项没有变，只是胶囊在预览。
      expect(
        argb(tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color!),
        argb(colors.accentDeep),
      );

      await mouse.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();

      expect(lensCenterX(tester), closeTo(slotCenterX(tester, 0), 0.5));
      expect(argb(lensColor(tester)), argb(colors.accentSoftStrong));
      expect(
        argb(tester.widget<Icon>(find.byIcon(Icons.explore_outlined)).color!),
        argb(colors.textSecondary),
      );
    });

    testWidgets('悬停时胶囊朝指针方向前倾 20%', (tester) async {
      await pumpDock(tester);
      final dockTopLeft = tester.getTopLeft(find.byType(BmDock));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // 第 2 项右侧 1/4 项宽：项内偏移 0.25，倾斜后目标偏移 0.05 项。
      await mouse.moveTo(
        Offset(dockTopLeft.dx + slot * 1.75, dockTopLeft.dy + 30),
      );
      await tester.pumpAndSettle();

      expect(
        lensCenterX(tester),
        closeTo(slotCenterX(tester, 1) + slot * 0.05, 0.6),
      );
    });

    testWidgets('切换选中项时胶囊横移过去', (tester) async {
      await pumpDock(tester);
      expect(lensCenterX(tester), closeTo(slotCenterX(tester, 0), 0.5));

      await pumpDock(tester, selectedIndex: 2);
      expect(lensCenterX(tester), closeTo(slotCenterX(tester, 2), 0.5));
    });

    testWidgets('reduce motion 下悬停直接到位', (tester) async {
      await pumpDock(tester, reduceMotion: true);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.text('设置')));
      await tester.pump();

      expect(lensCenterX(tester), closeTo(slotCenterX(tester, 3), 0.5));
    });

    testWidgets('点击回调带下标', (tester) async {
      int? tapped;
      await pumpDock(tester, onSelected: (index) => tapped = index);

      await tester.tap(find.byIcon(Icons.explore_outlined));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });
  });

  group('BmSwitch', () {
    testWidgets('52 × 32，thumb 28，开启走 accent', (tester) async {
      await pump(tester, BmSwitch(value: true, onChanged: (_) {}));
      expect(tester.getSize(find.byType(BmSwitch)), const Size(52, 32));

      final track = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(BmSwitch),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect((track.decoration! as BoxDecoration).color, colors.accent);
    });

    testWidgets('关闭走 lineStrong；点击回调取反', (tester) async {
      bool? next;
      await pump(tester, BmSwitch(value: false, onChanged: (v) => next = v));

      final track = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(BmSwitch),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect((track.decoration! as BoxDecoration).color, colors.lineStrong);

      await tester.tap(find.byType(BmSwitch));
      expect(next, isTrue);
    });

    testWidgets('语义带 toggled', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, BmSwitch(value: true, onChanged: (_) {}));
      expect(
        tester.getSemantics(find.byType(BmSwitch)),
        containsSemantics(isToggled: true),
      );
      handle.dispose();
    });
  });

  group('BmSectionHeader', () {
    testWidgets('标题走 section 21/27 w700；有 onMore 时出现「查看全部」', (tester) async {
      await pump(tester, const BmSectionHeader(title: '为你推荐', onMore: _noop));

      final style = tester.widget<Text>(find.text('为你推荐')).style!;
      expect(style.fontSize, 21);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.height, closeTo(27 / 21, 1e-9));
      expect(find.text('查看全部'), findsOneWidget);
    });

    testWidgets('无 onMore / trailing 时右侧不渲染', (tester) async {
      await pump(tester, const BmSectionHeader(title: '歌单'));
      expect(find.text('查看全部'), findsNothing);
    });
  });

  group('BmSettingsGroup', () {
    testWidgets('组标题 + 白卡 + 行高 56 + 32 底座', (tester) async {
      await pump(
        tester,
        SizedBox(
          width: 360,
          child: BmSettingsGroup(
            title: '通知',
            children: [
              BmSettingsSwitchRow(
                title: '推送媒体通知',
                icon: Icons.notifications_none,
                value: true,
                onChanged: _noopBool,
              ),
              BmSettingsValueRow(
                title: '通知权限',
                icon: Icons.shield_outlined,
                value: '已允许',
              ),
            ],
          ),
        ),
      );

      expect(find.text('通知'), findsOneWidget);
      expect(find.byType(BmCard), findsOneWidget);
      expect(find.byType(BmSwitch), findsOneWidget);
      expect(find.text('已允许'), findsOneWidget);

      final row = tester.getSize(
        find
            .ancestor(
              of: find.text('推送媒体通知'),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(row.height, BmTokens.settingRow);
    });
  });

  group('BmCard', () {
    testWidgets('默认白底 + hairline 描边 + 14 圆角', (tester) async {
      await pump(
        tester,
        const BmCard(padding: EdgeInsets.all(BmTokens.s4), child: Text('内容')),
      );

      final decoration =
          tester
                  .widgetList<DecoratedBox>(
                    find.descendant(
                      of: find.byType(BmCard),
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .first
                  .decoration
              as BoxDecoration;
      expect(decoration.color, colors.surfaceRaised);
      expect(decoration.borderRadius, BmTokens.r14All);
      expect(decoration.border, isNotNull);
    });
  });
}

void _noop() {}
void _noopBool(bool _) {}
