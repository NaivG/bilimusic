import 'package:bilimusic/shared/motion/bm_overlay_routes.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/overlay/bm_overlays.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lucent M3 浮层原语：对话框 / 底部单 / Toast。
void main() {
  group('showBmDialog', () {
    testWidgets('遮罩用 scrim，面板 0.94→1 有中间帧，settle 后到 1', (tester) async {
      final host = await _pumpHost(
        tester,
        onPressed: (context) {
          showBmDialog<void>(
            context: context,
            builder: (_) => const BmDialog(content: Text('确定要删除吗？')),
          );
        },
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      expect(find.byType(BmDialog), findsOneWidget);
      // 遮罩颜色由路由的 barrierColor 驱动；刚打开时还在淡入。
      expect(_barrier(tester).color!.a, lessThan(host.colors.scrim.a));

      // 90ms 约等于 180ms 的一半：缩放既不是 0.94 也不是 1。
      await tester.pump(const Duration(milliseconds: 90));
      final midScale = _dialogScale(tester);
      expect(midScale, greaterThan(0.94));
      expect(midScale, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(_dialogScale(tester), closeTo(1.0, 1e-6));
      expect(_barrier(tester).color, host.colors.scrim);

      final route = host.pushed.last;
      expect(route, isA<BmDialogRoute<void>>());
      final dialogRoute = route as BmDialogRoute<void>;
      expect(dialogRoute, isA<PopupRoute<void>>());
      expect(dialogRoute.transitionDuration, BmMotion.medium);
      expect(dialogRoute.reverseTransitionDuration, BmMotion.small);
    });

    testWidgets('点遮罩关闭', (tester) async {
      await _pumpHost(
        tester,
        onPressed: (context) {
          showBmDialog<void>(
            context: context,
            builder: (_) => const BmDialog(content: Text('内容')),
          );
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BmDialog), findsOneWidget);

      // 对话框居中，四角落在遮罩上。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BmDialog), findsNothing);
    });

    testWidgets('barrierDismissible: false 时点遮罩不关', (tester) async {
      await _pumpHost(
        tester,
        onPressed: (context) {
          showBmDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const BmDialog(content: Text('危险操作')),
          );
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BmDialog), findsOneWidget);
    });

    testWidgets('reduce motion：只保留淡入，路由时长 120ms', (tester) async {
      final host = await _pumpHost(
        tester,
        reduceMotion: true,
        onPressed: (context) {
          showBmDialog<void>(
            context: context,
            builder: (_) => const BmDialog(content: Text('内容')),
          );
        },
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.byType(BmDialog), findsOneWidget);
      expect(_dialogScaleTransition(), findsNothing);
      expect(
        find.ancestor(
          of: find.byType(BmDialog),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );

      final route = host.pushed.last as BmDialogRoute<void>;
      expect(route.transitionDuration, BmMotion.small);
      expect(route.reverseTransitionDuration, BmMotion.small);
    });
  });

  group('showBmSheet', () {
    testWidgets('从下方滑入、贴底；中间帧面板 top 高于静止态', (tester) async {
      final host = await _pumpHost(
        tester,
        onPressed: (context) {
          showBmSheet<void>(context: context, builder: (_) => _sheetBody());
        },
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.byType(BmSheet), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 80));
      final midTop = tester.getTopLeft(find.byType(BmSheet)).dy;

      await tester.pumpAndSettle();
      final settledTop = tester.getTopLeft(find.byType(BmSheet)).dy;
      expect(midTop, greaterThan(settledTop));

      final screenHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      // 弹簧按容差收尾，最后几帧可能还差零点几像素，给 1px 余量。
      expect(
        tester.getBottomLeft(find.byType(BmSheet)).dy,
        closeTo(screenHeight, 1),
      );

      final route = host.pushed.last;
      expect(route, isA<BmSheetRoute<void>>());
      final sheetRoute = route as BmSheetRoute<void>;
      expect(sheetRoute, isA<PopupRoute<void>>());
      expect(sheetRoute.transitionDuration, BmMotion.sheetMax);
      expect(sheetRoute.reverseTransitionDuration, BmMotion.large);
    });

    testWidgets('拖过 30% 关闭', (tester) async {
      await _pumpHost(
        tester,
        onPressed: (context) {
          showBmSheet<void>(context: context, builder: (_) => _sheetBody());
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(BmSheet), findsOneWidget);

      await tester.drag(find.byType(BmSheet), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byType(BmSheet), findsNothing);
    });

    testWidgets('拖拽不足阈值时弹回、不关闭', (tester) async {
      await _pumpHost(
        tester,
        onPressed: (context) {
          showBmSheet<void>(context: context, builder: (_) => _sheetBody());
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final settledTop = tester.getTopLeft(find.byType(BmSheet)).dy;

      await tester.drag(find.byType(BmSheet), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(find.byType(BmSheet), findsOneWidget);
      // 弹簧回到原位，不残留位移（容差按弹簧收尾误差给）。
      expect(
        tester.getTopLeft(find.byType(BmSheet)).dy,
        closeTo(settledTop, 0.5),
      );
    });

    testWidgets('isDismissible: false 时拖拽不关闭', (tester) async {
      await _pumpHost(
        tester,
        onPressed: (context) {
          showBmSheet<void>(
            context: context,
            isDismissible: false,
            builder: (_) => _sheetBody(),
          );
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final settledTop = tester.getTopLeft(find.byType(BmSheet)).dy;

      await tester.drag(find.byType(BmSheet), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byType(BmSheet), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(BmSheet)).dy,
        closeTo(settledTop, 0.5),
      );
    });

    testWidgets('reduce motion：打开即到最终位置，路由时长 120ms', (tester) async {
      final host = await _pumpHost(
        tester,
        reduceMotion: true,
        onPressed: (context) {
          showBmSheet<void>(context: context, builder: (_) => _sheetBody());
        },
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.byType(BmSheet), findsOneWidget);
      final firstTop = tester.getTopLeft(find.byType(BmSheet)).dy;

      await tester.pumpAndSettle();
      final settledTop = tester.getTopLeft(find.byType(BmSheet)).dy;
      // 没有位移过渡：首帧就贴在最终位置。
      expect(firstTop, closeTo(settledTop, 0.01));

      final route = host.pushed.last as BmSheetRoute<void>;
      expect(route.transitionDuration, BmMotion.small);
      expect(route.reverseTransitionDuration, BmMotion.small);
    });
  });

  group('showBmToast', () {
    testWidgets('success：文案可见，surface 用 floating 底 + r14 + 成功色条', (
      tester,
    ) async {
      final host = await _pumpHost(
        tester,
        onPressed: (context) {
          showBmToast(context, '已保存', status: BmToastStatus.success);
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('已保存'), findsOneWidget);

      final surface = _toastMaterial(tester);
      expect(surface.color, host.colors.floating);
      final shape = surface.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BmTokens.r14All);
      expect(shape.side.color, host.colors.hairline);
      expect(shape.side.width, 0.5);

      final bar = tester.widget<Container>(
        find.descendant(
          of: find.byType(BmToast),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxWidth == 2,
          ),
        ),
      );
      final barDecoration = bar.decoration! as BoxDecoration;
      expect(barDecoration.color, host.colors.success);
      expect(barDecoration.borderRadius, BmTokens.rPillAll);

      // 文案走 type.label 13/18。
      final message = tester.widget<Text>(find.text('已保存'));
      expect(message.style!.fontSize, 13);
      expect(message.style!.height, closeTo(19 / 13, 1e-9));

      // SnackBar 只是透明外壳：不留 padding、不带描边。
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Colors.transparent);
      expect(snackBar.padding, EdgeInsets.zero);
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect((snackBar.shape! as RoundedRectangleBorder).side, BorderSide.none);

      await _expireToast(tester);
    });

    testWidgets('error：色条用 danger', (tester) async {
      final host = await _pumpHost(
        tester,
        onPressed: (context) {
          showBmToast(context, '保存失败', status: BmToastStatus.error);
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final bar = tester.widget<Container>(
        find.descendant(
          of: find.byType(BmToast),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxWidth == 2,
          ),
        ),
      );
      expect((bar.decoration! as BoxDecoration).color, host.colors.danger);

      await _expireToast(tester);
    });

    testWidgets('neutral：没有状态色条', (tester) async {
      await _pumpHost(
        tester,
        onPressed: (context) {
          showBmToast(context, '已复制');
        },
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('已复制'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BmToast),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxWidth == 2,
          ),
        ),
        findsNothing,
      );

      await _expireToast(tester);
    });
  });
}

/// 启动一个带触发按钮的最小 App，返回主题颜色与路由探针。
///
/// reduce motion 的 MediaQuery 必须包在按钮外层：`showBmDialog` / `showBmSheet`
/// 在调用瞬间把 `reduceMotionOf(context)` 捕获进路由。包在 MaterialApp 外面无效
/// （根 View 会重新注入 MediaQuery）。
Future<_Host> _pumpHost(
  WidgetTester tester, {
  required void Function(BuildContext context) onPressed,
  bool reduceMotion = false,
}) async {
  final theme = ThemeRegistry.defaultTheme.light();
  final observer = _RouteProbe();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      navigatorObservers: [observer],
      home: Scaffold(
        body: Builder(
          builder: (outerContext) {
            final Widget page = Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => onPressed(context),
                  child: const Text('open'),
                ),
              ),
            );
            if (!reduceMotion) return page;
            return MediaQuery(
              data: MediaQuery.of(outerContext)
                  .copyWith(disableAnimations: true),
              child: page,
            );
          },
        ),
      ),
    ),
  );
  return _Host(theme.extension<BmColors>()!, observer);
}

class _Host {
  const _Host(this.colors, this.observer);

  final BmColors colors;
  final _RouteProbe observer;

  List<Route<dynamic>> get pushed => observer.pushed;
}

class _RouteProbe extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Widget _sheetBody() {
  return const BmSheet(
    child: SizedBox(height: 120, child: Center(child: Text('Sheet 内容'))),
  );
}

/// 路由遮罩：基础页的 `ModalBarrier` 没有颜色，取带 barrierColor 的那个。
ModalBarrier _barrier(WidgetTester tester) {
  return tester.widget<ModalBarrier>(
    find.byWidgetPredicate((w) => w is ModalBarrier && w.color != null),
  );
}

Finder _dialogScaleTransition() {
  return find.ancestor(
    of: find.byType(BmDialog),
    matching: find.byType(ScaleTransition),
  );
}

double _dialogScale(WidgetTester tester) {
  return tester.widget<ScaleTransition>(_dialogScaleTransition()).scale.value;
}

Material _toastMaterial(WidgetTester tester) {
  return tester.widget<Material>(
    find
        .descendant(of: find.byType(BmToast), matching: find.byType(Material))
        .first,
  );
}

/// 把 3 秒的 toast 停留时间走完，避免测试结束时留下待触发的计时器。
Future<void> _expireToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}
