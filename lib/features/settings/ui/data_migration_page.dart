import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restart_app/restart_app.dart';

import '../../../app/app_providers.dart';
import '../logic/data_migration_helper.dart';

class DataMigrationPage extends ConsumerStatefulWidget {
  const DataMigrationPage({super.key});

  @override
  ConsumerState<DataMigrationPage> createState() => _DataMigrationPageState();
}

class _DataMigrationPageState extends ConsumerState<DataMigrationPage> {
  late final DataMigrationHelper _helper;

  bool _isExporting = false;
  bool _isImporting = false;
  String _statusMessage = '';
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _helper = DataMigrationHelper(
      playlistService: ref.read(playlistServiceProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AutoAppBar.generateAppBar(context: context, title: '数据迁移'),
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '数据迁移向导',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '导出或导入您的应用数据',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 32),

              // 数据说明
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '迁移的数据包括：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const BulletPoint(text: '用户设置（外观、播放、音效与音频输出等）'),
                      const BulletPoint(text: '播放历史与收藏列表'),
                      const BulletPoint(text: '用户创建的播放列表与自定义标签'),
                      const BulletPoint(text: '当前播放队列'),
                      const BulletPoint(text: '音量与 DSP 音效配置'),
                      const BulletPoint(text: '口味画像（KV Cache）与收藏夹同步状态'),
                      const BulletPoint(text: '登录 Cookie 与 refresh token'),
                      const SizedBox(height: 16),
                      Text(
                        '注意：缓存数据、离线音频、局域网配对信息不会被迁移',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 导出数据
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '导出数据',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('将所有应用数据导出为一个文件，以便在其他设备上导入'),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportData,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('导出数据'),
                        ),
                      ),
                      if (_isExporting) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _statusIsError
                                  ? Theme.of(context).colorScheme.error
                                  : _statusMessage.contains('成功')
                                  ? Colors.green
                                  : Theme.of(context).hintColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 导入数据
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '导入数据',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('从之前导出的数据文件导入应用数据'),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _isImporting ? null : _importData,
                          icon: const Icon(Icons.download),
                          label: const Text('导入数据'),
                        ),
                      ),
                      if (_isImporting) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 注意事项
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '注意事项',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      BulletPoint(
                        text: '导入数据将覆盖当前应用数据',
                        textColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                      BulletPoint(
                        text: '导入完成后建议重启应用以确保所有设置生效',
                        textColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                      BulletPoint(
                        text: '请妥善保管导出的数据文件',
                        textColor: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 导出 ──────────────────────────────────────────────────────────────

  Future<void> _exportData() async {
    if (_isExporting) return;
    setState(() {
      _isExporting = true;
      _statusIsError = false;
      _statusMessage = '正在导出数据...';
    });

    try {
      final path = await _helper.exportToFile();
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _statusMessage = path == null ? '导出已取消' : '导出成功！文件已保存到：$path';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _statusIsError = true;
        _statusMessage = '导出失败: $e';
      });
    }
  }

  // ── 导入 ──────────────────────────────────────────────────────────────

  Future<void> _importData() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);

    try {
      final backup = await _helper.pickBackupFile();
      if (backup == null) {
        _showMessage('已取消导入');
        return;
      }
      if (!mounted) return;

      // 版本异常与覆盖确认合成一次弹窗，避免连续两次打断用户。
      final warning = _compatibilityWarning(backup.compatibility);
      final confirmed = await _confirm(
        warning?.title ?? '导入数据',
        warning?.message ??
            '导入将覆盖当前设置、登录状态、歌单、播放历史、收藏与播放队列，'
                '且无法撤销。\n\n确定继续吗？',
      );
      if (!confirmed) {
        _showMessage('已取消导入');
        return;
      }

      await _helper.restore(backup.data);
      if (!mounted) return;
      setState(() => _isImporting = false);
      await _showRestartDialog();
    } on DataMigrationFormatException catch (e) {
      _showMessage('文件无法识别: ${e.message}');
    } catch (e) {
      _showMessage('导入失败: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  ({String title, String message})? _compatibilityWarning(
    BackupCompatibility compatibility,
  ) {
    if (compatibility.newerFormat) {
      return (
        title: '备份格式较新',
        message:
            '该备份由更新版本的应用生成（格式 v${compatibility.formatVersion}，'
            '当前支持 v${DataMigrationHelper.formatVersion}），'
            '部分数据可能无法识别。\n\n'
            '继续导入将覆盖当前应用数据，是否继续？',
      );
    }
    if (compatibility.missingVersion) {
      return (
        title: '版本信息缺失',
        message:
            '导入的数据文件中不包含版本信息，可能存在兼容性问题，'
            '请确认是否选择了正确的数据文件。\n'
            '如果此文件是在 1.3.04 以下的版本导出的，请忽视此提示。\n\n'
            '继续导入将覆盖当前应用数据，是否继续？',
      );
    }
    if (compatibility.newerThanApp) {
      return (
        title: '数据版本不兼容',
        message:
            '导入的数据文件版本为 ${compatibility.dataVersionCode}，'
            '高于当前应用版本 ${compatibility.appVersionCode}，'
            '可能存在兼容性问题。\n\n'
            '继续导入将覆盖当前应用数据，是否继续？',
      );
    }
    return null;
  }

  Future<bool> _confirm(String title, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber),
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续导入'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _showRestartDialog() async {
    final shouldRestart = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入成功'),
          content: const Text('数据导入完成，建议重启应用以确保所有设置生效。是否现在重启？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后重启'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('立即重启'),
            ),
          ],
        );
      },
    );

    if (shouldRestart == true) {
      await Restart.restartApp(mode: RestartMode.process);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class BulletPoint extends StatelessWidget {
  final String text;
  final Color? textColor;

  const BulletPoint({super.key, required this.text, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: textColor)),
          Expanded(
            child: Text(text, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }
}
