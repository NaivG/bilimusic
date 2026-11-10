import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';

/// 横屏内容区舞台：页面在最底，遮罩 / 资料库抽屉 / 播放队列依次叠在上面。
///
/// 抽屉与队列用 [AnimatedSlide]（绘制期位移）滑入滑出，布局上始终停在舞台的
/// 左 / 右缘；[Stack] 只在布局溢出时才插裁切层，位移出去的那截会画到图标轨和
/// 窗口边缘上。舞台因此常驻一层 [ClipRect]：三块 chrome（轨 / 标题栏 / 底栏）
/// 永远不被抽屉压住。
class LandscapeContentStage extends StatelessWidget {
  const LandscapeContentStage({
    super.key,
    required this.page,
    required this.libraryDrawer,
    required this.queuePanel,
    required this.libraryOpen,
    required this.queueOpen,
    required this.onCloseDrawers,
  });

  /// 舞台底层的页面内容（壳层的页面切换容器）。
  final Widget page;

  /// 从左缘滑出的资料库抽屉。
  final Widget libraryDrawer;

  /// 从右缘滑出的播放队列。
  final Widget queuePanel;

  final bool libraryOpen;
  final bool queueOpen;

  /// 点遮罩关闭抽屉。
  final VoidCallback onCloseDrawers;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: page),
          // 抽屉遮罩：只盖内容区，不压轨 / 标题栏 / 底栏
          Positioned.fill(child: _buildScrim(context)),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !libraryOpen,
              child: AnimatedSlide(
                offset: libraryOpen ? Offset.zero : const Offset(-1, 0),
                duration: BmMotion.drawer,
                curve: BmMotion.pageCurve,
                child: libraryDrawer,
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !queueOpen,
              child: AnimatedSlide(
                offset: queueOpen ? Offset.zero : const Offset(1, 0),
                duration: BmMotion.drawer,
                curve: BmMotion.pageCurve,
                child: queuePanel,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrim(BuildContext context) {
    final open = libraryOpen || queueOpen;
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: BmMotion.scrim,
        curve: BmMotion.standard,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCloseDrawers,
          child: ColoredBox(color: context.bmColors.scrim),
        ),
      ),
    );
  }
}
