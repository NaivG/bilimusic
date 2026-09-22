import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/app/app_providers.dart';

final _audioEffectsServiceProvider = audioEffectsServiceProvider;
final _playerCoordinatorProvider = playerCoordinatorProvider;

/// 桥接 AudioEffectsService.effects 的只读状态镜像
/// （固定桥接写法见 `playback_providers.dart`：build 内 addListener +
/// ref.onDispose 中 removeListener）。
class _AudioEffectsWatcher extends Notifier<mpv.AudioEffects> {
  @override
  mpv.AudioEffects build() {
    final vn = ref.read(_audioEffectsServiceProvider).effects;
    vn.addListener(_onChanged);
    ref.onDispose(() => vn.removeListener(_onChanged));
    return vn.value;
  }

  void _onChanged() =>
      state = ref.read(_audioEffectsServiceProvider).effects.value;
}

/// 当前音频效果包（只读镜像）。写入口在 [audioEffectsCommandsProvider]。
final audioEffectsProvider =
    NotifierProvider<_AudioEffectsWatcher, mpv.AudioEffects>(
      _AudioEffectsWatcher.new,
    );

/// 音频效果命令 —— UI 写效果的统一入口。
///
/// 链路：这里 → PlayerCoordinator.setAudioEffects →
/// AudioEffectsService（状态 + 独立持久化）→ DualAudioService（A/B 两路）。
///
/// AudioEffects 是不可变值对象，每次修改都是整包 copyWith；滑动条频繁
/// 拖动时用本地 draft 承接 onChange，onChangeEnd 再提交一次（引擎侧
/// 对相同包自动 no-op，参数级变化走 af-command 原地热更，不重建链）。
class AudioEffectsCommands extends Notifier<void> {
  @override
  void build() {}

  /// 整包替换。
  Future<void> setEffects(mpv.AudioEffects effects) =>
      ref.read(_playerCoordinatorProvider).setAudioEffects(effects);

  /// 局部 patch：[mapper] 收到当前包，返回新包。
  Future<void> update(mpv.AudioEffects Function(mpv.AudioEffects) mapper) =>
      setEffects(mapper(ref.read(_audioEffectsServiceProvider).effects.value));
}

final audioEffectsCommandsProvider =
    NotifierProvider<AudioEffectsCommands, void>(AudioEffectsCommands.new);
