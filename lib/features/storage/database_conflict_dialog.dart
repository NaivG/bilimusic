import 'package:flutter/material.dart';
import 'package:restart_app/restart_app.dart';

import 'package:bilimusic/core/storage/database_conflict.dart';
import 'package:bilimusic/core/storage/database_conflict_resolver.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';

/// 盘上有不止一份能读的库时，**先问用户，再重启**。
///
/// 这个 shell 是 `runApp` 的根：那一刻真正的 App 还**没有被构造** —— 没有
/// `ProviderContainer`、没有播放器、没有音频服务、没有托盘。这不是顺手为之，而是
/// 这套流程的关键：
/// - 重启进程时没有任何状态要收（`RestartMode.process` 是硬退出，不做析构）；
/// - 改名归档发生时**没有任何东西持有那些 `.db`** —— Windows 上 rename 一个被自己
///   打开的文件是要失败的。
///
/// 用户选完之后：`applyDatabaseChoice` 把落败的每一份整组改名归档 → **重启进程**
/// → 新进程重新扫一遍，只会看到一份，于是走最朴素的「搬过去 / 打开」。所以这里
/// 不需要决策记录、不需要指纹校验，**盘上的状态自己就是记录**。
///
/// 重启不是 100% 可靠（`restart_app` 在真正 spawn 之前就把 `success: true` 回了
/// Dart，spawn 失败时旧进程照旧活着），所以这里按「这行之后的代码还会不会跑」来判断，
/// 跑到了就切到「请手动重新打开」—— 把兜底留在这个 shell 里，而不是去复制一份 App
/// 初始化路径。
///
/// **不做「不重启、就地继续启动」那条分支**（`kDebugMode` 下曾经有，代号
/// `onResolvedLocally`）：归档刚做完、盘上还没收敛就让常规启动路径去扫落点，等于把
/// 「重启后重扫一遍」这个唯一可靠的收敛点拆掉，和搬迁的时序打架。现在 debug 也照常
/// 重启；重启不成只有「请手动重新打开」一条路。
class DatabaseConflictShell extends StatefulWidget {
  const DatabaseConflictShell({super.key, required this.scan});

  /// 预检扫出来的现场，每份都带上了只读探查的行数。
  final DatabaseScan scan;

  /// 归档完成后等这么久还活着，就当作「没重启成」。
  static const Duration restartGrace = Duration(seconds: 3);

  @override
  State<DatabaseConflictShell> createState() => _DatabaseConflictShellState();
}

class _DatabaseConflictShellState extends State<DatabaseConflictShell> {
  bool _deciding = false;
  bool _restartFailed = false;
  List<String> _archiveFailures = const [];

  @override
  Widget build(BuildContext context) {
    // 这时候 settingsProvider 还没建起来，用默认主题 + 跟随系统明暗。
    final descriptor = ThemeRegistry.defaultTheme;
    return MaterialApp(
      title: 'BiliMusic',
      debugShowCheckedModeBanner: false,
      theme: descriptor.light(),
      darkTheme: descriptor.dark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _restartFailed
                  ? _buildRestartFailed(context)
                  : _buildAsk(context),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- 问用户 ----------------

  Widget _buildAsk(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scan = widget.scan;
    final recommended = _recommend(scan);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '发现 ${scan.placements.length} 份音乐数据',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '检测到冲突的数据库文件且均有效，请选择一个保留为应用数据库。'
              '没被选中的会备份并留在它原来的目录里，不会删除。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final placement in scan.placements) ...[
              _PlacementCard(
                placement: placement,
                label:
                    scan.target != null &&
                        placement.directory == scan.target!.directory
                    ? '应用数据目录'
                    : '其它落点（旧落点）',
                recommended:
                    recommended != null &&
                    placement.directory == recommended.directory,
                enabled: !_deciding && placement.readable,
                onUse: () => _decide(placement),
              ),
              const SizedBox(height: 12),
            ],
            if (_deciding) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '正在归档未选中的数据库并重启…',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 推荐哪一份：应用数据目录那份读得出来的话就是它（那是 App 的正式落点，
  /// 重装、更新、换启动方式都不丢）；否则推荐读到的记录最多的那份。
  DatabasePlacement? _recommend(DatabaseScan scan) {
    final target = scan.target;
    if (target != null && target.readable) return target;
    final readable = scan.readable;
    if (readable.isEmpty) return null;
    return readable.reduce((a, b) => b.rowTotal > a.rowTotal ? b : a);
  }

  // ---------------- 决定 ----------------

  Future<void> _decide(DatabasePlacement winner) async {
    if (_deciding) return;
    setState(() => _deciding = true);

    final failures = await applyDatabaseChoice(
      scan: widget.scan,
      winner: winner,
      onLog: (message) => debugPrint('[AppDatabase] $message'),
    );
    _archiveFailures = failures;

    await _restart();
  }

  /// 重启进程；**代码还能往下跑就说明没重启成**（见类文档）。
  Future<void> _restart() async {
    await Restart.restartApp(mode: RestartMode.process);
    await Future<void>.delayed(DatabaseConflictShell.restartGrace);
    if (!mounted) return;
    setState(() {
      _deciding = false;
      _restartFailed = true;
    });
  }

  // ---------------- 重启没成 ----------------

  Widget _buildRestartFailed(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failures = _archiveFailures;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('已经处理好了', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              '选中的那份留在原处（下次启动会搬进应用数据目录），其余的都改名成了 '
              '.bak 放在它们各自的目录里，没有删除。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '有 ${failures.length} 份没能改名（可能被别的程序占用），'
                '已留在原处，下次启动会再问你一次。',
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '自动重启没有成功，请手动重新打开 BiliMusic。',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _restartFailed = false;
                    _deciding = true;
                  });
                  _restart();
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('再试一次'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一份库的展示卡片：位置、路径、大小、时间、各表行数，以及「用这份」。
class _PlacementCard extends StatelessWidget {
  const _PlacementCard({
    required this.placement,
    required this.label,
    required this.recommended,
    required this.enabled,
    required this.onUse,
  });

  final DatabasePlacement placement;
  final String label;
  final bool recommended;
  final bool enabled;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = placement.stats;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(
          color: recommended
              ? colorScheme.primary.withValues(alpha: 0.6)
              : colorScheme.outlineVariant,
          width: recommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recommended ? '$label（推荐）' : label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (rows == null)
                _Chip(text: '读不出来', color: colorScheme.error)
              else if (rows.isShell)
                _Chip(text: '空的', color: colorScheme.error)
              else
                _Chip(
                  text: _sizeLabel(placement.group.size),
                  color: colorScheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            placement.group.mainPath,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Consolas',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_sizeLabel(placement.group.size)} · 最后修改 '
            '${_formatTime(placement.group.modifiedAt)}',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (rows == null)
            Text(
              '行数读不出来（可能正被占用、权限不足，或者是更新版本的库），'
              '不建议选它',
              style: TextStyle(fontSize: 12, color: colorScheme.error),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final entry in databaseInspectTables)
                  _CountChip(
                    label: entry.label,
                    count: rows.countOf(entry.table),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: enabled ? onUse : null,
              child: const Text('用这份'),
            ),
          ),
        ],
      ),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  static String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final value = count == null ? '—' : '$count';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
