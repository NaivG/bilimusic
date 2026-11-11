import 'package:flutter/material.dart';

import 'package:bilimusic/app/app_lifecycle.dart';
import 'package:bilimusic/app/desktop_tray.dart';
import 'package:bilimusic/features/settings/settings_manager.dart';
import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 关闭行为确认弹窗：询问本次关闭是「最小化至托盘」还是「直接退出」。
///
/// 勾选「不再提示」后，本次选择会覆写设置里的关闭行为，之后不再弹窗
/// （可在「设置 - 窗口行为 - 关闭行为」改回「弹出提示」）。
Future<void> showCloseConfirmDialog(BuildContext context) {
  return showBmDialog<void>(
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
    final colors = context.bmColors;
    final type = context.bmType;
    return BmDialog(
      title: '关闭 BiliMusic',
      // 最后一个动作是「直接退出」：销毁式操作走 danger 文字
      destructive: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关闭窗口时希望执行什么操作？',
            style: type.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: BmTokens.s3),
          BmPressable(
            onTap: () => setState(() => _remember = !_remember),
            borderRadius: BmTokens.r10All,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BmTokens.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: BmTokens.s1 / 2),
                    child: Container(
                      width: BmTokens.icon,
                      height: BmTokens.icon,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _remember ? colors.accent : null,
                        borderRadius: BmTokens.r4All,
                        border: Border.all(
                          color: _remember ? colors.accent : colors.hairline,
                          width: BmTokens.hairlineWidth,
                        ),
                      ),
                      child: _remember
                          ? Icon(
                              Icons.check,
                              size: BmTokens.iconInline,
                              color: colors.onAccent,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: BmTokens.s2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '不再提示',
                          style: type.body.copyWith(color: colors.textPrimary),
                        ),
                        Text(
                          '可在「设置 - 窗口行为 - 关闭行为」中修改',
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        BmDialogAction(
          label: '最小化至托盘',
          onPressed: () => _confirm(minimize: true),
        ),
        BmDialogAction(
          label: '直接退出',
          onPressed: () => _confirm(minimize: false),
        ),
      ],
    );
  }
}
