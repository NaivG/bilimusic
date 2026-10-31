import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/core/network/bili_exception.dart';
import 'package:bilimusic/features/auth/ui/force_logout_dialog.dart';

/// 搭一个只有「打开对话框」按钮的宿主，结果回填 [onResult]。
Future<void> _pumpHost(
  WidgetTester tester,
  Object? error,
  void Function(bool) onResult,
) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                onResult(await showForceLogoutDialog(context, error: error));
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('服务端拒绝（-101）时说明登录态已失效', (tester) async {
    await _pumpHost(tester, const BiliApiException(-101, '账号未登录'), (_) {});
    await _openDialog(tester);

    expect(find.text('强制退出登录'), findsOneWidget);
    expect(find.textContaining('服务端已不认当前登录态'), findsOneWidget);
    expect(find.textContaining('本地登录态已经失效'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('强制退出'), findsOneWidget);
  });

  testWidgets('其他业务错误带出错误码', (tester) async {
    await _pumpHost(tester, const BiliApiException(-111, 'csrf 校验失败'), (_) {});
    await _openDialog(tester);

    expect(find.textContaining('服务端拒绝了注销请求'), findsOneWidget);
    expect(find.textContaining('code -111'), findsOneWidget);
    expect(find.textContaining('服务端会话可能仍然有效'), findsOneWidget);
  });

  testWidgets('网络错误区分超时', (tester) async {
    await _pumpHost(
      tester,
      const BiliNetworkException(null, 'timeout', isTimeout: true),
      (_) {},
    );
    await _openDialog(tester);

    expect(find.textContaining('注销请求超时'), findsOneWidget);
  });

  testWidgets('取消返回 false，确认后返回 true', (tester) async {
    bool? result;
    await _pumpHost(tester, const BiliApiException(-101, '账号未登录'), (v) {
      result = v;
    });

    await _openDialog(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await _openDialog(tester);
    await tester.tap(find.text('强制退出'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
