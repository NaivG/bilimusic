import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:bilimusic/shared/theme/app_tokens.dart';

/// 更新前通知权限检查结果
enum UpdateNotificationDecision {
  /// 通知权限已授予，通知栏可正常显示下载进度
  granted,

  /// 通知权限未授予但继续更新：仅系统通知栏进度不可见，弹窗内进度不受影响
  continueWithout,

  /// 中断更新流程（用户选择先去开启权限，或关闭了对话框）
  aborted,
}

/// 永久拒绝时应用内引导对话框的动作
enum _PermissionDialogAction { openSettings, updateAnyway }

/// Android 上 DownloadManager 的下载进度通知需要通知权限（API 33+ 需运行时
/// 申请，且系统不会为应用更新自动授予）。在开始更新前调用本检查：
///
/// - 已授予 → 直接继续；
/// - 可申请 → 弹系统权限对话框，用户拒绝则静默继续（不做二次打扰）；
/// - 永久拒绝 → 弹应用内对话框引导去系统设置开启，也可选择继续更新。
Future<UpdateNotificationDecision> checkNotificationPermissionBeforeUpdate(
  BuildContext context,
) async {
  // 进度通知是 Android DownloadManager 的行为，其余平台直接放行
  if (!Platform.isAndroid) {
    return UpdateNotificationDecision.granted;
  }

  final status = await Permission.notification.status;
  if (status.isGranted) {
    return UpdateNotificationDecision.granted;
  }

  // 尚未永久拒绝：请求一次，拒绝则继续更新但不追问
  if (!status.isPermanentlyDenied) {
    final requested = await Permission.notification.request();
    return requested.isGranted
        ? UpdateNotificationDecision.granted
        : UpdateNotificationDecision.continueWithout;
  }

  if (!context.mounted) {
    return UpdateNotificationDecision.aborted;
  }
  final action = await showDialog<_PermissionDialogAction>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        backgroundColor: colorScheme.surfaceContainerHighest,
        title: const Text('无法显示更新通知'),
        content: const Text(
          '通知权限已被拒绝，下载更新时将无法在系统通知栏显示进度（不影响下载与安装）。\n\n可前往系统设置开启通知权限，也可以不开启直接更新。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_PermissionDialogAction.updateAnyway),
            child: Text(
              '仍然更新',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_PermissionDialogAction.openSettings),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
            ),
            child: const Text('去设置'),
          ),
        ],
      );
    },
  );
  switch (action) {
    case _PermissionDialogAction.openSettings:
      await openAppSettings();
      return UpdateNotificationDecision.aborted;
    case _PermissionDialogAction.updateAnyway:
      return UpdateNotificationDecision.continueWithout;
    case null:
      return UpdateNotificationDecision.aborted;
  }
}
