import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/services/dual_audio_service.dart';
import 'package:bilimusic/managers/settings_manager.dart';
import 'package:bilimusic/managers/user_manager.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart';

final playerCoordinatorProvider = Provider<PlayerCoordinator>((ref) {
  return sl.playerCoordinator;
});

final dualAudioServiceProvider = Provider<DualAudioService>((ref) {
  return sl.dualAudioService;
});

final settingsManagerProvider = Provider<SettingsManager>((ref) {
  return sl.settingsManager;
});

final userManagerProvider = Provider<UserManager>((ref) {
  return sl.userManager;
});

final favSyncManagerProvider = Provider<FavSyncManager>((ref) {
  return sl.favSyncManager;
});
