import 'dart:async';

/// 串行异步执行器：同一时刻只跑一个任务，后提交的任务排队等待。
///
/// mDNS 的 `start` / `stop` 会创建、销毁原生对象（BonsoirDiscovery /
/// BonsoirBroadcast）。这类生命周期操作统一排到本执行器上，调用顺序即执行顺序。
///
/// 注意：任务内部不要再 `await` 同一个执行器上的任务，否则会互相等待而卡死；
/// 需要复用的内部步骤请直接调用私有方法（例如 `_stopInternal`）。
class SerialExecutor {
  /// 队尾：上一个任务完成的信号。
  ///
  /// 队尾自身永远以成功结束：单个任务失败只回传给它的调用方，不能污染
  /// 队列，否则后续任务会被连带卡死。
  Future<void> _tail = Future<void>.value();

  /// 把 [action] 排到队尾，返回的 Future 携带它自己的结果 / 错误。
  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final next = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _tail = next.catchError((Object _) {});
    return completer.future;
  }
}
