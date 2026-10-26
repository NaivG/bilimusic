import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/core/network/passport_store.dart';
import 'package:bilimusic/features/fav_sync/fav_sync_manager.dart';
import 'package:bilimusic/features/player/logic/audio_effects_service.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 数据迁移的导出 / 导入逻辑。
///
/// 页面只负责按钮状态与弹窗；备份文件的组装、解析、版本判断、
/// SharedPreferences 与数据库写入都在这里。
class DataMigrationHelper {
  DataMigrationHelper({required this.playlistService});

  final PlaylistService playlistService;

  static const String format = 'bilimusic';
  static const int formatVersion = 2;

  static const String _formatKey = 'backup_format';
  static const String _formatVersionKey = 'backup_version';
  static const String _cookiesKey = 'cookies';
  static const String _loginTimeKey = 'login_time';

  /// 旧备份没有 `backup_format`，用这些顶层键判断它是不是数据备份。
  static const Set<String> _knownTopLevelKeys = {
    'settings',
    'cookies',
    'login_time',
    'play_history',
    'favorites',
    'user_playlists',
    'user_playlists_enhanced',
    'current_queue',
    'custom_tags',
    'kv',
    'audio_effects',
    'fav_import_records',
  };

  /// 备份里允许导出 / 导入的设置项及其默认值。
  ///
  /// 显式列成白名单：导入文件不能往 SharedPreferences 里写任意键。
  /// `SettingsManager` 新增设置项时同步补到这里。
  static final Map<String, Object> _settingDefaults = {
    SettingsManager.KEY_NOTIFICATIONS_ENABLED:
        SettingsManager.DEFAULT_NOTIFICATIONS_ENABLED,
    SettingsManager.KEY_APPEARANCE: SettingsManager.DEFAULT_APPEARANCE,
    SettingsManager.KEY_THEME: SettingsManager.DEFAULT_THEME,
    SettingsManager.KEY_AUTO_PLAY_NEXT: SettingsManager.DEFAULT_AUTO_PLAY_NEXT,
    SettingsManager.KEY_SHOW_LYRICS: SettingsManager.DEFAULT_SHOW_LYRICS,
    SettingsManager.KEY_FLUID_BACKGROUND:
        SettingsManager.DEFAULT_FLUID_BACKGROUND,
    SettingsManager.KEY_BLUR_EFFECT: SettingsManager.DEFAULT_BLUR_EFFECT,
    SettingsManager.KEY_AUDIO_QUALITY: SettingsManager.DEFAULT_AUDIO_QUALITY,
    SettingsManager.KEY_VERSION_CODE: SettingsManager.DEFAULT_VERSION_CODE,
    SettingsManager.KEY_AUDIO_OUTPUT_DISCLAIMER:
        SettingsManager.DEFAULT_AUDIO_OUTPUT_DISCLAIMER,
    SettingsManager.KEY_AUDIO_DELAY_MS: SettingsManager.DEFAULT_AUDIO_DELAY_MS,
    SettingsManager.KEY_AUDIO_EXCLUSIVE:
        SettingsManager.DEFAULT_AUDIO_EXCLUSIVE,
    SettingsManager.KEY_AUDIO_SAMPLERATE:
        SettingsManager.DEFAULT_AUDIO_SAMPLERATE,
    SettingsManager.KEY_AUDIO_DEVICE: SettingsManager.DEFAULT_AUDIO_DEVICE,
    SettingsManager.KEY_CROSSFADE_ENABLED:
        SettingsManager.DEFAULT_CROSSFADE_ENABLED,
    SettingsManager.KEY_CROSSFADE_DURATION:
        SettingsManager.DEFAULT_CROSSFADE_DURATION,
    SettingsManager.KEY_CROSSFADE_AUTO: SettingsManager.DEFAULT_CROSSFADE_AUTO,
    SettingsManager.KEY_PRELOAD_SECONDS:
        SettingsManager.DEFAULT_PRELOAD_SECONDS,
    SettingsManager.KEY_ROAM_STYLE: SettingsManager.DEFAULT_ROAM_STYLE.name,
    SettingsManager.KEY_ROAM_REFILL_THRESHOLD:
        SettingsManager.DEFAULT_ROAM_REFILL_THRESHOLD,
    SettingsManager.KEY_LAN_SYNC_MODE: SettingsManager.DEFAULT_LAN_SYNC_MODE,
    SettingsManager.KEY_LAN_SYNC_DEVICE_NAME:
        SettingsManager.DEFAULT_LAN_SYNC_DEVICE_NAME,
    SettingsManager.KEY_CLOSE_BEHAVIOR: SettingsManager.DEFAULT_CLOSE_BEHAVIOR,
    SettingsManager.KEY_TITLE_META_FILTER:
        SettingsManager.DEFAULT_TITLE_META_FILTER,
  };

  /// 旧备份里的设置键名 → 当前键名。
  static const Map<String, String> _legacySettingKeys = {
    'theme_mode': SettingsManager.KEY_APPEARANCE,
    'theme_color': SettingsManager.KEY_THEME,
  };

  // ── 导出 ──────────────────────────────────────────────────────────────

  /// 组装一份完整备份。列表 / 歌单 / 队列 / 标签由 [PlaylistService] 提供。
  Future<Map<String, dynamic>> buildExportData() async {
    await playlistService.initialize();
    final prefs = await SharedPreferences.getInstance();
    final playlistData = await playlistService.exportForBackup();

    return <String, dynamic>{
      _formatKey: format,
      _formatVersionKey: formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': _exportSettings(prefs),
      _cookiesKey: prefs.getString(_cookiesKey),
      _loginTimeKey: prefs.getString(_loginTimeKey),
      'refresh_token': prefs.getString(PassportStore.prefsKey),
      'player_volume': prefs.getDouble(DualAudioService.KEY_VOLUME),
      'audio_effects': prefs.getString(AudioEffectsService.prefsKey),
      'fav_import_records': prefs.getString(FavSyncManager.prefsKey),
      ...playlistData,
    };
  }

  /// 导出并让用户选择保存位置。取消返回 null。
  Future<String?> exportToFile() async {
    final data = await buildExportData();
    final content = jsonEncode(data);
    return _saveJsonFile(
      bytes: utf8.encode(content),
      fileName: 'bilimusic_data_${DateTime.now().millisecondsSinceEpoch}.json',
    );
  }

  Map<String, dynamic> _exportSettings(SharedPreferences prefs) {
    final settings = <String, dynamic>{};
    _settingDefaults.forEach((key, fallback) {
      settings[key] = _readSetting(prefs, key, fallback);
    });
    return settings;
  }

  Object _readSetting(SharedPreferences prefs, String key, Object fallback) {
    if (fallback is bool) return prefs.getBool(key) ?? fallback;
    if (fallback is int) return prefs.getInt(key) ?? fallback;
    if (fallback is double) return prefs.getDouble(key) ?? fallback;
    if (fallback is String) return prefs.getString(key) ?? fallback;
    return prefs.get(key) ?? fallback;
  }

  // ── 导入 ──────────────────────────────────────────────────────────────

  /// 让用户选择文件并解析。取消返回 null；文件结构错误抛
  /// [DataMigrationFormatException]。
  Future<PickedBackup?> pickBackupFile() async {
    final content = await _pickJsonFile();
    if (content == null) return null;
    final data = decode(content);
    return PickedBackup(data: data, compatibility: checkCompatibility(data));
  }

  /// 把备份写回本地。**调用方负责先确认覆盖**。
  Future<void> restore(Map<String, dynamic> data) async {
    await playlistService.initialize();
    final prefs = await SharedPreferences.getInstance();
    await _restoreSettings(prefs, data['settings']);
    await playlistService.importFromBackup(data);
    await _restoreCredentials(prefs, data);
    await _restorePlayerState(prefs, data);
    debugPrint('[DataMigrationHelper] 数据导入完成');
  }

  Future<void> _restoreSettings(
    SharedPreferences prefs,
    Object? rawSettings,
  ) async {
    if (rawSettings is! Map) return;
    for (final entry in rawSettings.entries) {
      final rawKey = entry.key;
      if (rawKey is! String) continue;
      final key = _legacySettingKeys[rawKey] ?? rawKey;
      final fallback = _settingDefaults[key];
      if (fallback == null) continue;

      final value = entry.value;
      if (fallback is bool && value is bool) {
        await prefs.setBool(key, value);
      } else if (fallback is int && value is num) {
        await prefs.setInt(key, value.toInt());
      } else if (fallback is double && value is num) {
        await prefs.setDouble(key, value.toDouble());
      } else if (fallback is String && value is String) {
        await prefs.setString(key, value);
      }
    }
  }

  Future<void> _restoreCredentials(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    final cookies = data[_cookiesKey];
    if (cookies is String && cookies.isNotEmpty) {
      await prefs.setString(_cookiesKey, cookies);
    }
    final loginTime = data[_loginTimeKey];
    if (loginTime is String) {
      await prefs.setString(_loginTimeKey, loginTime);
    }
    final refreshToken = data['refresh_token'];
    if (refreshToken is String && refreshToken.isNotEmpty) {
      await prefs.setString(PassportStore.prefsKey, refreshToken);
    }
  }

  Future<void> _restorePlayerState(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    final volume = data['player_volume'];
    if (volume is num) {
      await prefs.setDouble(
        DualAudioService.KEY_VOLUME,
        volume.toDouble().clamp(0.0, 1.0),
      );
    }
    final effects = data['audio_effects'];
    if (effects is String && effects.isNotEmpty) {
      await prefs.setString(AudioEffectsService.prefsKey, effects);
    }
    final favRecords = data['fav_import_records'];
    if (favRecords is String) {
      await prefs.setString(FavSyncManager.prefsKey, favRecords);
    }
  }

  // ── 解析 / 版本 ───────────────────────────────────────────────────────

  /// 解析备份文件根节点。失败抛 [DataMigrationFormatException]。
  static Map<String, dynamic> decode(String content) {
    Object? raw;
    try {
      raw = jsonDecode(content);
    } on FormatException catch (e) {
      throw DataMigrationFormatException('文件不是合法的 JSON：${e.message}');
    }
    if (raw is! Map) {
      throw const DataMigrationFormatException('文件根节点不是对象');
    }
    final data = raw.cast<String, dynamic>();
    final formatName = data[_formatKey];
    if (formatName != null) {
      if (formatName != format) {
        throw const DataMigrationFormatException('不是 BiliMusic 的数据文件');
      }
    } else if (!_looksLikeLegacyBackup(data)) {
      throw const DataMigrationFormatException('不是 BiliMusic 的数据文件');
    }
    return data;
  }

  static bool _looksLikeLegacyBackup(Map<String, dynamic> data) {
    return data.keys.any(
      (key) =>
          _knownTopLevelKeys.contains(key) ||
          key.startsWith('playlist_info_') ||
          key.startsWith('playlist_songs_'),
    );
  }

  /// 读取备份里的数据版本 / 格式版本，供页面决定是否弹兼容性提示。
  static BackupCompatibility checkCompatibility(Map<String, dynamic> data) {
    final settings = data['settings'];
    final rawVersionCode = settings is Map
        ? settings[SettingsManager.KEY_VERSION_CODE]
        : null;
    final rawFormatVersion = data[_formatVersionKey];

    return BackupCompatibility(
      dataVersionCode: rawVersionCode is num ? rawVersionCode.toInt() : null,
      appVersionCode: SettingsManager.DEFAULT_VERSION_CODE,
      formatVersion: rawFormatVersion is num ? rawFormatVersion.toInt() : null,
    );
  }

  // ── 文件 ──────────────────────────────────────────────────────────────

  Future<String?> _saveJsonFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '请选择保存位置:',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: PlatformHelper.isMobile ? Uint8List.fromList(bytes) : null,
    );
    if (path == null) return null;
    if (!PlatformHelper.isMobile) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  Future<String?> _pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: '请选择数据文件',
      withData: PlatformHelper.isMobile,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes != null) return utf8.decode(bytes);
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsString();
  }
}

/// 选择后的备份文件。
class PickedBackup {
  const PickedBackup({required this.data, required this.compatibility});

  final Map<String, dynamic> data;
  final BackupCompatibility compatibility;
}

/// 备份文件的版本信息。
class BackupCompatibility {
  const BackupCompatibility({
    required this.dataVersionCode,
    required this.appVersionCode,
    required this.formatVersion,
  });

  /// 备份里 `settings.version_code` 的值；旧备份可能没有。
  final int? dataVersionCode;

  /// 当前应用接受的数据版本。
  final int appVersionCode;

  /// 备份文件自身的格式版本；旧备份没有。
  final int? formatVersion;

  bool get missingVersion => dataVersionCode == null;

  bool get newerThanApp =>
      dataVersionCode != null && dataVersionCode! > appVersionCode;

  bool get newerFormat =>
      formatVersion != null &&
      formatVersion! > DataMigrationHelper.formatVersion;

  bool get needsConfirmation => missingVersion || newerThanApp || newerFormat;
}

/// 备份文件不是合法 JSON / 根节点结构错误。
class DataMigrationFormatException implements Exception {
  const DataMigrationFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
