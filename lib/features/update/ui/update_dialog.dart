import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bilimusic/features/update/models/changelog_entry.dart';
import 'package:bilimusic/features/update/update_installer.dart';
import 'package:bilimusic/features/update/ui/notification_permission.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 更新弹窗：展示更新日志，并在"立即更新"时执行应用内更新
/// （Android 走系统下载 + 安装页，桌面端下载 zip 换血重启）。
/// 不支持应用内更新的平台（Web/macOS）保持原行为：打开 Releases 页面。
class UpdateAvailableDialog extends StatefulWidget {
  final String newVersion;
  final List<ChangelogEntry> changelog;

  const UpdateAvailableDialog({
    super.key,
    required this.newVersion,
    required this.changelog,
  });

  static Future<void> show(
    BuildContext context, {
    required String newVersion,
    required List<ChangelogEntry> changelog,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          UpdateAvailableDialog(newVersion: newVersion, changelog: changelog),
    );
  }

  @override
  State<UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

enum _InstallStage { idle, installing, androidStarted, error }

class _UpdateAvailableDialogState extends State<UpdateAvailableDialog> {
  _InstallStage _stage = _InstallStage.idle;
  UpdatePhase? _phase;
  int _receivedBytes = 0;
  int? _totalBytes;
  String? _errorText;

  /// 通知权限是否可用（Android 更新前检查的结果），
  /// 决定“已开始后台下载”提示里要不要提通知栏
  bool _notificationPermissionGranted = true;

  bool get _installing => _stage == _InstallStage.installing;

  Future<void> _launchUpdateUrl() async {
    final url = Uri.parse('https://github.com/NaivG/bilimusic/releases');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _startInstall() async {
    if (_installing) return;
    // 不支持应用内更新的平台保持原有行为：打开 Releases 页面
    if (!UpdateInstaller.instance.isSupported) {
      Navigator.of(context).pop();
      await _launchUpdateUrl();
      return;
    }
    // Android 13+ 的下载进度走系统通知，更新前先确认通知权限
    final decision = await checkNotificationPermissionBeforeUpdate(context);
    if (!mounted) return;
    if (decision == UpdateNotificationDecision.aborted) return;
    setState(() {
      _stage = _InstallStage.installing;
      _errorText = null;
      _phase = null;
      _receivedBytes = 0;
      _totalBytes = null;
      _notificationPermissionGranted =
          decision == UpdateNotificationDecision.granted;
    });
    try {
      await UpdateInstaller.instance.install(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _phase = progress.phase;
            _receivedBytes = progress.receivedBytes;
            _totalBytes = progress.totalBytes;
          });
        },
        onError: (message) {
          if (!mounted) return;
          setState(() {
            _stage = _InstallStage.error;
            _errorText = message;
          });
        },
      );
      // Android：已移交系统后台下载，完成后插件会自动拉起安装页；
      // 桌面端成功后进程直接被替换重启，不会执行到这里
      if (!mounted) return;
      setState(() => _stage = _InstallStage.androidStarted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _InstallStage.error;
        _errorText = e.toString();
      });
    }
  }

  String _phaseLabel(UpdatePhase phase) {
    switch (phase) {
      case UpdatePhase.resolving:
        return '正在获取更新信息…';
      case UpdatePhase.downloading:
        return '正在下载更新…';
      case UpdatePhase.verifying:
        return '正在校验更新包…';
      case UpdatePhase.extracting:
        return '正在解压更新…';
      case UpdatePhase.restarting:
        return '即将重启应用…';
    }
  }

  String _bytesLabel(int? bytes) {
    if (bytes == null) return '';
    final mb = bytes / 1024 / 1024;
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_installing,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        backgroundColor: colorScheme.surfaceContainerHighest,
        icon: Icon(Icons.system_update, size: 48, color: colorScheme.primary),
        title: Text('发现新版本 v${widget.newVersion}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '以下是本次更新内容：',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              // 更新日志条目可能很多，包一层可滚动容器避免撑爆弹窗高度；
              // Flexible 限定日志区域最多占弹窗剩余高度，内容少时仍自适应
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.changelog
                        .map(
                          (entry) => _buildChangelogItem(entry, colorScheme),
                        )
                        .toList(),
                  ),
                ),
              ),
              if (_stage != _InstallStage.idle) ...[
                const Divider(height: 24),
                _buildStatusSection(colorScheme),
              ],
            ],
          ),
        ),
        actions: _buildActions(colorScheme),
      ),
    );
  }

  Widget _buildStatusSection(ColorScheme colorScheme) {
    switch (_stage) {
      case _InstallStage.installing:
        final phase = _phase;
        final determinate = _totalBytes != null && _totalBytes! > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: phase == UpdatePhase.downloading && determinate
                  ? (_receivedBytes / _totalBytes!).clamp(0.0, 1.0).toDouble()
                  : null,
              minHeight: 4,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              // 弹窗背景是 surfaceContainerHighest，与 M3 进度条默认轨道色
              // 相同，不加显式颜色时进度条会整个融进背景里
              color: colorScheme.primary,
              backgroundColor: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.15,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    phase == null ? '' : _phaseLabel(phase),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (phase == UpdatePhase.downloading)
                  Text(
                    '${_bytesLabel(_receivedBytes)}'
                    '${_totalBytes != null ? ' / ${_bytesLabel(_totalBytes)}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        );
      case _InstallStage.androidStarted:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _notificationPermissionGranted
                    ? '已开始后台下载更新，完成后将自动弹出安装界面，可在通知栏查看进度。'
                    : '已开始后台下载更新，完成后将自动弹出安装界面。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      case _InstallStage.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '更新失败：${_errorText ?? '未知错误'}',
                style: TextStyle(fontSize: 12, color: colorScheme.error),
              ),
            ),
          ],
        );
      case _InstallStage.idle:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildActions(ColorScheme colorScheme) {
    switch (_stage) {
      case _InstallStage.installing:
        return [];
      case _InstallStage.androidStarted:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ];
      case _InstallStage.idle:
      case _InstallStage.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '暂不更新',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: _startInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
            ),
            child: Text(_stage == _InstallStage.error ? '重试' : '立即更新'),
          ),
        ];
    }
  }

  Widget _buildChangelogItem(ChangelogEntry entry, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${entry.version}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.date,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...entry.changes.map(
            (change) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(fontSize: 12, color: colorScheme.primary),
                  ),
                  Expanded(
                    child: Text(
                      change,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
