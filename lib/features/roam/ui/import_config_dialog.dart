import 'package:flutter/material.dart';

import 'package:bilimusic/features/roam/models/roam_config.dart';
import 'package:bilimusic/shared/ui/controls/bm_field.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 显示导入漫游配置对话框。
///
/// 返回解析成功的 [RoamConfig]，或 `null`（用户取消 / 解析失败不返回）。
///
/// 解析失败时 inline 展示错误，用户可继续编辑文本后再次点击「导入」。
Future<RoamConfig?> showImportConfigDialog(BuildContext context) {
  return showBmDialog<RoamConfig>(
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
    final colors = context.bmColors;
    final type = context.bmType;

    return BmDialog(
      title: '导入漫游配置',
      hasFields: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '粘贴之前导出的配置字符串：',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: BmTokens.s2),
          BmField(
            controller: _controller,
            hintText: '2-r-b-2-3-xAVezxEkw-QwU7BREo6-GzV36pE5h',
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            onChanged: (_) => _revalidate(),
            errorText: _error,
          ),
        ],
      ),
      actions: [
        BmDialogAction(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BmDialogAction(
          label: '导入',
          enabled: _parsed != null,
          onPressed: _onImport,
        ),
      ],
    );
  }
}
