import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/pages/profile/widgets/roam_info_dialog.dart';
import 'package:bilimusic/shells/shell_page_manager.dart';

/// profile_page 上的"漫游模式"行。
///
/// UI 风格与 `_buildFunctionList` 中的其他条目一致（圆角图标块 + 标题 +
/// trailing）：
/// - 未漫游：trailing 为右箭头，点击进入 [ShellPage.roamOnboarding]。
/// - 漫游中：trailing 为紫色设置按钮，点击 [showRoamInfoDialog]
///   （详情框内可导出配置或停止漫游）。
class RoamSection extends ConsumerStatefulWidget {
  const RoamSection({super.key});

  @override
  ConsumerState<RoamSection> createState() => _RoamSectionState();
}

class _RoamSectionState extends ConsumerState<RoamSection> {
  void _onStartTap() {
    ShellPageManager.instance.push(ShellPage.roamOnboarding);
  }

  Future<void> _onSettingsTap() async {
    final didStop = await showRoamInfoDialog(context, ref);
    if (didStop == true) {
      // isRoaming 变化后手动触发重建（行内仍使用 ref.read，依赖 setState）
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRoaming = ref.read(playerCoordinatorProvider).isRoaming;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.explore_outlined, color: Colors.purple),
      ),
      title: const Text('漫游模式'),
      trailing: isRoaming
          ? IconButton(
              icon: const Icon(Icons.tune, color: Colors.purple),
              tooltip: '漫游设置',
              onPressed: _onSettingsTap,
            )
          : const Icon(Icons.arrow_forward_ios),
      onTap: isRoaming ? null : _onStartTap,
    );
  }
}
