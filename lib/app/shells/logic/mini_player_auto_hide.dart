/// 迷你播放器随滚动自动收起的判定器。
///
/// 只累计纵向滚动增量，方向反转时清零；是否启用由外壳决定。
class MiniPlayerAutoHide {
  MiniPlayerAutoHide({this.threshold = 12});

  /// 触发一次收起/展开所需的累计滚动距离（像素）。
  final double threshold;

  double _accumulated = 0;

  /// 喂入一次纵向滚动增量，返回期望的收起状态：
  /// `true` 收起、`false` 展开、`null` 保持不变。
  ///
  /// 增量为正表示向下浏览（内容上移），为负表示向上浏览。
  /// [atTop] 为 true 时总是展开。
  bool? update(double scrollDelta, {bool atTop = false}) {
    if (atTop) {
      _accumulated = 0;
      return false;
    }
    if (scrollDelta == 0) return null;
    if (_accumulated != 0 && _accumulated.sign != scrollDelta.sign) {
      _accumulated = 0;
    }
    _accumulated += scrollDelta;
    if (_accumulated > threshold) {
      _accumulated = 0;
      return true;
    }
    if (_accumulated < -threshold) {
      _accumulated = 0;
      return false;
    }
    return null;
  }

  /// 清空累计量（切页或滚动结束时调用）。
  void reset() => _accumulated = 0;
}
