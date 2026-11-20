import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lan_sync/logic/serial_executor.dart';

void main() {
  group('SerialExecutor', () {
    test('任务严格按入队顺序串行执行，不重叠', () async {
      final executor = SerialExecutor();
      final log = <String>[];
      final gate = Completer<void>();

      final first = executor.run(() async {
        log.add('a:start');
        await gate.future;
        log.add('a:end');
      });
      final second = executor.run(() async {
        log.add('b:start');
        log.add('b:end');
      });
      final third = executor.run(() async {
        log.add('c:start');
      });

      await pumpEventQueue();
      expect(log, ['a:start'], reason: '第一个任务未完成时后续任务不得开始');

      gate.complete();
      await Future.wait([first, second, third]);
      expect(log, ['a:start', 'a:end', 'b:start', 'b:end', 'c:start']);
    });

    test('单个任务失败不阻塞后续任务，错误只回传给调用方', () async {
      final executor = SerialExecutor();
      final log = <String>[];

      final failing = executor.run<void>(() async {
        log.add('first');
        throw StateError('boom');
      });
      final next = executor.run(() async {
        log.add('second');
        return 42;
      });

      await expectLater(failing, throwsStateError);
      expect(await next, 42);
      expect(log, ['first', 'second']);

      // 队列尾部没有被错误污染，还能继续接任务。
      expect(await executor.run(() async => 'ok'), 'ok');
    });

    test('返回值类型与任务结果一致', () async {
      final executor = SerialExecutor();

      expect(await executor.run(() async => 7), 7);
      expect(await executor.run(() async => null), isNull);
    });
  });
}
