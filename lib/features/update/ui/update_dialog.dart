import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bilimusic/features/update/models/changelog_entry.dart';
import 'package:bilimusic/features/update/update_installer.dart';
import 'package:bilimusic/features/update/ui/notification_permission.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

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
    return showBmDialog<void>(
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
    return mb >= 1
        ? '${mb.toStringAsFixed(1)} MB'
        : '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_installing,
      child: BmDialog(
        title: '发现新版本 v${widget.newVersion}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '以下是本次更新内容：',
              style: context.bmType.body.copyWith(
                color: context.bmColors.textSecondary,
              ),
            ),
            const SizedBox(height: BmTokens.s3),
            for (final entry in widget.changelog) _buildChangelogItem(entry),
            if (_stage != _InstallStage.idle) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: BmTokens.s3),
                child: Container(
                  height: BmTokens.hairlineWidth,
                  color: context.bmColors.hairline,
                ),
              ),
              _buildStatusSection(),
            ],
          ],
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildStatusSection() {
    final colors = context.bmColors;
    final type = context.bmType;
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
              minHeight: BmTokens.s1,
              borderRadius: BmTokens.r4All,
              color: colors.accent,
              backgroundColor: colors.fillMuted,
            ),
            const SizedBox(height: BmTokens.s2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    phase == null ? '' : _phaseLabel(phase),
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                if (phase == UpdatePhase.downloading)
                  Text(
                    '${_bytesLabel(_receivedBytes)}'
                    '${_totalBytes != null ? ' / ${_bytesLabel(_totalBytes)}' : ''}',
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ],
        );
      case _InstallStage.androidStarted:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle,
              size: BmTokens.iconMenu,
              color: colors.success,
            ),
            const SizedBox(width: BmTokens.s2),
            Expanded(
              child: Text(
                _notificationPermissionGranted
                    ? '已开始后台下载更新，完成后将自动弹出安装界面，可在通知栏查看进度。'
                    : '已开始后台下载更新，完成后将自动弹出安装界面。',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        );
      case _InstallStage.error:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: BmTokens.iconMenu,
              color: colors.danger,
            ),
            const SizedBox(width: BmTokens.s2),
            Expanded(
              child: Text(
                '更新失败：${_errorText ?? '未知错误'}',
                style: type.caption.copyWith(color: colors.danger),
              ),
            ),
          ],
        );
      case _InstallStage.idle:
        return const SizedBox.shrink();
    }
  }

  List<BmDialogAction> _buildActions() {
    switch (_stage) {
      case _InstallStage.installing:
        return const <BmDialogAction>[];
      case _InstallStage.androidStarted:
        return [
          BmDialogAction(
            label: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ];
      case _InstallStage.idle:
      case _InstallStage.error:
        return [
          BmDialogAction(
            label: '暂不更新',
            onPressed: () => Navigator.of(context).pop(),
          ),
          BmDialogAction(
            label: _stage == _InstallStage.error ? '重试' : '立即更新',
            onPressed: _startInstall,
          ),
        ];
    }
  }

  Widget _buildChangelogItem(ChangelogEntry entry) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Padding(
      padding: const EdgeInsets.only(bottom: BmTokens.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${entry.version}',
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: BmTokens.s2),
              Text(
                entry.date,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: BmTokens.s1),
          ...entry.changes.map(
            (change) => Padding(
              padding: const EdgeInsets.only(
                left: BmTokens.s2,
                top: BmTokens.s1 / 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: type.caption.copyWith(color: colors.accent),
                  ),
                  Expanded(
                    child: Text(
                      change,
                      style: type.caption.copyWith(color: colors.textSecondary),
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
