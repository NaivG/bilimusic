import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/taste/ui/widgets/taste_graph_card.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 我的音乐画像（设置 → 音乐画像）。
///
/// 展示 [TasteProfile] 的词-词关系图与加权关键词（越重的词视觉上越突出），
/// 并提供手动重建入口。画像由播放历史 / 收藏 / 歌单名等正信号自动构建，
/// 每 24 小时更新一次，同时驱动漫游排序与「猜你喜欢」重排。
class TasteProfilePage extends ConsumerStatefulWidget {
  const TasteProfilePage({super.key});

  @override
  ConsumerState<TasteProfilePage> createState() => _TasteProfilePageState();
}

class _TasteProfilePageState extends ConsumerState<TasteProfilePage> {
  TasteProfile? _profile;
  bool _loading = true;
  bool _rebuilding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await ref.read(tasteProfileServiceProvider).ensureFresh();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    try {
      final profile = await ref
          .read(tasteProfileServiceProvider)
          .ensureFresh(force: true);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _rebuilding = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AutoAppBar.generateAppBar(context: context, title: '音乐画像'),
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildIntro(context),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _buildStats(context),
            const SizedBox(height: 16),
            if (profile != null && !profile.isEmpty) ...[
              TasteGraphCard(profile: profile),
              const SizedBox(height: 16),
            ],
            _buildKeywords(context),
            const SizedBox(height: 24),
            _buildRebuildButton(context),
          ],
        ],
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('画像在学什么', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '根据播放历史、收藏和歌单标签自动提炼你的口味关键词，'
              '每 24 小时更新一次。画像会参与漫游选歌（风格档位越偏向'
              '「探索」，口味权重越高）和「猜你喜欢」的排序。'
              '所有计算均在本地完成，数据不会上传。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context) {
    final profile = _profile;
    final updated = profile == null
        ? '—'
        : '${profile.updatedAt.year}-'
              '${profile.updatedAt.month.toString().padLeft(2, '0')}-'
              '${profile.updatedAt.day.toString().padLeft(2, '0')} '
              '${profile.updatedAt.hour.toString().padLeft(2, '0')}:'
              '${profile.updatedAt.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Expanded(
          child: _statTile(
            context,
            label: '参与统计的歌曲',
            value: '${profile?.sampleCount ?? 0} 首',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statTile(context, label: '上次更新', value: updated),
        ),
      ],
    );
  }

  Widget _statTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywords(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _profile;
    if (profile == null || profile.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '还没有足够的播放记录来提炼口味。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('口味关键词', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in profile.keywords) _keywordChip(context, k),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 关键词胶囊：权重映射到字号与不透明度，轻重一眼可辨。
  Widget _keywordChip(BuildContext context, TasteKeyword k) {
    final theme = Theme.of(context);
    final w = k.weight.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.35 + 0.65 * w,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
      child: Text(
        k.term,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 12 + 4 * w,
          fontWeight: w > 0.6 ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildRebuildButton(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _rebuilding ? null : _rebuild,
      icon: _rebuilding
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      label: Text(_rebuilding ? '重建中…' : '立即重建画像'),
    );
  }
}
