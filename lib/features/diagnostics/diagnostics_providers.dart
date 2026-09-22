import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/diagnostics/logic/audio_backend_probe.dart';

/// 音频后端测试页的采集器。
///
/// 只读地依赖四个服务（引擎 / 协调器 / 通知 / 焦点），依赖全部走 `ref.watch`
/// 声明，创建与释放交给 Riverpod——页面自己不实例化任何服务。
final audioBackendProbeProvider = Provider<AudioBackendProbe>((ref) {
  return AudioBackendProbe(
    coordinator: ref.watch(playerCoordinatorProvider),
    dualAudio: ref.watch(dualAudioServiceProvider),
    notifications: ref.watch(notificationServiceProvider),
    audioFocus: ref.watch(audioFocusServiceProvider),
  );
});
