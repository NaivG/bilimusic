import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/menu/app_context_menu.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:super_context_menu/super_context_menu.dart';

/// [AppContextMenu]：桌面右键落到 Lucent 菜单行并执行菜单项。
///
/// 触屏长按走 `super_context_menu` 的原生菜单通道（`MenuContext`），
/// widget test 里没有平台实现，只能在真机验证。
void main() {
  testWidgets('桌面右键弹出 Lucent 菜单并能执行菜单项', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    var selected = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeRegistry.defaultTheme.light(),
        home: Scaffold(
          body: Center(
            child: AppContextMenu(
              menuProvider: (_) => Menu(
                children: [
                  MenuAction(title: '收藏', callback: () => selected = true),
                ],
              ),
              child: const SizedBox(
                width: 160,
                height: 48,
                child: Center(child: Text('曲目行')),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('曲目行')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(BmMenuRow), findsOneWidget);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);

    debugDefaultTargetPlatformOverride = null;
  });
}
