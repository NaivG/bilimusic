import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';

/// 漫游会话是否活跃（桥接 `PlayerCoordinator.roamingNotifier`）。
///
/// 漫游的启停不止发生在漫游入口：被控端收到遥控指令、或被本机「跟随此设备」
/// 时都会退出漫游，因此漫游 UI 必须订阅这个 provider 被动跟随，而不是在
/// 对话框回调里手动 setState。
class _IsRoamingWatcher extends Notifier<bool> {
  @override
  bool build() {
    final coordinator = ref.read(playerCoordinatorProvider);
    coordinator.roamingNotifier.addListener(_onChanged);
    ref.onDispose(() => coordinator.roamingNotifier.removeListener(_onChanged));
    return coordinator.roamingNotifier.value;
  }

  void _onChanged() =>
      state = ref.read(playerCoordinatorProvider).roamingNotifier.value;
}

final isRoamingProvider = NotifierProvider<_IsRoamingWatcher, bool>(
  _IsRoamingWatcher.new,
);
