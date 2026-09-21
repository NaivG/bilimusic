import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bilimusic/core/storage/database_conflict.dart';
import 'package:bilimusic/core/storage/database_conflict_resolver.dart';
import 'package:bilimusic/core/storage/database_inspector.dart';
import 'package:bilimusic/core/storage/database_path_migration.dart';

/// 「盘上不止一份库」这条路的行为密封测试。
///
/// 要钉死的是四件事：
/// - **数得准**：三处落点（cwd 算出来的、exe 旁边的、应用数据目录）取**并集**，
///   有两份就是两份 —— 包括「两份都落在候选侧、应用数据目录还空着」这种老判据
///   漏掉的情况；
/// - **问得对**：只有一份读得出来时不打扰用户（自动把读不出来的归档），不止一份
///   读得出来才问；
/// - **收得住**：用户选完，落败的整组**改名归档而不是删除**，赢家留在原处；
/// - **会收敛**：归档之后重新扫一遍只会看到一份，重启后的新进程走最朴素的
///   「搬过去 / 打开」，**不需要任何持久化的决策记录** —— 早先那版记「赢家 + 指纹」，
///   判据一和归档动作的先后顺序错开就变成每次启动都重新问一遍。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const dbName = 'playlist.db';

  late Directory root;
  late String cwdDir;
  late String exeDir;
  late String exeDbDir;
  late String target;

  /// 双击 exe 启动时 cwd 恰好是 exe 目录，于是 sqflite 在那里算出来的落点 ——
  /// 「exe 旁边」指的就是它，**不是 exe 目录本身**（库从来没有直接放在那儿过）。
  String sqfliteLayoutIn(String directory) =>
      p.join(directory, '.dart_tool', 'sqflite_common_ffi', 'databases');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bilimusic_conflict_');
    cwdDir = p.join(root.path, 'cwd', 'databases');
    exeDir = p.join(root.path, 'appdir');
    exeDbDir = sqfliteLayoutIn(exeDir);
    target = p.join(root.path, 'appdata');
    await Directory(cwdDir).create(recursive: true);
    await Directory(exeDir).create(recursive: true);
    await Directory(exeDbDir).create(recursive: true);
    await Directory(target).create(recursive: true);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  // ---------- 造库工具 ----------

  /// 造一个结构齐、行数可控的库。[rows] 是每张业务表的行数。
  ///
  /// 用 `singleInstance: false`：sqflite ffi 的 factory 会复用同路径的
  /// `singleInstance` 连接，第二次「造库」会拿到旧连接、`onCreate` 不执行。
  Future<void> makeDatabase(String path, {int rows = 0}) async {
    if (File(path).existsSync()) {
      await databaseFactoryFfi.deleteDatabase(path);
    }
    await Directory(p.dirname(path)).create(recursive: true);
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        singleInstance: false,
        onCreate: (db, _) async {
          for (final table in [
            'current_track',
            'play_history',
            'favorite',
            'playlist',
            'playlist_song',
          ]) {
            await db.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
          }
        },
      ),
    );
    for (final table in [
      'current_track',
      'play_history',
      'favorite',
      'playlist',
      'playlist_song',
    ]) {
      for (var i = 0; i < rows; i++) {
        await db.insert(table, {'id': i + 1});
      }
    }
    await db.close();
  }

  /// 造一份**非空但不是 SQLite** 的文件：结构读不出来，但不该被删。
  Future<void> makeGarbage(String path) async {
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsBytes(List<int>.filled(2048, 0x41));
  }

  String dbAt(String directory) => p.join(directory, dbName);

  Future<DatabaseScan> scan([List<String>? candidates]) =>
      scanDatabasePlacements(
        candidateDirectories: candidates ?? [cwdDir, exeDbDir],
        targetDirectory: target,
        databaseFileName: dbName,
      );

  Future<DatabaseScan?> preflight([List<String>? candidates]) =>
      preflightDatabasePlacement(
        candidateDirectories: candidates ?? [cwdDir, exeDbDir],
        targetDirectory: target,
        databaseFileName: dbName,
        factory: databaseFactoryFfi,
      );

  /// 归档后重新扫一遍 —— 「重启后的新进程看到什么」就是这样。
  Future<DatabaseScan> rescan() => scan();

  List<String> bakFilesIn(String directory) => [
    for (final entity in Directory(directory).listSync())
      if (p.basename(entity.path).contains('.bak-')) p.basename(entity.path),
  ];

  group('扫描：数一数盘上有几份（三处取并集）', () {
    test('三处都没有库 → 0 份，交给「应用数据目录新建」', () async {
      final result = await scan();
      expect(result.isEmpty, isTrue);
      expect(result.sole, isNull);
      expect(result.isAmbiguous, isFalse);
      expect(result.target, isNull);
    });

    test('只有应用数据目录有一份 → 就是它，不用搬也不用问', () async {
      await makeDatabase(dbAt(target), rows: 3);
      final result = await scan();
      expect(result.placements, hasLength(1));
      expect(result.sole!.directory, target);
      expect(result.isAmbiguous, isFalse);
    });

    test('只有 cwd 落点有一份 → sole 就是它（搬迁源）', () async {
      await makeDatabase(dbAt(cwdDir), rows: 3);
      final result = await scan();
      expect(result.sole!.directory, cwdDir);
      expect(result.target, isNull);
    });

    test('只有 exe 旁边有一份 → 也算数（以前这个位置完全看不见）', () async {
      await makeDatabase(dbAt(exeDbDir), rows: 3);
      final result = await scan();
      expect(result.sole!.directory, exeDbDir);
      expect(result.isAmbiguous, isFalse);
    });

    test('应用数据目录 + 一个候选 → 两份', () async {
      await makeDatabase(dbAt(target), rows: 1);
      await makeDatabase(dbAt(cwdDir), rows: 2);
      final result = await scan();
      expect(result.placements, hasLength(2));
      expect(result.isAmbiguous, isTrue);
      // 应用数据目录那份排在最前：UI 的推荐位与 sole 的取法都按这个顺序。
      expect(result.placements.first.directory, target);
      expect(result.others.map((e) => e.directory), [cwdDir]);
    });

    test('应用数据目录还空着、但两个候选各有一份 → 仍然是「两份」', () async {
      // 回归：老判据是「目标存在 且 至少一个候选也有库」，这种情况会被判成没冲突，
      // 然后静默搬一份上去，另一份永远躺在原地。
      await makeDatabase(dbAt(cwdDir), rows: 1);
      await makeDatabase(dbAt(exeDbDir), rows: 2);
      final result = await scan();
      expect(result.target, isNull);
      expect(result.isAmbiguous, isTrue);
      expect(result.placements, hasLength(2));
    });

    test('重复候选、以及与目标重合的候选 → 去重（同一处不算两份）', () async {
      await makeDatabase(dbAt(target), rows: 1);
      // 同一个目录写两遍、以及把应用数据目录本身当候选：都只算一份。
      final result = await scan([target, cwdDir, cwdDir]);
      expect(result.placements, hasLength(1));
      expect(result.sole!.directory, target);
      expect(result.isAmbiguous, isFalse);
    });

    test('0 字节主库、以及只有旁文件 → 都不算一份', () async {
      await File(dbAt(cwdDir)).writeAsBytes(const []);
      await File('${dbAt(exeDbDir)}-wal').writeAsString('x');
      final result = await scan();
      expect(result.isEmpty, isTrue);
    });

    test('describe() 带上份数与每份的位置（排查「莫名弹框」看这行）', () async {
      await makeDatabase(dbAt(target), rows: 1);
      await makeDatabase(dbAt(cwdDir), rows: 1);
      final text = (await scan()).describe();
      expect(text, contains('2 份'));
      expect(text, contains(target));
      expect(text, contains(cwdDir));
    });
  });

  group('预检：能自动办的就别问用户', () {
    test('只有一份 → 直接放行，且一个文件都不动', () async {
      await makeDatabase(dbAt(cwdDir), rows: 3);
      expect(await preflight(), isNull);
      expect(File(dbAt(cwdDir)).existsSync(), isTrue);
      expect(bakFilesIn(cwdDir), isEmpty);
    });

    test('两份都能读 → 交给用户选，每份都带行数', () async {
      await makeDatabase(dbAt(target), rows: 2);
      await makeDatabase(dbAt(cwdDir), rows: 5);
      final result = await preflight();
      expect(result, isNotNull);
      expect(result!.placements, hasLength(2));
      for (final placement in result.placements) {
        expect(
          placement.readable,
          isTrue,
          reason: '${placement.directory} 应该能读',
        );
      }
      expect(result.target!.stats!.countOf('favorite'), 2);
      expect(result.others.single.stats!.countOf('favorite'), 5);
      // 还没选，什么都不该动。
      expect(File(dbAt(target)).existsSync(), isTrue);
      expect(File(dbAt(cwdDir)).existsSync(), isTrue);
    });

    test('只有一份能读 → 不打扰用户，把读不出来的那份改名归档', () async {
      await makeDatabase(dbAt(target), rows: 4);
      await makeGarbage(dbAt(cwdDir));
      expect(await preflight(), isNull);
      expect(File(dbAt(target)).existsSync(), isTrue, reason: '好那份必须留在原地');
      expect(File(dbAt(cwdDir)).existsSync(), isFalse);
      expect(bakFilesIn(cwdDir), hasLength(1));
    });

    test('两份都读不出来 → 全部改名归档（让 App 干净地新建），也不问用户', () async {
      // 目标位置那份读不出来却留在原地的话，openDatabase 会直接撞上它。
      await makeGarbage(dbAt(target));
      await makeGarbage(dbAt(cwdDir));
      expect(await preflight(), isNull);
      expect(File(dbAt(target)).existsSync(), isFalse);
      expect(File(dbAt(cwdDir)).existsSync(), isFalse);
      expect(bakFilesIn(target), hasLength(1));
      expect(bakFilesIn(cwdDir), hasLength(1));
    });

    test('扫描与探查都不会建出目标目录（只读语义）', () async {
      final missing = p.join(root.path, 'not-yet');
      await makeDatabase(dbAt(cwdDir), rows: 1);
      await makeDatabase(dbAt(exeDbDir), rows: 1);
      final result = await preflightDatabasePlacement(
        candidateDirectories: [cwdDir, exeDbDir],
        targetDirectory: missing,
        databaseFileName: dbName,
        factory: databaseFactoryFfi,
      );
      // 两份都能读（探查跑过了）—— 但探查只碰系统临时目录，绝不碰这个不存在的落点。
      expect(result, isNotNull);
      expect(result!.readable, hasLength(2));
      expect(Directory(missing).existsSync(), isFalse);
    });
  });

  group('应用选择：落败的改名归档，绝不删除', () {
    test('选应用数据目录那份 → 候选那份整组归档（含旁文件）', () async {
      await makeDatabase(dbAt(target), rows: 2);
      await makeDatabase(dbAt(cwdDir), rows: 9);
      await File('${dbAt(cwdDir)}-wal').writeAsString('wal');

      final current = (await preflight())!;
      final failures = await applyDatabaseChoice(
        scan: current,
        winner: current.target!,
      );

      expect(failures, isEmpty);
      expect(File(dbAt(target)).existsSync(), isTrue);
      expect(File(dbAt(cwdDir)).existsSync(), isFalse);
      expect(File('${dbAt(cwdDir)}-wal').existsSync(), isFalse);
      // 旁文件跟着主库的归档前缀走，不会留在原地当孤儿。
      expect(bakFilesIn(cwdDir).where((n) => n.endsWith('-wal')), hasLength(1));
    });

    test('选候选那份 → 应用数据目录那份归档，赢家留在原处', () async {
      await makeDatabase(dbAt(target), rows: 2);
      await makeDatabase(dbAt(cwdDir), rows: 9);

      final current = (await preflight())!;
      final winner = current.others.single;
      final failures = await applyDatabaseChoice(scan: current, winner: winner);

      expect(failures, isEmpty);
      expect(File(dbAt(target)).existsSync(), isFalse);
      expect(bakFilesIn(target), hasLength(1));
      // 赢家不动：下一次启动它是唯一一份，会被搬进应用数据目录。
      expect(File(dbAt(cwdDir)).existsSync(), isTrue);
    });

    test('归档名带时间戳，且绝不覆盖已有的归档', () async {
      await makeDatabase(dbAt(target), rows: 1);
      await makeDatabase(dbAt(cwdDir), rows: 1);
      var current = (await preflight())!;
      await applyDatabaseChoice(scan: current, winner: current.target!);
      final first = bakFilesIn(cwdDir);

      // 用户又把一份库放回同一个候选落点，再选一次。
      await makeDatabase(dbAt(cwdDir), rows: 1);
      current = (await preflight())!;
      await applyDatabaseChoice(scan: current, winner: current.target!);

      expect(bakFilesIn(cwdDir), hasLength(2));
      expect(bakFilesIn(cwdDir).toSet(), hasLength(2), reason: '两次归档不能重名');
      expect(first, hasLength(1));
    });

    test('归档失败只记账，不改赢家、也不抛', () async {
      await makeDatabase(dbAt(target), rows: 1);
      await makeDatabase(dbAt(cwdDir), rows: 1);
      final current = (await preflight())!;
      final ghost = DatabasePlacement(
        directory: p.join(root.path, 'gone'),
        group: DatabaseFileGroup(
          mainPath: p.join(root.path, 'gone', dbName),
          sidecarPaths: const [],
          size: 1,
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );

      final failures = await applyDatabaseChoice(
        scan: DatabaseScan(
          placements: [current.target!, ...current.others, ghost],
          targetDirectory: target,
        ),
        winner: current.target!,
      );
      // 候选那份归档成功、幽灵那份失败：失败的只记账，赢家不受影响。
      expect(failures, [ghost.directory]);
      expect(File(dbAt(target)).existsSync(), isTrue);
      expect(bakFilesIn(cwdDir), hasLength(1));
    });
  });

  group('收敛：归档之后重扫只会看到一份', () {
    test('选应用数据目录那份 → 重扫只剩它，不再需要任何决策记录', () async {
      await makeDatabase(dbAt(target), rows: 2);
      await makeDatabase(dbAt(cwdDir), rows: 2);
      await makeDatabase(dbAt(exeDbDir), rows: 2);

      final current = (await preflight())!;
      expect(current.placements, hasLength(3));
      await applyDatabaseChoice(scan: current, winner: current.target!);

      final after = await rescan();
      expect(after.placements, hasLength(1));
      expect(after.sole!.directory, target);
      expect(after.isAmbiguous, isFalse);
      // 第二次启动（重启后的新进程）不会再有可问的东西。
      expect(await preflight(), isNull);
    });

    test('选候选那份 → 重扫只剩它，并且会被搬进应用数据目录', () async {
      await makeDatabase(dbAt(target), rows: 2);
      await makeDatabase(dbAt(cwdDir), rows: 7);

      final current = (await preflight())!;
      final winner = current.others.single;
      await applyDatabaseChoice(scan: current, winner: winner);

      final after = await rescan();
      expect(after.sole!.directory, cwdDir);

      // 这就是重启后新进程走的那条路：搬过去。
      final relocation = await relocateDatabase(
        legacyDirectory: after.sole!.directory,
        targetDirectory: target,
        databaseFileName: dbName,
      );
      expect(relocation.migrated, isTrue);
      expect(relocation.directory, target);

      final settled = await rescan();
      expect(settled.sole!.directory, target);
      // 被归档的是原来在应用数据目录的那一份，所以 .bak 落在 target 那边。
      expect(bakFilesIn(target), hasLength(1));
      expect(bakFilesIn(cwdDir), isEmpty);
    });

    test('选 exe 旁边那份 → 搬迁源是它，不是 sqflite 算出来的那个目录', () async {
      // cwd 落点一份都没有，只有 exe 旁边（= `<exe>/.dart_tool/.../databases`）有：
      // 只认 getDatabasesPath() 算出来的那个目录、或者把「exe 旁边」当成 exe 目录
      // 本身的实现，都会一份都看不见，然后在应用数据目录开一个空库。
      await makeDatabase(dbAt(target), rows: 2);
      await makeDatabase(dbAt(exeDbDir), rows: 7);

      final current = (await preflight())!;
      final winner = current.others.single;
      expect(winner.directory, exeDbDir);
      await applyDatabaseChoice(scan: current, winner: winner);

      final after = await rescan();
      expect(after.sole!.directory, exeDbDir);
      final relocation = await relocateDatabase(
        legacyDirectory: after.sole!.directory,
        targetDirectory: target,
        databaseFileName: dbName,
      );
      expect(relocation.migrated, isTrue);
      expect(File(dbAt(target)).existsSync(), isTrue);
    });
  });

  group('候选落点：两个都必须落在 sqflite 的 databases 目录那一层', () {
    // 这一组钉死的是「宿主事实 → 候选目录」这段接缝。它曾经错成
    // `p.dirname(getDatabasesPath())`（削掉了 databases 那一层）+ exe 目录本身，
    // 两个候选都打不中真实文件 —— 三份库的机器上只扫得出应用数据目录那一份，
    // 另外两份（用户真正的数据）既没人问也没人搬，App 直接打开了一份旧库。
    late String project;
    late String cwdDatabases;
    late String buildExe;
    late String appData;

    List<String> candidatesFor(String sqflitePath, {String? current}) =>
        legacyDatabaseCandidates(
          sqfliteDatabasesPath: sqflitePath,
          currentDirectory: current ?? project,
          executableDirectory: buildExe,
          targetDirectory: appData,
        );

    setUp(() {
      project = p.join(root.path, 'proj');
      cwdDatabases = sqfliteLayoutIn(project);
      buildExe = p.join(project, 'build', 'windows', 'x64', 'runner', 'Debug');
      appData = p.join(root.path, 'appdata');
    });

    test('cwd 那个不再被削一层，exe 那个带上 sqflite 的布局', () {
      expect(candidatesFor(cwdDatabases), [
        cwdDatabases,
        sqfliteLayoutIn(buildExe),
      ]);
    });

    test('两个候选打的都是真文件：exe 旁边那份能被扫出来', () async {
      await makeDatabase(dbAt(cwdDatabases), rows: 3);
      await makeDatabase(dbAt(sqfliteLayoutIn(buildExe)), rows: 5);

      final result = await scan(candidatesFor(cwdDatabases));
      expect(result.placements.map((placement) => placement.directory), [
        cwdDatabases,
        sqfliteLayoutIn(buildExe),
      ]);
      expect(result.isAmbiguous, isTrue);
    });

    test('应用数据目录还空着、两份都在候选侧 → 仍然是「不止一份」', () async {
      // 老判据「目标存在 且 至少一个候选也有库」在这里会判成没冲突，
      // 然后静默搬一份上去、另一份永远躺着。
      await makeDatabase(dbAt(cwdDatabases), rows: 2);
      await makeDatabase(dbAt(sqfliteLayoutIn(buildExe)), rows: 9);

      final result = await preflight(candidatesFor(cwdDatabases));
      expect(result, isNotNull);
      expect(result!.target, isNull);
      expect(result.others, hasLength(2));
    });

    test('候选与应用数据目录重合时去掉，不留重复项', () {
      // 用户把数据目录指到了旧落点：sqflite 算出来的恰好就是应用数据目录，
      // 那个候选要被剔掉（cwd 取 root，好让 appData 落在它底下）。
      final result = candidatesFor(appData, current: root.path);
      expect(result, isNot(contains(appData)));
      expect(result, hasLength(1));
    });

    test('两个候选重合（cwd 就是 exe 目录）→ 去重成一条', () {
      final exeDatabases = sqfliteLayoutIn(buildExe);
      expect(candidatesFor(exeDatabases, current: buildExe), [exeDatabases]);
    });

    test('sqflite 落点不在 cwd 之下（跨盘符等）→ 只留它自己，不瞎猜 exe 那边', () {
      final elsewhere = sqfliteLayoutIn(p.join(root.path, 'elsewhere'));
      expect(candidatesFor(elsewhere), [elsewhere]);
    });
  });

  group('探查口径', () {
    test('inspectDatabaseScan 给每一份都填上行数，读不出来的留 null', () async {
      await makeDatabase(dbAt(target), rows: 4);
      await makeGarbage(dbAt(cwdDir));
      final inspected = await inspectDatabaseScan(
        await scan(),
        factory: databaseFactoryFfi,
      );

      expect(inspected.placements, hasLength(2));
      expect(inspected.target!.readable, isTrue);
      expect(inspected.target!.stats!.countOf('playlist'), 4);
      expect(inspected.target!.rowTotal, 20);
      expect(inspected.others.single.readable, isFalse);
      // 「读不出来」的要能被推荐逻辑跳过。
      expect(inspected.readable, hasLength(1));
      expect(inspected.readable.single.directory, target);
    });
  });
}
