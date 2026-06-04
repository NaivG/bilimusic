import 'package:flutter/material.dart';
import 'package:bilimusic/managers/fav_sync_manager.dart';

/// 导入进度对话框
/// 展示导入 Bilibili 收藏夹时的实时进度
class ImportProgressDialog extends StatefulWidget {
  final String folderName;
  final Future<ImportResult> Function(
    void Function(int, int, int) onProgress,
  ) importTask;

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
    final result = _importResult ?? ImportResult(
      successCount: _processed - _failed,
      failedCount: _failed,
    );
    // Defer the pop to the next frame to avoid triggering
    // '!_debugLocked' assertion when the navigator is still
    // animating the dialog route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Text(
              _isComplete ? '导入完成' : '正在导入',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage != null
                  ? '出错了'
                  : widget.folderName,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),

            // 图标
            if (_errorMessage != null)
              const Icon(Icons.error_outline, size: 48, color: Colors.red)
            else if (_isComplete)
              const Icon(Icons.check_circle, size: 48, color: Colors.green)
            else
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),

            const SizedBox(height: 16),

            // 进度条
            if (_total > 0 && _errorMessage == null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _total > 0 ? _processed / _total : null,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_processed / $_total',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],

            // 跳过计数
            if (_failed > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '已跳过 $_failed 个失效内容',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),

            // 错误信息
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 24),

            // 按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isComplete || _errorMessage != null
                    ? _dismiss
                    : null,
                child: Text(_errorMessage != null ? '关闭' : '完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
