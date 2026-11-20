import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/roam/models/roam_config.dart';
import 'package:bilimusic/features/roam/models/roam_style.dart';
import 'package:bilimusic/features/roam/roam_providers.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/clipboard_helpers.dart';
import 'package:bilimusic/shared/widgets/music_cover.dart';

/// 显示漫游模式详情对话框。
///
/// 内容：歌单 / 风格 / 种子列表。
/// 操作：
/// - 导出配置 → 复制到剪贴板
/// - 停止漫游 → 退出漫游
/// - 关闭
///
/// 返回 `true` 表示用户点击了「停止漫游」，`null` 表示取消/关闭；
/// 漫游状态本身以 [isRoamingProvider] 为准（遥控 / 跟随也会停漫游）。
Future<bool?> showRoamInfoDialog(BuildContext context, WidgetRef ref) {
  return showBmDialog<bool>(
    context: context,
    builder: (_) => const _RoamInfoDialog(),
  );
}

class _RoamInfoDialog extends ConsumerWidget {
  const _RoamInfoDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.read(playerCoordinatorProvider);
    // 停下漫游的来源不止本对话框：遥控指令 / 「跟随此设备」也会停，
    // 订阅后按钮的可用状态才能跟着变。
    final isRoaming = ref.watch(isRoamingProvider);
    final style = coordinator.roamStyle;
    final seeds = coordinator.roamSeeds;

    return BmDialog(
      title: '漫游详情',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(label: '风格', value: _styleDisplayName(style)),
          const SizedBox(height: BmTokens.s2),
          _InfoRow(label: '种子', value: '${seeds.length} 首'),
          const SizedBox(height: BmTokens.s3),
          if (seeds.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: BmTokens.s8 * 7),
              // 种子超过上限时内层自己滚：外层 BmDialog 的滚动到不了被裁的部分。
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: seeds.length,
                separatorBuilder: (_, _) => const SizedBox(height: BmTokens.s2),
                itemBuilder: (_, i) => _SeedTile(music: seeds[i]),
              ),
            ),
        ],
      ),
      actions: [
        BmDialogAction(label: '导出配置', onPressed: () => _onExport(context, ref)),
        BmDialogAction(
          label: '停止漫游',
          enabled: isRoaming,
          onPressed: () => _onStop(context, ref),
        ),
        BmDialogAction(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Future<void> _onExport(BuildContext context, WidgetRef ref) async {
    final config = RoamConfig.fromCoordinator(
      ref.read(playerCoordinatorProvider),
    );
    if (config == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法导出：当前无活跃漫游会话')));
      return;
    }
    final text = config.toPlainText();
    await copyToClipboard(context, text, preview: text);
  }

  void _onStop(BuildContext context, WidgetRef ref) {
    ref.read(playerCoordinatorProvider).stopRoam();
    Navigator.of(context).pop(true);
  }
}

String _styleDisplayName(RoamStyle? s) => switch (s) {
  RoamStyle.similar => '相似',
  RoamStyle.balanced => '平衡',
  RoamStyle.explore => '探索',
  null => '未知',
};

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: BmTokens.s8,
          child: Text(
            label,
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: type.body.copyWith(color: colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _SeedTile extends StatelessWidget {
  const _SeedTile({required this.music});
  final Music music;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      children: [
        MusicCover(music: music, size: 44, radius: BmTokens.r4),
        const SizedBox(width: BmTokens.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                music.title.isEmpty ? '(无标题)' : music.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: BmTokens.s1),
              Text(
                music.artist.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
