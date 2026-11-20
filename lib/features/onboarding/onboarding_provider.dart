import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';

/// 盘上记录的上次启动版本，`null` 表示从未记录。
///
/// 走 `SettingsManager.loadLastBootVersion()` 直接读盘，不用
/// `settingsProvider`：后者只是 SettingsManager 的内存快照，而 manager 的
/// `init()` 在组合根里是 fire-and-forget 的，启动早期读到的会是空值，
/// 于是每个老用户都会被当成初次启动、反复看到引导页。
final lastBootVersionProvider = FutureProvider<String?>((ref) {
  return ref.read(settingsManagerProvider).loadLastBootVersion();
});

/// 记录本次启动的版本号。
///
/// 先落盘再展示：用户中途关掉应用，下次启动也不会把同一次升级再弹一遍。
/// 回看引导页（设置入口）不会调用这里，因此不会改动升级判定。
Future<void> recordBootVersion(WidgetRef ref, String version) async {
  await ref.read(settingsManagerProvider).setLastBootVersion(version);
}
