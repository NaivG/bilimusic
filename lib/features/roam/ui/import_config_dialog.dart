import 'package:flutter/material.dart';

import 'package:bilimusic/models/roam_config.dart';

/// 显示导入漫游配置对话框。
///
/// 返回解析成功的 [RoamConfig]，或 `null`（用户取消 / 解析失败不返回）。
///
/// 解析失败时 inline 展示错误，用户可继续编辑文本后再次点击「导入」。
Future<RoamConfig?> showImportConfigDialog(BuildContext context) {
  return showDialog<RoamConfig>(
    context: context,
    builder: (_) => const _ImportConfigDialog(),
  );
}

class _ImportConfigDialog extends StatefulWidget {
  const _ImportConfigDialog();

  @override
  State<_ImportConfigDialog> createState() => _ImportConfigDialogState();
}

class _ImportConfigDialogState extends State<_ImportConfigDialog> {
  final TextEditingController _controller = TextEditingController();
  RoamConfig? _parsed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_revalidate);
  }

  @override
  void dispose() {
    _controller.removeListener(_revalidate);
    _controller.dispose();
    super.dispose();
  }

  void _revalidate() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsed = null;
        _error = null;
      });
      return;
    }
    final parsed = RoamConfig.fromPlainText(text);
    setState(() {
      _parsed = parsed;
      _error = parsed == null ? '无法解析，请检查格式' : null;
    });
  }

  void _onImport() {
    final parsed = _parsed;
    if (parsed == null) return;
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canImport = _parsed != null;

    return AlertDialog(
      title: const Text('导入漫游配置'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '粘贴之前导出的配置字符串：',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '2-r-b-2-3-xAVezxEkw-QwU7BREo6-GzV36pE5h',
                errorText: _error,
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canImport ? _onImport : null,
          child: const Text('导入'),
        ),
      ],
    );
  }
}
