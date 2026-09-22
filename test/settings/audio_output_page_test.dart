import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/features/settings/ui/audio_output_page.dart';

/// 不建真实播放器的双播放器服务。
///
/// `DualAudioService.initialize()` 会 new 两个 `mpv.Player`，那要加载
/// 本机 libmpv，widget 测试环境里跑不了；而页面只消费它两个**字段
/// 初始化时就已就绪**的 ValueNotifier（`audioDevices` / `audioDevice`），
/// 把 `initialize` / `dispose` 抹掉即可——`_initialized` 保持 false 时
/// `_broadcast` 自己会早退。
class _StubDualAudioService extends DualAudioService {
  @override
  void initialize() {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// `SettingsManager` 是进程级单例，`_cache` 会跨用例残留；
  /// 每个用例先重置 prefs 再 await init()，把已知键整份覆盖掉。
  Future<SettingsManager> loadSettings({
    Map<String, Object> values = const {},
  }) async {
    SharedPreferences.setMockInitialValues(values);
    final mgr = SettingsManager();
    await mgr.init();
    return mgr;
  }

  /// 预置可用设备清单，避免下拉停在「设备列表尚未就绪」那一态。
  Widget wrap(Widget child, {List<mpv.Device> devices = const []}) {
    final audio = _StubDualAudioService();
    audio.audioDevices.value = devices;
    return ProviderScope(
      overrides: [dualAudioServiceProvider.overrideWithValue(audio)],
      child: MaterialApp(home: child),
    );
  }

  group('免责协议闸门', () {
    testWidgets('首次进入弹三行说明，四项设置同时在树里', (tester) async {
      final mgr = await loadSettings();
      expect(mgr.audioOutputDisclaimerAccepted, isFalse);

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('1. 硬件直通（独占模式）会锁死输出设备，期间其他应用将没有声音。'), findsOneWidget);
      expect(
        find.text('2. 强制采样率、切换设备可能与硬件不兼容，出现无声、爆音，或需要重启应用。'),
        findsOneWidget,
      );
      expect(find.text('3. 以上均为高级音频选项，因配置导致的问题请自行承担。'), findsOneWidget);

      // 弹窗是模态的，底下的设置并没有「先渲染一半再等同意」。
      for (final title in const ['音频延迟', '硬件直通（独占模式）', '强制 DAC 采样率', '输出设备']) {
        expect(find.text(title), findsOneWidget, reason: '缺少设置项「$title」');
      }
    });

    testWidgets('点同意：写入设置、留在本页', (tester) async {
      final mgr = await loadSettings();

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('同意并继续'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(mgr.audioOutputDisclaimerAccepted, isTrue);
      expect(find.text('音频延迟'), findsOneWidget);
      // 协议是「看过风险」的标记，同意一次就不再打扰。
      expect(find.text('同意并继续'), findsNothing);
    });

    testWidgets('点不同意：提示 + 退回设置页，设置位保持未同意', (tester) async {
      final mgr = await loadSettings();

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('不同意'));
      await tester.pumpAndSettle();

      // 外壳导航是 ShellPageManager 的自定义栈（测试里只有 home 一帧，
      // pop 是 no-op），这里能断言的是提示确实发出去了。
      expect(find.text('需先同意免责说明，才能调整音频输出'), findsOneWidget);
      expect(mgr.audioOutputDisclaimerAccepted, isFalse);
    });

    testWidgets('已同意过：进页不再弹', (tester) async {
      await loadSettings(values: {'audio_output_disclaimer_accepted': true});

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('音频延迟'), findsOneWidget);
    });

    testWidgets('拒绝之后再进：重新弹（闸门没被半途置位）', (tester) async {
      final mgr = await loadSettings();

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不同意'));
      await tester.pumpAndSettle();
      expect(mgr.audioOutputDisclaimerAccepted, isFalse);

      // 外壳用 `ValueKey(页面名)` 区分帧（shell_page_manager.dart 的
      // basePageKey），换页时上一帧整棵卸载、新帧重新 initState——
      // 直接把同一个 AudioOutputPage 再 pump 一次会复用 State，
      // initState 不跑，测的就不是真实路径了。这里先塞一个占位页
      // 模拟「离开音频输出页」。
      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('页面形态', () {
    testWidgets('不折叠：没有 ExpansionTile / 展开箭头，四项平铺', (tester) async {
      await loadSettings(values: {'audio_output_disclaimer_accepted': true});

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ExpansionTile), findsNothing);
      // 对照 DSP 页：那边是 9 个「开关长在折叠头上」的模块，本页只有一个
      // 独占模式开关——开关数量对得上，就说明没有偷偷长出折叠结构。
      expect(find.byType(Switch), findsNWidgets(1));
      expect(find.byType(Slider), findsNWidgets(1));

      for (final title in const ['音频延迟', '硬件直通（独占模式）', '强制 DAC 采样率', '输出设备']) {
        expect(find.text(title), findsOneWidget, reason: '缺少设置项「$title」');
      }
      expect(find.text('恢复默认'), findsOneWidget);
    });

    testWidgets('设备清单没就绪时下拉禁用，并把原因写出来', (tester) async {
      await loadSettings(values: {'audio_output_disclaimer_accepted': true});

      await tester.pumpWidget(wrap(const AudioOutputPage()));
      await tester.pumpAndSettle();

      expect(find.text('设备列表尚未就绪——mpv 初始化完成后自动填充。'), findsOneWidget);
      final deviceDropdown = tester.widget<DropdownButton<String>>(
        find.byWidgetPredicate(
          (w) => w is DropdownButton && w.value is String?,
        ),
      );
      expect(deviceDropdown.onChanged, isNull, reason: '空清单不该给出可点开的下拉');
    });

    testWidgets('设备清单就绪后可选，并渲染设备描述', (tester) async {
      await loadSettings(values: {'audio_output_disclaimer_accepted': true});

      await tester.pumpWidget(
        wrap(
          const AudioOutputPage(),
          devices: const [
            mpv.Device(name: 'wasapi/{hp}', description: 'USB 耳机'),
            mpv.Device(name: 'wasapi/{sp}', description: '扬声器'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('设备列表尚未就绪——mpv 初始化完成后自动填充。'), findsNothing);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byWidgetPredicate(
          (w) => w is DropdownButton && w.value is String?,
        ),
      );
      expect(dropdown.onChanged, isNotNull);
      // 0 号是「自动（系统默认）」，之后才是真设备。
      expect(dropdown.items, hasLength(3));
      expect(dropdown.items!.first.value, '');
    });
  });
}
