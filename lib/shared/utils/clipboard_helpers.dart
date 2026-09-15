import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 把一段字符串复制到剪贴板并弹「已复制」提示。
///
/// [preview] 非空时（如导出的长配置文本）在 SnackBar 里附两行内容预览。
Future<void> copyToClipboard(
  BuildContext context,
  String value, {
  String? preview,
}) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: preview == null
          ? const Text('已复制到剪贴板')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('已复制到剪贴板'),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
                ),
              ],
            ),
    ),
  );
}
