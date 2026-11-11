import 'package:flutter/material.dart';

import 'package:bilimusic/features/fav_sync/fav_sync_manager.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 导入进度对话框
/// 展示导入 Bilibili 收藏夹时的实时进度
class ImportProgressDialog extends StatefulWidget {
  final String folderName;
  final Future<ImportResult> Function(void Function(int, int, int) onProgress)
  importTask;

  const ImportProgressDialog({
    super.key,
    required this.folderName,
    required this.importTask,
  });

  @override
  State<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<ImportProgressDialog> {
  int _processed = 0;
  int _total = 0;
  int _failed = 0;
  bool _isComplete = false;
  String? _errorMessage;
  ImportResult? _importResult;

  @override
  void initState() {
    super.initState();
    _startImport();
  }

  Future<void> _startImport() async {
    try {
      final r = await widget.importTask((processed, total, failed) {
        if (mounted) {
          setState(() {
            _processed = processed;
            _total = total;
            _failed = failed;
          });
        }
      });
      if (mounted) {
        setState(() {
          _importResult = r;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isComplete = true;
        });
      }
    }
  }

  void _dismiss() {
    // Build the result to return — prefer the captured ImportResult from the
    // import task, otherwise reconstruct from progress counters.
    final result =
        _importResult ??
        ImportResult(successCount: _processed - _failed, failedCount: _failed);
    // Defer the pop to the next frame to avoid triggering
    // '!_debugLocked' assertion when the navigator is still
    // animating the dialog route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  /// 状态图标：失败 / 完成 / 进行中。
  Widget _buildStatus(BmColors colors) {
    if (_errorMessage != null) {
      return Icon(
        Icons.error_outline,
        size: BmTokens.iconTile,
        color: colors.danger,
      );
    }
    if (_isComplete) {
      return Icon(
        Icons.check_circle,
        size: BmTokens.iconTile,
        color: colors.success,
      );
    }
    return SizedBox(
      width: BmTokens.iconTile,
      height: BmTokens.iconTile,
      child: CircularProgressIndicator(
        strokeWidth: BmTokens.s1 / 2,
        color: colors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final canDismiss = _isComplete || _errorMessage != null;

    return BmDialog(
      title: _isComplete ? '导入完成' : '正在导入',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _errorMessage != null ? '出错了' : widget.folderName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: type.label.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: BmTokens.s5),
          Center(child: _buildStatus(colors)),
          if (_total > 0 && _errorMessage == null) ...[
            const SizedBox(height: BmTokens.s4),
            LinearProgressIndicator(
              value: _processed / _total,
              minHeight: BmTokens.s1,
              borderRadius: BmTokens.r4All,
              color: colors.accent,
              backgroundColor: colors.fillMuted,
            ),
            const SizedBox(height: BmTokens.s2),
            Text(
              '$_processed / $_total',
              textAlign: TextAlign.center,
              style: BmTypography.numeric(type.label)
                  .copyWith(color: colors.textSecondary),
            ),
          ],
          if (_failed > 0)
            Padding(
              padding: const EdgeInsets.only(top: BmTokens.s1),
              child: Text(
                '已跳过 $_failed 个失效内容',
                textAlign: TextAlign.center,
                style: type.caption.copyWith(color: colors.warning),
              ),
            ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: BmTokens.s2),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: type.label.copyWith(color: colors.danger),
              ),
            ),
        ],
      ),
      actions: [
        BmDialogAction(
          label: _errorMessage != null ? '关闭' : '完成',
          enabled: canDismiss,
          onPressed: _dismiss,
        ),
      ],
    );
  }
}
