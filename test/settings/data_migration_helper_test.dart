import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/features/settings/logic/data_migration_helper.dart';

/// [PlaylistService] 的替身：数据迁移测试只关心 map 的拼装与落盘，
/// 不需要真的开库。
class _FakePlaylistService extends PlaylistService {
  _FakePlaylistService(this.exportData);

  final Map<String, String?> exportData;
  Map<String, dynamic>? imported;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, String?>> exportForBackup() async => exportData;

  @override
  Future<void> importFromBackup(Map<String, dynamic> data) async {
    imported = data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('导出', () {
    test('包含完整设置、登录凭据与播放状态', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'notifications_enabled': false,
        'appearance': 'dark',
        'theme': 'nord',
        'audio_quality': '30251',
        'crossfade_enabled': true,
        'crossfade_duration': 5000,
        'roam_style': 'explore',
        'title_meta_filter': true,
        'cookies': '{"SESSDATA":"sess"}',
        'login_time': '1700000000000',
        'bili_refresh_token_v1': '{"version":1,"refresh_token":"token"}',
        'player_volume': 0.42,
        'player_audio_effects_v1': '{"aneq":{"enabled":true}}',
        'fav_import_records': '[]',
      });

      final helper = DataMigrationHelper(
        playlistService: _FakePlaylistService({'play_history': '[]'}),
      );
      final data = await helper.buildExportData();

      expect(data['backup_format'], 'bilimusic');
      expect(data['backup_version'], 2);
      expect(data['exported_at'], isA<String>());

      final settings = data['settings'] as Map<String, dynamic>;
      expect(settings['notifications_enabled'], false);
      expect(settings['appearance'], 'dark');
      expect(settings['theme'], 'nord');
      expect(settings['audio_quality'], '30251');
      expect(settings['crossfade_enabled'], true);
      expect(settings['crossfade_duration'], 5000);
      expect(settings['roam_style'], 'explore');
      expect(settings['title_meta_filter'], true);

      expect(data['cookies'], '{"SESSDATA":"sess"}');
      expect(data['login_time'], '1700000000000');
      expect(data['refresh_token'], '{"version":1,"refresh_token":"token"}');
      expect(data['player_volume'], 0.42);
      expect(data['audio_effects'], '{"aneq":{"enabled":true}}');
      expect(data['fav_import_records'], '[]');
      expect(data['play_history'], '[]');
    });

    test('设置缺省时导出默认值，不产生 null', () async {
      final helper = DataMigrationHelper(
        playlistService: _FakePlaylistService({}),
      );
      final data = await helper.buildExportData();
      final settings = data['settings'] as Map<String, dynamic>;

      expect(settings.values, isNot(contains(null)));
      expect(settings['appearance'], 'system');
      expect(settings['audio_quality'], '30280');
    });
  });

  group('导入', () {
    test('旧键名映射到当前设置，并拒绝未知键', () async {
      final fake = _FakePlaylistService({});
      final helper = DataMigrationHelper(playlistService: fake);

      await helper.restore(<String, dynamic>{
        'settings': <String, dynamic>{
          'theme_mode': 'dark',
          'theme_color': 'nord',
          'notifications_enabled': false,
          'crossfade_duration': 4000.0,
          'audio_exclusive': true,
          'unknown_key': 'ignored',
        },
        'cookies': '{"SESSDATA":"sess"}',
        'refresh_token': '{"version":1,"refresh_token":"token"}',
        'player_volume': 1.5,
        'audio_effects': '{"aneq":{"enabled":true}}',
        'fav_import_records': '[]',
        'current_queue': '[]',
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance'), 'dark');
      expect(prefs.getString('theme'), 'nord');
      expect(prefs.getBool('notifications_enabled'), false);
      expect(prefs.getInt('crossfade_duration'), 4000);
      expect(prefs.getBool('audio_exclusive'), true);
      expect(prefs.containsKey('unknown_key'), false);
      expect(prefs.getString('cookies'), '{"SESSDATA":"sess"}');
      expect(prefs.getString('bili_refresh_token_v1'), contains('token'));
      expect(prefs.getDouble('player_volume'), 1.0);
      expect(prefs.getString('player_audio_effects_v1'), contains('aneq'));
      expect(prefs.getString('fav_import_records'), '[]');

      expect(fake.imported, isNotNull);
      expect(fake.imported!['current_queue'], '[]');
    });

    test('非法 JSON / 非对象根节点抛格式异常', () {
      expect(
        () => DataMigrationHelper.decode('{'),
        throwsA(isA<DataMigrationFormatException>()),
      );
      expect(
        () => DataMigrationHelper.decode('[]'),
        throwsA(isA<DataMigrationFormatException>()),
      );
      expect(
        () => DataMigrationHelper.decode('{"backup_format":"other"}'),
        throwsA(isA<DataMigrationFormatException>()),
      );
      expect(
        () => DataMigrationHelper.decode('{"kind":"full","version":1}'),
        throwsA(isA<DataMigrationFormatException>()),
      );
      expect(
        DataMigrationHelper.decode('{"backup_format":"bilimusic"}')['settings'],
        isNull,
      );
    });
  });

  group('版本判断', () {
    test('旧备份缺版本号需要确认', () {
      final compatibility = DataMigrationHelper.checkCompatibility({
        'settings': <String, dynamic>{},
      });
      expect(compatibility.missingVersion, isTrue);
      expect(compatibility.needsConfirmation, isTrue);
    });

    test('当前版本与旧格式不需要确认', () {
      final compatibility = DataMigrationHelper.checkCompatibility({
        'settings': <String, dynamic>{'version_code': 80},
      });
      expect(compatibility.newerThanApp, isFalse);
      expect(compatibility.newerFormat, isFalse);
      expect(compatibility.needsConfirmation, isFalse);
    });

    test('数据版本或格式版本更高时都要确认', () {
      final compatibility = DataMigrationHelper.checkCompatibility({
        'backup_version': 99,
        'settings': <String, dynamic>{'version_code': 81},
      });
      expect(compatibility.newerThanApp, isTrue);
      expect(compatibility.newerFormat, isTrue);
      expect(compatibility.needsConfirmation, isTrue);
    });
  });
}
