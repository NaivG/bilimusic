import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:bilimusic/core/storage/database_path_migration.dart';

/// 旧落点搬迁的行为密封测试。
void main() {
  const dbName = 'playlist.db';

  late Directory root;
  late String legacy;
  late String target;

  String dbIn(String dir) => p.join(dir, dbName);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bilimusic_relocate_');
    legacy = p.join(root.path, 'legacy');
    target = p.join(root.path, 'target');
    await Directory(legacy).create(recursive: true);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<void> writeFile(String path, String content) async {
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsString(content);
  }

  Future<DatabaseRelocation> relocate() => relocateDatabase(
    legacyDirectory: legacy,
    targetDirectory: target,
    databaseFileName: dbName,
  );

  test('旧落点有库、目标为空 → 搬到目标，源文件不残留', () async {
    await writeFile(dbIn(legacy), 'DB-CONTENT');

    final result = await relocate();

    expect(result.migrated, isTrue);
    expect(result.directory, target);
    expect(File(dbIn(target)).readAsStringSync(), 'DB-CONTENT');
    expect(File(dbIn(legacy)).existsSync(), isFalse);
  });

  test('旁文件跟着主库一起搬（WAL 里可能还有已提交的事务）', () async {
    await writeFile(dbIn(legacy), 'DB-CONTENT');
    await writeFile('${dbIn(legacy)}-wal', 'WAL-CONTENT');

    final result = await relocate();

    expect(result.migrated, isTrue);
    expect(File(dbIn(target)).readAsStringSync(), 'DB-CONTENT');
    expect(File('${dbIn(target)}-wal').readAsStringSync(), 'WAL-CONTENT');
    expect(File('${dbIn(legacy)}-wal').existsSync(), isFalse);
  });

  test('旧落点没有库 → 不搬，直接用目标目录', () async {
    final result = await relocate();

    expect(result.migrated, isFalse);
    expect(result.directory, target);
    expect(Directory(target).existsSync(), isFalse, reason: '不该顺手建空目录');
  });

  test('两个目录相同时直接返回，不做任何事', () async {
    final result = await relocateDatabase(
      legacyDirectory: legacy,
      targetDirectory: p.join(legacy, '.'),
      databaseFileName: dbName,
    );

    expect(result.migrated, isFalse);
    expect(result.directory, p.normalize(legacy));
  });

  test('目标已有非空库 → 保留目标，绝不用旧库覆盖', () async {
    await writeFile(dbIn(legacy), 'OLD');
    await writeFile(dbIn(target), 'CURRENT');

    final result = await relocate();

    expect(result.migrated, isFalse);
    expect(result.directory, target);
    expect(File(dbIn(target)).readAsStringSync(), 'CURRENT');
    expect(File(dbIn(legacy)).readAsStringSync(), 'OLD', reason: '旧库保持原样');
  });

  test('目标是 0 字节残渣 → 视为没有，照搬旧库', () async {
    await writeFile(dbIn(legacy), 'REAL');
    await writeFile(dbIn(target), '');

    final result = await relocate();

    expect(result.migrated, isTrue);
    expect(File(dbIn(target)).readAsStringSync(), 'REAL');
  });

  test('重复调用幂等：第二次不再搬，目标内容不变', () async {
    await writeFile(dbIn(legacy), 'DB-CONTENT');

    final first = await relocate();
    final second = await relocate();

    expect(first.migrated, isTrue);
    expect(second.migrated, isFalse);
    expect(second.directory, target);
    expect(File(dbIn(target)).readAsStringSync(), 'DB-CONTENT');
  });

  test('目标目录建不出来 → 回退旧落点，不在新地方开空库', () async {
    await writeFile(dbIn(legacy), 'DB-CONTENT');
    // 目标路径被一个同名文件占住，Directory.create 必然失败。
    await writeFile(target, 'not a directory');

    final result = await relocate();

    expect(result.migrated, isFalse);
    expect(result.directory, legacy, reason: '搬不动就必须继续用旧落点');
    expect(File(dbIn(legacy)).readAsStringSync(), 'DB-CONTENT');
  });

  test('搬到一半失败 → 已搬走的旁文件回滚，库仍开在旧落点', () async {
    await writeFile(dbIn(legacy), 'DB-CONTENT');
    await writeFile('${dbIn(legacy)}-wal', 'WAL-CONTENT');
    // 旁文件能搬，主库的目的地被一个同名目录占住 → 主库这步必失败。
    await Directory(dbIn(target)).create(recursive: true);

    final result = await relocate();

    expect(result.migrated, isFalse);
    expect(result.directory, legacy);
    expect(File(dbIn(legacy)).readAsStringSync(), 'DB-CONTENT');
    expect(
      File('${dbIn(legacy)}-wal').readAsStringSync(),
      'WAL-CONTENT',
      reason: '旁文件要跟着回滚，否则旧库下次打开会缺 WAL',
    );
    expect(File('${dbIn(target)}-wal').existsSync(), isFalse);
  });
}
