import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音乐 / 图片缓存上限设置的回归测试。
///
/// 只覆盖 SettingsManager 的读写夹取与 SettingsState 的字段映射：走
/// `SettingsNotifier.setMusicCacheLimitMb` / `setImageCacheLimitMb` 会触发
/// `LocalStorage.enforceCacheLimits()`（依赖 path_provider），单测里不跑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsManager> bootManager([
    Map<String, Object> initial = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    // SettingsManager 是单例：每个用例重新 init，让缓存从 mock 值重载。
    final manager = SettingsManager();
    await manager.init();
    return manager;
  }

  test('未持久化时使用默认上限（音乐 512 MB / 图片 256 MB）', () async {
    final manager = await bootManager();

    expect(
      manager.musicCacheLimitMb,
      SettingsManager.DEFAULT_MUSIC_CACHE_LIMIT_MB,
    );
    expect(
      manager.imageCacheLimitMb,
      SettingsManager.DEFAULT_IMAGE_CACHE_LIMIT_MB,
    );
  });

  test('读盘时把越界的历史值夹回 64–8192 MB', () async {
    final manager = await bootManager(<String, Object>{
      SettingsManager.KEY_MUSIC_CACHE_LIMIT_MB: 1,
      SettingsManager.KEY_IMAGE_CACHE_LIMIT_MB: 999999,
    });

    expect(manager.musicCacheLimitMb, SettingsManager.MIN_CACHE_LIMIT_MB);
    expect(manager.imageCacheLimitMb, SettingsManager.MAX_CACHE_LIMIT_MB);
  });

  test('setter 写盘前夹取上下限', () async {
    final manager = await bootManager();

    await manager.setMusicCacheLimitMb(1);
    expect(manager.musicCacheLimitMb, SettingsManager.MIN_CACHE_LIMIT_MB);

    await manager.setMusicCacheLimitMb(999999);
    expect(manager.musicCacheLimitMb, SettingsManager.MAX_CACHE_LIMIT_MB);

    // 范围内原样生效。
    await manager.setImageCacheLimitMb(1024);
    expect(manager.imageCacheLimitMb, 1024);
  });

  test('设置落盘后重新 init 能读回', () async {
    final manager = await bootManager();

    await manager.setMusicCacheLimitMb(2048);
    await manager.setImageCacheLimitMb(128);

    // 不重置 mock 值，模拟用户改完后重启应用再次 init。
    await manager.init();

    expect(manager.musicCacheLimitMb, 2048);
    expect(manager.imageCacheLimitMb, 128);
  });

  test('SettingsState.fromManager 带出两个缓存上限字段', () async {
    final manager = await bootManager(<String, Object>{
      SettingsManager.KEY_MUSIC_CACHE_LIMIT_MB: 1024,
      SettingsManager.KEY_IMAGE_CACHE_LIMIT_MB: 4096,
    });

    final state = SettingsState.fromManager(manager);

    expect(state.musicCacheLimitMb, 1024);
    expect(state.imageCacheLimitMb, 4096);
  });
}
