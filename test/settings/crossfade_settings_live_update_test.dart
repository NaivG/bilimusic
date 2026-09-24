import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// crossfade 设置的实时生效回归测试。
///
/// **走 notifier 改设置后，manager 与 provider 状态必须同时
/// 立即反映新值**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> bootContainer(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final container = ProviderContainer();
    // SettingsManager 是单例：每个用例重新 init，让缓存从 mock 值重载。
    await container.read(settingsManagerProvider).init();
    // 触发 settingsProvider 构建并挂上 manager 监听。
    container.read(settingsProvider);
    return container;
  }

  test('设置 crossfade 时长后 manager 缓存立即更新（实时读回归）', () async {
    final container = await bootContainer({'crossfade_duration': 3000});
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setCrossfadeDuration(8000);

    expect(
      container.read(settingsManagerProvider).crossfadeDuration,
      8000,
      reason: 'PlayerCoordinator 读的是 manager 缓存，必须立即是最新值',
    );
    expect(container.read(settingsProvider).crossfadeDuration, 8000);
  });

  test('设置 crossfade 时长超过预加载时间时自动抬高预加载（manager 不变量）', () async {
    final container = await bootContainer({
      'crossfade_duration': 3000,
      'preload_seconds': 5,
    });
    addTearDown(container.dispose);

    // fade 8 秒 > 预加载 5 秒 → 预加载自动抬到 8
    await container.read(settingsProvider.notifier).setCrossfadeDuration(8000);

    expect(container.read(settingsProvider).preloadSeconds, 8);
    expect(container.read(settingsProvider).crossfadeDuration, 8000);

    // fade 不超过预加载时不该动预加载（8 秒预加载 ≥ 6 秒 fade）
    await container.read(settingsProvider.notifier).setCrossfadeDuration(6000);
    expect(container.read(settingsProvider).crossfadeDuration, 6000);
    expect(container.read(settingsProvider).preloadSeconds, 8);
  });

  test('crossfade 开关 / 自动过渡 / 自动连播委托 manager 实时生效', () async {
    final container = await bootContainer({});
    addTearDown(container.dispose);

    final notifier = container.read(settingsProvider.notifier);

    await notifier.setCrossfadeEnabled(true);
    expect(container.read(settingsManagerProvider).crossfadeEnabled, isTrue);
    expect(container.read(settingsProvider).crossfadeEnabled, isTrue);

    await notifier.setCrossfadeAuto(true);
    expect(container.read(settingsManagerProvider).crossfadeAuto, isTrue);
    expect(container.read(settingsProvider).crossfadeAuto, isTrue);

    await notifier.setAutoPlayNext(false);
    expect(container.read(settingsManagerProvider).autoPlayNext, isFalse);
    expect(container.read(settingsProvider).autoPlayNext, isFalse);
  });

  test('preloadSeconds 夹取与下限不变量（不得小于淡入淡出时长）', () async {
    final container = await bootContainer({
      'crossfade_duration': 8000,
      'preload_seconds': 10,
    });
    addTearDown(container.dispose);

    // 请求 5 秒 < fade 的 8 秒 → 收紧到 8
    await container.read(settingsProvider.notifier).setPreloadSeconds(5);
    expect(container.read(settingsProvider).preloadSeconds, 8);

    // 正常范围内原样生效
    await container.read(settingsProvider.notifier).setPreloadSeconds(20);
    expect(container.read(settingsProvider).preloadSeconds, 20);

    // 超范围夹取到 30
    await container.read(settingsProvider.notifier).setPreloadSeconds(99);
    expect(container.read(settingsProvider).preloadSeconds, 30);
  });

  test('lanSync 模式委托 manager（LanSyncService 靠 manager 通知运行时切换）', () async {
    final container = await bootContainer({'lan_sync_mode': 'off'});
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).setLanSyncMode('private');

    expect(container.read(settingsManagerProvider).lanSyncMode, 'private');
    expect(container.read(settingsProvider).lanSyncMode, 'private');
  });
}
