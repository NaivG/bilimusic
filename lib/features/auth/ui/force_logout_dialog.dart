import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/bili_exception.dart';

/// 服务端注销失败时的强制退出提示。
///
/// 返回 `true` 表示用户选择「强制退出」，此时只需清本地登录态。
Future<bool> showForceLogoutDialog(
  BuildContext context, {
  Object? error,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('强制退出登录'),
        content: Text(_describeFailure(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('强制退出'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// 把注销失败翻译成用户能判断要不要强制退出的理由。
String _describeFailure(Object? error) {
  final reason = switch (error) {
    BiliApiException e when e.isNotLogin =>
      '服务端已不认当前登录态（Cookie 可能已过期），注销请求被拒绝。',
    BiliApiException e => '服务端拒绝了注销请求（code ${e.code}）。',
    BiliNetworkException e when e.isTimeout => '注销请求超时，没有送达服务端。',
    BiliNetworkException() => '网络不可达，注销请求没有送达服务端。',
    _ => '服务端注销未完成。',
  };
  // 服务端明确回「未登录」时本地登录态已经失效，不必再提醒服务端会话仍有效。
  final advice = error is BiliApiException && error.isNotLogin
      ? '本地登录态已经失效，可以强制退出清除残留的登录信息。'
      : '可以强制退出：清除本机登录凭据，服务端会话可能仍然有效。';
  return '$reason\n\n$advice';
}
