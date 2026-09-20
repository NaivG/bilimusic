/// 「退回旧落点」这条路会不会自己造出一个空壳库。
///
/// 现场（2026-09-20 22:28）：应用数据目录拿到了真数据（233472 B / 97 行，
/// 22:28:30.144 新建 —— 同目录刚归档出去的 `.bak` 把创建时间 tunnelling 给了它），
/// 而**旧落点（应用目录）里多出一个 86016 B、8 张表全 0 行、change counter=1 的
/// 空壳库**（22:28:30.246，同样从被搬走的那份继承了 10:32:14 的创建时间）——
/// 两份相差 102 ms、哈希不同、行数不同，空壳那份只能是 `onCreate` 刚建出来的。
///
/// 谁建的：`relocateDatabase` 的失败分支返回 `directory: legacy`，而调用方
/// `_resolveLocation()` 会拿这个目录去 `openDatabase(legacy/playlist.db)`。旧落点里
/// 的库要是已经不在了（源在 `exists()` 之后被**另一个并发搬运**搬走并删掉），
/// `openDatabase` 就原地建一个新库 —— `done` 为空时回滚无事可做，**「退回旧落点」
/// 退回到了一个空目录**。
///
/// 并发从哪来：`AppDatabase.database` 原先只有 `if (_db != null)` 兜底，没有单飞。
/// 启动时 `playlistService.initialize()`（main.dart:137）与
/// `unawaited(AppDatabase.instance.migrateFromPrefsOnce())`（main.dart:143）
/// 会同时进来，正好构成「两个 `_resolveLocation()` 抢同一份源」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/core/storage/database.dart';
import 'package:bilimusic/core/storage/database_path_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const dbName = 'playlist.db';

  late Directory root;
  late Directory target;
  late Directory previousCwd;

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    previousCwd = Directory.current;
    root = await Directory.systemTemp.createTemp('bilimusic_reloc_');
    target = Directory(p.join(root.path, 'appdata'))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.directoryResolver = null;
    Directory.current = previousCwd.path;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// sqflite 的默认落点：`<cwd>/.dart_tool/sqflite_common_ffi/databases`。
  /// 测试把 cwd 换到临时目录，这样候选落点里只有自己造的库 ——
  /// 绝不碰仓库里那份真库。
  String legacyDirIn(String cwd) =>
      p.join(cwd, '.dart_tool', 'sqflite_common_ffi', 'databases');

  /// 造一份可用的库：user_version=2（不会被当成待升级的老库）+ 一张 kv 表。
  Future<void> makeDatabase(String path, {String seed = 'seed'}) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        onCreate: (db, _) => db.execute('CREATE TABLE kv (k TEXT PRIMARY KEY)'),
      ),
    );
    await db.insert('kv', {'k': seed});
    await db.close();
  }

  Future<int> rowCountOf(String path) async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM kv');
      return rows.first['c']! as int;
    } finally {
      await db.close();
    }
  }

  /// 找一个**与 [reference] 不同卷**的目录：从它往 [reference] 里 rename 会失败。
  /// 复现那条路径必须跨卷 —— 同卷走的是 `rename`，跨卷才走「拷贝 → 删源」，
  /// 而「删源」正是并发那次撞车的地方（也正是真机的形态：库在 D:，应用数据目录在 C:）。
  Future<Directory?> secondVolumeDirectory(String reference) async {
    for (final letter in ['D', 'E', 'F', 'G']) {
      final rootPath = '${letter[0]}:\\';
      if (!Directory(rootPath).existsSync()) continue;
      final probe = Directory(p.join(rootPath, 'bilimusic_reloc_probe'));
      try {
        probe.createSync(recursive: true);
        final source = File(p.join(probe.path, 'probe.bin'))
          ..writeAsStringSync('x');
        final destination = p.join(reference, 'probe.bin');
        await source.rename(destination);
        // 同卷：rename 成功，不是我们要的卷。
        await File(destination).delete();
      } on FileSystemException {
        return probe;
      } finally {
        try {
          probe.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    return null;
  }

  group('搬失败之后该开哪个目录（不变量：绝不返回没有库的落点）', () {
    test('目标有非空主库（并发赢家刚搬完）→ 用目标', () async {
      final legacy = p.join(root.path, 'legacy');
      await makeDatabase(p.join(legacy, dbName));
      await makeDatabase(p.join(target.path, dbName));

      expect(
        await directoryAfterFailedRelocation(
          legacy: legacy,
          target: target.path,
          databaseFileName: dbName,
        ),
        target.path,
      );
    });

    test('旧落点有、目标没有（真没搬动）→ 用旧落点', () async {
      final legacy = p.join(root.path, 'legacy');
      await makeDatabase(p.join(legacy, dbName));

      expect(
        await directoryAfterFailedRelocation(
          legacy: legacy,
          target: target.path,
          databaseFileName: dbName,
        ),
        legacy,
      );
    });

    test('两边都没有（源被搬走又没落到目标）→ 用目标，绝不退回空目录', () async {
      final legacy = p.join(root.path, 'legacy');
      Directory(legacy).createSync(recursive: true);

      expect(
        await directoryAfterFailedRelocation(
          legacy: legacy,
          target: target.path,
          databaseFileName: dbName,
        ),
        target.path,
        reason: '退回旧落点会让调用方在那里 openDatabase 出一个空壳库',
      );
    });

    test('0 字节残渣不算「有库」', () async {
      final legacy = p.join(root.path, 'legacy');
      Directory(legacy).createSync(recursive: true);
      await File(p.join(legacy, dbName)).writeAsBytes(const []);

      expect(
        await directoryAfterFailedRelocation(
          legacy: legacy,
          target: target.path,
          databaseFileName: dbName,
        ),
        target.path,
      );
    });
  });

  test('跨卷搬中途源消失 → 返回目标，不在旧落点留下空壳（现场复现）', () async {
    final scratch = await secondVolumeDirectory(root.path);
    if (scratch == null) {
      markTestSkipped('需要第二个卷才能复现跨卷搬迁（同卷走 rename，撞不出这条路径）');
      return;
    }

    final legacy = Directory(p.join(scratch.path, 'legacy'))
      ..createSync(recursive: true);
    final legacyDb = p.join(legacy.path, dbName);
    final targetDb = p.join(target.path, dbName);
    await makeDatabase(legacyDb);
    // 大一点的旁文件：搬迁顺序是「先旁文件、后主库」，它给了我们一个稳定的窗口，
    // 去模拟「并发的另一次搬迁已经把主库搬走」。
    await File('$legacyDb-wal')
        .writeAsBytes(List<int>.filled(32 * 1024 * 1024, 0x41), flush: true);
    // 目标目录**故意不建**：它一出现就说明这次搬迁已经过了「查源」那一步。
    Directory(target.path).deleteSync(recursive: true);

    final relocation = relocateDatabase(
      legacyDirectory: legacy.path,
      targetDirectory: target.path,
      databaseFileName: dbName,
    );

    while (!Directory(target.path).existsSync()) {
      await Future<void>.delayed(Duration.zero);
    }
    await File(legacyDb).delete();

    final result = await relocation;
    // ignore: avoid_print
    print('[relocation] directory=${result.directory} reason=${result.reason}');

    expect(File(legacyDb).existsSync(), isFalse, reason: '前提：源确实在这次搬迁途中消失了');
    expect(
      result.directory,
      target.path,
      reason:
          '旧落点已经没有库了，不能把它当成可用的落点 —— '
          '调用方会立刻 openDatabase 出一个空壳库（现场那份 86016 B / 0 行）',
    );
    expect(File(targetDb).existsSync(), isFalse, reason: '这次没有真的搬成，目标不该有库');
  });

  test('并发两次开库：只解析一次落点，两次拿到同一个 Database', () async {
    Directory.current = root.path;
    final legacy = Directory(legacyDirIn(root.path))
      ..createSync(recursive: true);
    final legacyDb = p.join(legacy.path, dbName);
    final targetDb = p.join(target.path, dbName);
    await makeDatabase(legacyDb, seed: 'real-data');
    AppDatabase.directoryResolver = () async => target.path;

    // main.dart 里同时进来的两条：`playlistService.initialize()` 与
    // `unawaited(migrateFromPrefsOnce())` —— 都是 await AppDatabase.instance.database。
    final first = AppDatabase.instance.database;
    final second = AppDatabase.instance.database;
    expect(identical(first, second), isTrue, reason: '并发调用必须共用同一次开库');

    final opened = await Future.wait([first, second]);
    expect(identical(opened.first, opened.last), isTrue);

    expect(await rowCountOf(targetDb), 1, reason: '真数据应当被搬进应用数据目录');
    expect(File(legacyDb).existsSync(), isFalse, reason: '旧落点应当被搬空');
    expect(
      await rowCountOf(targetDb),
      1,
      reason: '目标里那份必须是真数据，不是 onCreate 建出来的空壳',
    );
  });
}
