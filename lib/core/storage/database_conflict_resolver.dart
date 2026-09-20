/// 落点冲突的**处置**：预检（能自动办的就办掉）与应用用户的选择。
///
/// 扫描在 `database_conflict.dart`（只 `stat`），探查在 `database_inspector.dart`
/// （只读副本），本文件负责「动手」——而整套设计里**唯一的动手动作就是改名归档**：
///
/// 1. [preflightDatabasePlacement]：盘上不止一份时逐份探查行数。
///    - 只有一份读得出来（其余读不出来）→ 把读不出来的那些归档，返回 null
///      （调用方照常走「搬迁 / 打开 / 新建」），用户完全不会被问；
///    - 不止一份读得出来 → 返回带行数的扫描结果，交给 UI 问。
/// 2. [applyDatabaseChoice]：用户选定后，把**没被选中的每一份**整组归档。
/// 3. 之后调用方**重启进程**（`restart_app`）：重启后重扫一遍只会看到一份，
///    于是走最朴素的「搬过去 / 打开」。
///
/// 为什么没有决策记录、没有指纹、也没有启动闸门：**重启就是记录**。归档之后盘上
/// 只剩一份，「上次选了哪份」这件事由文件系统自己回答；进程重启后重新扫一遍即可，
/// 不需要（也不该）在 SharedPreferences 里留一份需要校验是否「还成立」的状态。
/// 早先那版记「赢家目录 + 指纹」，判据一旦和归档动作的先后顺序错开，就会变成
/// **每次启动都重新问一遍**（用户实测报过这个 bug）。别再引入这类持久状态。
///
/// 为什么读不出来不删、只改名：**「打开失败」会有假阴性** —— 文件可能正被另一个
/// 实例占着（重启机制本身就有 ~200ms 的双进程窗口）、权限不足、在只读介质上、
/// WAL 没 checkpoint，或者属于更新版本的 schema。这些情况下删除是不可逆的数据
/// 丢失，改名最坏也只是一个 `.bak`。
library;

import 'dart:developer';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bilimusic/core/storage/database_conflict.dart';
import 'package:bilimusic/core/storage/database_file_ops.dart';
import 'package:bilimusic/core/storage/database_inspector.dart';

/// 预检结果：返回 null 表示「不用问用户，照常往下走」。
///
/// 返回非 null 时调用方必须把选择权交出去（弹窗），然后在用户选完之后调
/// [applyDatabaseChoice] 并重启进程。
Future<DatabaseScan?> preflightDatabasePlacement({
  required List<String> candidateDirectories,
  required String targetDirectory,
  required String databaseFileName,
  DatabaseFactory? factory,
  void Function(String message)? onLog,
}) async {
  final scan = await scanDatabasePlacements(
    candidateDirectories: candidateDirectories,
    targetDirectory: targetDirectory,
    databaseFileName: databaseFileName,
  );
  onLog?.call(scan.describe());

  // 0 份或 1 份：没有可问的，交给常规路径（新建 / 打开 / 搬过去）。
  if (!scan.isAmbiguous) return null;

  final inspected = await inspectDatabaseScan(scan, factory: factory);
  final readable = inspected.readable;

  // 不止一份读得出来 —— 这才是真正需要用户决定的情况。
  if (readable.length > 1) return inspected;

  // 读得出来的最多一份：不用问，把其余的让开，好那份留在原地。
  //
  // 一份都读不出来时同样走这里：目标位置那份读不出来却留在原地，开库会直接失败
  // （`openDatabase` 撞上一个坏文件），所以必须把它挪开，让 App 在应用数据目录
  // 里干净地新建一个。
  final winner = readable.isEmpty ? null : readable.first;
  for (final placement in inspected.placements) {
    if (winner != null && p.equals(placement.directory, winner.directory)) {
      continue;
    }
    await archivePlacement(placement, onLog: onLog);
  }
  onLog?.call(
    winner == null
        ? '落点扫描：${inspected.placements.length} 份都读不出来，已全部改名归档，本次新建'
        : '落点扫描：只有 ${winner.directory} 那份读得出来，其余已改名归档',
  );
  return null;
}

/// 用户选定 [winner] 之后：把其余每一份整组改名归档。
///
/// 返回归档失败的落点目录（通常为空）。**归档失败不改变用户的选择** ——
/// 赢家照用，失败的那份留在原地并在日志里留痕；下一次启动它会重新参与扫描。
Future<List<String>> applyDatabaseChoice({
  required DatabaseScan scan,
  required DatabasePlacement winner,
  void Function(String message)? onLog,
}) async {
  final failures = <String>[];
  for (final placement in scan.placements) {
    if (p.equals(placement.directory, winner.directory)) continue;
    final archived = await archivePlacement(placement, onLog: onLog);
    if (!archived) failures.add(placement.directory);
  }
  return failures;
}

/// 归档一处落点（整组）。返回是否成功；失败只留痕，不抛。
Future<bool> archivePlacement(
  DatabasePlacement placement, {
  void Function(String message)? onLog,
}) async {
  try {
    final archived = await archiveDatabaseGroup(placement.group.mainPath);
    onLog?.call('已归档 ${placement.directory} → $archived');
    return true;
  } catch (e) {
    log(
      '归档落败数据库失败（$e）：${placement.directory}；文件留在原地',
      name: 'AppDatabase',
      level: 900, // SEVERE
    );
    return false;
  }
}
