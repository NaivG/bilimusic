import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// Theater 开关：52 × 32 轨道 + 28 thumb。
///
/// 关闭态轨道用 [BmColors.lineStrong]，开启态用 [BmColors.accent]；
/// 状态也通过 [Semantics.toggled] 暴露，不只靠颜色。
class BmSwitch extends StatelessWidget {
  const BmSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
  });

  final bool value;

  /// 为 null 时禁用（38% 且不响应）。
  final ValueChanged<bool>? onChanged;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final enabled = onChanged != null;
    final reduce = reduceMotionOf(context);
    final duration = reduce ? Duration.zero : BmMotion.medium;
    final curve = motionCurve(context, BmMotion.pageCurve);

    return Semantics(
      label: semanticLabel,
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : BmAlpha.disabled,
          child: AnimatedContainer(
            duration: duration,
            curve: curve,
            width: BmTokens.switchWidth,
            height: BmTokens.switchHeight,
            padding: const EdgeInsets.all(BmTokens.s1 / 2),
            decoration: BoxDecoration(
              color: value ? colors.accent : colors.lineStrong,
              borderRadius: BorderRadius.circular(BmTokens.switchHeight / 2),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: BmTokens.switchThumb,
                height: BmTokens.switchThumb,
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: BmTokens.s1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
