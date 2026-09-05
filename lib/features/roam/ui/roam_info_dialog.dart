import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/roam/models/roam_config.dart';
import 'package:bilimusic/features/roam/models/roam_style.dart';
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
/// 返回 `true` 表示用户点击了「停止漫游」，`null` 表示取消/关闭。
Future<bool?> showRoamInfoDialog(BuildContext context, WidgetRef ref) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _RoamInfoDialog(),
  );
}

class _RoamInfoDialog extends ConsumerWidget {
  const _RoamInfoDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coordinator = ref.read(playerCoordinatorProvider);
    final style = coordinator.roamStyle;
    final seeds = coordinator.roamSeeds;

    return AlertDialog(
      title: const Text('漫游详情'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(label: '风格', value: _styleDisplayName(style)),
            const SizedBox(height: 6),
            _InfoRow(label: '种子', value: '${seeds.length} 首'),
            const SizedBox(height: 12),
            if (seeds.isNotEmpty)
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: seeds.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _SeedTile(music: seeds[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _onExport(context, ref),
          child: const Text('导出配置'),
        ),
        TextButton(
          onPressed: coordinator.isRoaming ? () => _onStop(context, ref) : null,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('停止漫游'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Future<void> _onExport(BuildContext context, WidgetRef ref) async {
    final config = RoamConfig.fromCoordinator(
      ref.read(playerCoordinatorProvider),
    );
    if (config == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法导出：当前无活跃漫游会话')));
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
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _SeedTile extends StatelessWidget {
  const _SeedTile({required this.music});
  final Music music;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        MusicCover(music: music, size: 44, radius: 6),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                music.title.isEmpty ? '(无标题)' : music.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                music.artist.isEmpty ? '未知艺术家' : music.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
