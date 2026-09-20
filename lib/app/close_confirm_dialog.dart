import 'package:flutter/material.dart';

import 'package:bilimusic/app/app_lifecycle.dart';
import 'package:bilimusic/app/desktop_tray.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';

/// 关闭行为确认弹窗：询问本次关闭是「最小化至托盘」还是「直接退出」。
///
/// 勾选「不再提示」后，本次选择会覆写设置里的关闭行为，之后不再弹窗
/// （可在「设置 - 窗口行为 - 关闭行为」改回「弹出提示」）。
Future<void> showCloseConfirmDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    // 点弹窗外或按 ESC 取消：窗口保持原状，不执行任何关闭行为
    barrierDismissible: true,
    builder: (_) => const _CloseConfirmDialog(),
  );
}

class _CloseConfirmDialog extends StatefulWidget {
  const _CloseConfirmDialog();

  @override
  State<_CloseConfirmDialog> createState() => _CloseConfirmDialogState();
}

class _CloseConfirmDialogState extends State<_CloseConfirmDialog> {
  bool _remember = false;

  Future<void> _confirm({required bool minimize}) async {
    // 跨 async gap 前先拿到 Navigator，避免 use_build_context_synchronously
    final navigator = Navigator.of(context);
    if (_remember) {
      // 勾选了不再提示：把本次选择覆写进设置
      await SettingsManager().setCloseBehavior(
        minimize
            ? SettingsManager.CLOSE_BEHAVIOR_MINIMIZE_TRAY
            : SettingsManager.CLOSE_BEHAVIOR_EXIT,
      );
    }
    navigator.pop();
    if (minimize) {
      await DesktopTray.instance.hideToTray();
    } else {
      await AppLifecycleManager.instance.quit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('关闭 BiliMusic'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('关闭窗口时希望执行什么操作？'),
          CheckboxListTile(
            value: _remember,
            onChanged: (value) => setState(() => _remember = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('不再提示'),
            subtitle: const Text('可在「设置 - 窗口行为 - 关闭行为」中修改'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _confirm(minimize: true),
          child: const Text('最小化至托盘'),
        ),
        FilledButton(
          onPressed: () => _confirm(minimize: false),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          child: const Text('直接退出'),
        ),
      ],
    );
  }
}
