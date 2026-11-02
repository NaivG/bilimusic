import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/offline/services/offline_cache_service.dart';
import 'package:bilimusic/features/offline/ui/offline_page.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory baseDir;
  late OfflineCacheService service;
  late ProviderContainer container;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE downloads (
              bvid TEXT NOT NULL,
              cid TEXT NOT NULL,
              title TEXT,
              artist TEXT,
              cover_url TEXT,
              file_path TEXT NOT NULL,
              quality_id TEXT,
              file_size INTEGER DEFAULT 0,
              downloaded_at INTEGER NOT NULL,
              PRIMARY KEY (bvid, cid)
            )
          ''');
        },
      ),
    );
    baseDir = await Directory.systemTemp.createTemp('offline_page_test');
    service = OfflineCacheService();
    service.overrideForTest(db: db, baseDir: baseDir.path);
    container = ProviderContainer(
      overrides: [
        offlineCacheServiceProvider.overrideWithValue(service),
        currentMusicProvider.overrideWithValue(null),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    service.dispose();
    await db.close();
    if (baseDir.existsSync()) await baseDir.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 先把列表查询跑完，页面直接进入 data 态；加载中的无限动画会让
    // pumpAndSettle 一直等下去。数据库查询走真实异步，必须放进 runAsync。
    await tester.runAsync(() => container.read(offlineTracksProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OfflinePage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('没有离线记录时显示空状态', (tester) async {
    await pumpPage(tester);

    expect(find.text('还没有离线音乐'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
  });

  testWidgets('有离线记录时列出标题、作者与音质', (tester) async {
    await tester.runAsync(
      () => db.insert('downloads', {
        'bvid': 'BV1xx411c7mD',
        'cid': '12345',
        'title': '晴天',
        'artist': '周杰伦',
        'file_path': '${baseDir.path}/晴天.m4a',
        'quality_id': '30280',
        'file_size': 1024 * 1024,
        'downloaded_at': DateTime(2026, 11, 2).millisecondsSinceEpoch,
      }),
    );

    await pumpPage(tester);

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
    expect(find.text('192K'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('随机播放'), findsOneWidget);
    expect(find.text('清空缓存'), findsOneWidget);
  });
}
