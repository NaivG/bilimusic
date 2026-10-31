import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_context_menu/super_context_menu.dart';

import 'package:bilimusic/features/discover/widgets/discover_music_tile.dart';

/// 封面缓存要写盘，测试里把 path_provider 指到临时目录。
void _stubPathProvider() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async =>
        Directory.systemTemp.createTempSync('bilimusic_tile_test').path,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    ),
  );
}

Widget _buildTile({bool enabled = true, MenuProvider? contextMenuBuilder}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: DiscoverMusicTile(
            title: '测试曲目',
            subtitle: '测试歌手',
            coverUrl: '',
            cacheKey: 'tile-test',
            enabled: enabled,
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
      ),
    ),
  );
}

Menu _testMenu() => Menu(
  children: [MenuAction(title: '菜单测试项', callback: () {})],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('右键触发菜单构建器并弹出菜单', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    _stubPathProvider();

    var menuRequested = false;
    await tester.pumpWidget(
      _buildTile(
        contextMenuBuilder: (_) {
          menuRequested = true;
          return _testMenu();
        },
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DiscoverMusicTile)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(menuRequested, isTrue);
    // 菜单由 super_context_menu 默认构建器绘制，从菜单项元素确认浮层已铺开。
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_MenuItemWidget',
      ),
      findsWidgets,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('未提供构建器或行被禁用时不接管右键', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    _stubPathProvider();

    await tester.pumpWidget(_buildTile());
    await tester.pumpAndSettle();
    expect(find.byType(ContextMenuWidget), findsNothing);

    var menuRequested = false;
    await tester.pumpWidget(
      _buildTile(
        enabled: false,
        contextMenuBuilder: (_) {
          menuRequested = true;
          return _testMenu();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ContextMenuWidget), findsNothing);
    expect(menuRequested, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });
}
