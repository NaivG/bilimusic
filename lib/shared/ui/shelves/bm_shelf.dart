import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// 竖屏横向货架：左侧贴齐页面边距，右侧露一点下一张卡（peek）。
///
/// **只给竖屏用**；横屏任何列表都不许横向滚动（设计约束 §4.3）。
/// 卡片宽度 [itemWidth] 与货架高度 [height] 都由调用方给——横向列表必须有
/// 确定高度，高度用 [heightFor] 按卡片宽度算。
class BmShelf extends StatelessWidget {
  const BmShelf({
    super.key,
    required this.itemWidth,
    required this.height,
    required this.children,
    this.gap = BmTokens.s3 + 2,
    this.inset = BmTokens.pageInsetWide,
    this.peek = true,
  });

  final double itemWidth;
  final double height;
  final List<Widget> children;
  final double gap;

  /// 货架左侧内边距（与页头对齐）。
  final double inset;

  /// 是否在右侧留出露边（多留一段 [gap]，让下一张卡露出一条）。
  final bool peek;

  /// 封面（正方形）+ 8 间距 + 两行标题 + 副标题的高度预算。
  static double heightFor(double itemWidth) =>
      itemWidth + BmTokens.s8 * 2 + BmTokens.s2;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(
          left: inset,
          right: peek ? inset + gap : inset,
        ),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: children.length,
        separatorBuilder: (context, index) => SizedBox(width: gap),
        itemBuilder: (context, index) =>
            SizedBox(width: itemWidth, child: children[index]),
      ),
    );
  }
}
