import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/app/app_providers.dart';

final _dualAudioServiceProvider = dualAudioServiceProvider;
final _playerCoordinatorProvider = playerCoordinatorProvider;

/// 桥接 [DualAudioService.audioDevices] 的只读镜像
/// （固定桥接写法见 `effects_providers.dart`：build 内 addListener +
/// ref.onDispose 中 removeListener）。
///
/// 起步阶段是空列表——mpv 在 core 初始化之后才报真设备，页面据此显示
/// 「设备列表尚未就绪」而不是塞一个假的 `auto` 进下拉。
class _AudioDevicesWatcher extends Notifier<List<mpv.Device>> {
  @override
  List<mpv.Device> build() {
    final vn = ref.read(_dualAudioServiceProvider).audioDevices;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_dualAudioServiceProvider).audioDevices.value;
}

/// 当前可用的输出设备（A/B 两路的并集，已剔除 mpv 的 `auto` 哨兵）。
final audioDevicesProvider =
    NotifierProvider<_AudioDevicesWatcher, List<mpv.Device>>(
      _AudioDevicesWatcher.new,
    );

/// 桥接 [DualAudioService.audioDevice] 的只读镜像。
///
/// 读的是**实际生效**的设备，不是用户存的偏好：mpv 请求的设备不在时会
/// 回退到 `auto`，两者不一致时页面要点破，否则用户会以为耳机还在用。
class _AudioDeviceWatcher extends Notifier<mpv.Device> {
  @override
  mpv.Device build() {
    final vn = ref.read(_dualAudioServiceProvider).audioDevice;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_dualAudioServiceProvider).audioDevice.value;
}

/// 实际生效的输出设备。
final audioDeviceProvider = NotifierProvider<_AudioDeviceWatcher, mpv.Device>(
  _AudioDeviceWatcher.new,
);

/// 音频输出命令 —— UI 写这四项的统一入口。
///
/// 链路：这里 → PlayerCoordinator.setAudio* → SettingsManager（落盘，事实
/// 来源）→ DualAudioService（A/B 两路）。UI 不自己编排「先落盘后推引擎」，
/// 也不要把四项打包成一次调用——独占 / 采样率 / 设备任一变更都会让 mpv
/// 重建 AO（短暂静音），延迟不会。
///
/// 写失败时 Future 原样抛出（两路播放器全挂才抛，见 `_broadcast`），
/// 由页面转成 SnackBar；此时 SettingsManager 已经写了新值，下次启动重放。
class AudioOutputCommands extends Notifier<void> {
  @override
  void build() {}

  /// 音频延迟（毫秒，正数＝声音延后）。
  Future<void> setDelayMs(int ms) =>
      ref.read(_playerCoordinatorProvider).setAudioDelayMs(ms);

  /// 硬件直通 / 独占模式。
  Future<void> setExclusive(bool value) =>
      ref.read(_playerCoordinatorProvider).setAudioExclusive(value);

  /// 强制 DAC 采样率，`0` 表示跟随音源。
  Future<void> setSampleRate(int rate) =>
      ref.read(_playerCoordinatorProvider).setAudioSampleRate(rate);

  /// 输出设备的 mpv `Device.name`，空串表示跟随系统。
  Future<void> setDeviceName(String name) =>
      ref.read(_playerCoordinatorProvider).setAudioDeviceName(name);

  /// 四项一起回默认（不动免责闸门）。
  Future<void> resetDefaults() =>
      ref.read(_playerCoordinatorProvider).resetAudioOutputDefaults();
}

final audioOutputCommandsProvider = NotifierProvider<AudioOutputCommands, void>(
  AudioOutputCommands.new,
);
