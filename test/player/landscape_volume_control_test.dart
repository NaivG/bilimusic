import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/widgets/landscape_volume_control.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';

/// 不建真实 libmpv 播放器的双播放器服务：本控件只读 `volume`、只调静音切换。
class _StubDualAudioService extends DualAudioService {
  final ValueNotifier<double> _volume = ValueNotifier(0.5);

  @override
  ValueListenable<double> get volume => _volume;

  @override
  Future<void> setVolume(double value) async {
    _volume.value = value.clamp(0.0, 1.0);
  }

  @override
  Future<void> toggleMute() async {
    _volume.value = _volume.value > 0 ? 0 : 0.5;
  }

  @override
  void initialize() {}

  @override
  Future<void> dispose() async {}
}

/// 横屏底栏音量控件：悬停或触屏点按弹出竖向音量条，鼠标点击喇叭仍是静音切换。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubDualAudioService audio;

  Future<void> pumpControl(WidgetTester tester) async {
    audio = _StubDualAudioService();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dualAudioServiceProvider.overrideWithValue(audio)],
        child: MaterialApp(
          theme: ThemeRegistry.defaultTheme.light(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.only(right: 24, bottom: 16),
                child: LandscapeVolumeControl(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 鼠标移到喇叭图标上并等浮层展开。
  Future<TestGesture> hoverTrigger(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(BmIconButton)));
    await tester.pump(BmMotion.micro);
    await tester.pumpAndSettle();
    return mouse;
  }

  testWidgets('悬停喇叭弹出竖向音量条，移开后收起', (tester) async {
    await pumpControl(tester);
    expect(find.byType(Slider), findsNothing, reason: '默认不占底栏位置');

    final mouse = await hoverTrigger(tester);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('50%'), findsOneWidget, reason: '浮层显示当前音量');

    final sliderRect = tester.getRect(find.byType(Slider));
    expect(
      sliderRect.height,
      greaterThan(sliderRect.width),
      reason: '音量条要竖过来（0 在底部、向上增大）',
    );

    final iconRect = tester.getRect(find.byType(BmIconButton));
    final panelRect = tester.getRect(find.byType(BmMenuSurface));
    expect(
      panelRect.bottom,
      lessThanOrEqualTo(iconRect.top),
      reason: '浮层弹在图标上方，不盖住喇叭',
    );

    // 指针移进浮层：不能中途收起。
    await mouse.moveTo(sliderRect.center);
    await tester.pump(BmMotion.large);
    expect(find.byType(Slider), findsOneWidget);

    // 指针离开图标与浮层：收起。
    await mouse.moveTo(const Offset(40, 40));
    await tester.pump(BmMotion.large);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('鼠标点击喇叭仍是静音切换，浮层音量跟着变', (tester) async {
    await pumpControl(tester);
    await hoverTrigger(tester);

    await tester.tap(find.byType(BmIconButton), kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(audio.volume.value, 0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('拖动音量条向上增大音量，拖动期间移出浮层不收起', (tester) async {
    await pumpControl(tester);
    final mouse = await hoverTrigger(tester);
    final sliderCenter = tester.getCenter(find.byType(Slider));

    final drag = await tester.startGesture(sliderCenter);
    await tester.pump();
    // 拖动途中把指针甩到浮层外：浮层必须留着。
    await drag.moveTo(const Offset(40, 40));
    await tester.pump(BmMotion.large);
    expect(find.byType(Slider), findsOneWidget, reason: '拖动中不能被收起');

    await drag.up();
    await tester.pump();

    expect(audio.volume.value, greaterThan(0.5), reason: '从中心向上拖是调大音量');

    // 松手后指针不在浮层上，延迟收起。
    await mouse.moveTo(const Offset(40, 40));
    await tester.pump(BmMotion.large);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('触屏点按喇叭只展开音量条不静音，点浮层外收起', (tester) async {
    await pumpControl(tester);
    expect(find.byType(Slider), findsNothing);

    // tester.tap 默认就是 touch：没有 hover 也必须能展开浮层。
    await tester.tap(find.byType(BmIconButton));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(audio.volume.value, 0.5, reason: '触屏点按只负责展开，不切静音');

    await tester.tapAt(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(audio.volume.value, 0.5);
  });

  testWidgets('触屏点按展开后再点喇叭，遮罩先收起浮层', (tester) async {
    await pumpControl(tester);
    await tester.tap(find.byType(BmIconButton));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);

    // 浮层展开时全屏遮罩盖在图标上：再点喇叭只收起，不再改音量。
    await tester.tapAt(tester.getCenter(find.byType(BmIconButton)));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing);
    expect(audio.volume.value, 0.5, reason: '两次触屏点按都不静音');
  });

  testWidgets('触屏点按展开后可直接拖动音量条', (tester) async {
    await pumpControl(tester);
    await tester.tap(find.byType(BmIconButton));
    await tester.pumpAndSettle();

    final drag = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await drag.moveBy(const Offset(0, -40));
    await drag.up();
    await tester.pump();

    expect(audio.volume.value, greaterThan(0.5), reason: '遮罩不能挡住滑杆拖动');
  });
}
