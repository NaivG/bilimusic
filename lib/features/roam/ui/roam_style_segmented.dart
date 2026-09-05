import 'package:flutter/material.dart';

import 'package:bilimusic/models/roam_style.dart';

/// 共享 RoamStyle 三档选择器（相似 / 平衡 / 探索）。
///
/// 用于：
/// - profile_page 的 RoamSection
/// - roam_onboarding 步骤 C
class RoamStyleSegmented extends StatelessWidget {
  const RoamStyleSegmented({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final RoamStyle selected;
  final ValueChanged<RoamStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<RoamStyle>(
      segments: const [
        ButtonSegment(
          value: RoamStyle.similar,
          label: Text('相似'),
          icon: Icon(Icons.compare_arrows),
        ),
        ButtonSegment(
          value: RoamStyle.balanced,
          label: Text('平衡'),
          icon: Icon(Icons.balance),
        ),
        ButtonSegment(
          value: RoamStyle.explore,
          label: Text('探索'),
          icon: Icon(Icons.travel_explore),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (s) {
        if (s.isEmpty) return;
        onChanged(s.first);
      },
    );
  }
}
