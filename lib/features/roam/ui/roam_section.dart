import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/roam/roam_providers.dart';
import 'package:bilimusic/features/roam/ui/roam_info_dialog.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';

/// profile_page 上的"漫游模式"行。
///
/// UI 风格与 `_buildFunctionList` 中的其他条目一致（圆角图标块 + 标题 +
/// trailing）：
/// - 未漫游：trailing 为右箭头，点击进入 [ShellPage.roamOnboarding]。
/// - 漫游中：trailing 为主题色设置按钮，点击 [showRoamInfoDialog]
///   （详情框内可导出配置或停止漫游）。
///
/// 漫游状态订阅 [isRoamingProvider]：除了本行的入口，被控端收到遥控指令、
/// 本机「跟随此设备」也会退出漫游，本行需要跟着刷新。
class RoamSection extends ConsumerWidget {
  const RoamSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRoaming = ref.watch(isRoamingProvider);
    final accent = Theme.of(context).colorScheme.primary;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.explore_outlined, color: accent),
      ),
      title: const Text('漫游模式'),
      trailing: isRoaming
          ? IconButton(
              icon: Icon(Icons.tune, color: accent),
              tooltip: '漫游设置',
              onPressed: () => showRoamInfoDialog(context, ref),
            )
          : const Icon(Icons.arrow_forward_ios),
      onTap: isRoaming
          ? null
          : () => ShellPageManager.instance.push(ShellPage.roamOnboarding),
    );
  }
}
