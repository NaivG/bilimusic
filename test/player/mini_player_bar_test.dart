import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/widgets/mini_player_bar.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/chrome/bm_chrome.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

const _previousIcon = Icons.skip_previous_rounded;
const _nextIcon = Icons.skip_next_rounded;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 封面走 cached_network_image，给它一个可写目录，别让缓存器去要真实插件。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  testWidgets('右滑：上一首提示出现在浮块左侧的空白里', (tester) async {
    await _pumpBar(tester);
    final gesture = await _dragAndHold(tester, 60);

    final icon = find.byIcon(_previousIcon);
    expect(icon, findsOneWidget, reason: '右滑超过阈值必须显示上一首提示');

    final pill = tester.getRect(find.byType(BmChromeSurface));
    expect(
      tester.getRect(icon).right,
      lessThanOrEqualTo(pill.left),
      reason: '提示画在浮块让出来的左侧空白里，不能压在内容上',
    );

    await gesture.cancel();
  });

  testWidgets('左滑：下一首提示出现在浮块右侧的空白里', (tester) async {
    await _pumpBar(tester);
    final gesture = await _dragAndHold(tester, -60);

    final icon = find.byIcon(_nextIcon);
    expect(icon, findsOneWidget, reason: '左滑超过阈值必须显示下一首提示');

    final pill = tester.getRect(find.byType(BmChromeSurface));
    expect(
      tester.getRect(icon).left,
      greaterThanOrEqualTo(pill.right),
      reason: '提示画在浮块让出来的右侧空白里，不能压在内容上',
    );

    await gesture.cancel();
  });

  testWidgets('提示图标不能被浮块的圆角裁剪吞掉', (tester) async {
    await _pumpBar(tester);
    final gesture = await _dragAndHold(tester, 60);

    // 图标画在浮块之外：一旦被包进 ClipRRect（BmChromeSurface 的内容层）或
    // 带裁剪的 Stack，画面上就整条消失——这正是它「不渲染」时的样子。
    expect(
      _clippingAncestors(tester, find.byIcon(_previousIcon)),
      isEmpty,
      reason: '上一首提示和浮块之间不能有裁剪层',
    );

    await gesture.cancel();
  });

  testWidgets('提示图标随拖动距离逐渐放大', (tester) async {
    await _pumpBar(tester);
    final gesture = await _dragAndHold(tester, 60);
    final icon = find.byIcon(_previousIcon);
    final near = tester.getRect(icon).height;

    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    final far = tester.getRect(icon).height;

    expect(far, greaterThan(near), reason: '拖得越远，提示图标放得越大');

    await gesture.cancel();
  });

  testWidgets('没有当前曲目时不显示提示图标', (tester) async {
    await _pumpBar(tester, withMusic: false);
    final gesture = await _dragAndHold(tester, 60);

    expect(find.byIcon(_previousIcon), findsNothing);
    expect(find.byIcon(_nextIcon), findsNothing);

    await gesture.cancel();
  });
}

/// 从 [finder] 到 [MiniPlayerBar] 之间的裁剪层（会裁掉越界绘制的那几类）。
List<Widget> _clippingAncestors(WidgetTester tester, Finder finder) {
  final clips = <Widget>[];
  tester.element(finder).visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is ClipRect || widget is ClipRRect || widget is ClipPath) {
      clips.add(widget);
    } else if (widget is Stack && widget.clipBehavior != Clip.none) {
      clips.add(widget);
    }
    return widget is! MiniPlayerBar;
  });
  return clips;
}

/// 起一个只挂迷你播放器的最小页面。
Future<void> _pumpBar(WidgetTester tester, {bool withMusic = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dualAudioServiceProvider.overrideWithValue(_FakeDualAudioService()),
        currentMusicProvider.overrideWithValue(withMusic ? _music : null),
      ],
      child: MaterialApp(
        theme: ThemeRegistry.defaultTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(BmTokens.miniPlayerInset),
            child: MiniPlayerBar(onExpand: () {}, onPlayList: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// 从浮块中心按下并水平拖动 [dx]（分两次送事件，确保越过手势 slop）。
Future<TestGesture> _dragAndHold(WidgetTester tester, double dx) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(MiniPlayerBar)),
  );
  await gesture.moveBy(Offset(dx / 2, 0));
  await gesture.moveBy(Offset(dx / 2, 0));
  await tester.pump();
  return gesture;
}

/// 只提供状态通知器的最小双播放器：不碰 libmpv。
class _FakeDualAudioService extends DualAudioService {}

final _music = Music(
  id: 'BV1',
  cid: 'cid-1',
  title: 'track',
  artist: const Artist(name: 'artist'),
  album: 'album',
  coverUrl: '',
  audioUrl: '',
  duration: const Duration(minutes: 3),
);
