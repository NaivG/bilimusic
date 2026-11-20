import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/controls/bm_chip.dart';
import 'package:bilimusic/shared/ui/status/bm_empty.dart';
import 'package:bilimusic/shared/ui/status/bm_skeleton.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/animations.dart';

/// 空状态类型
enum EmptyStateType {
  initial, // 初始状态（未搜索）
  noResults, // 无搜索结果
  error, // 错误状态
  loading, // 加载状态
}

/// 搜索空状态组件：统一走 [BmEmptyState]，热门搜索用 [BmChip] 的 [Wrap]。
class SearchEmptyState extends StatelessWidget {
  final EmptyStateType type;
  final String? customMessage;
  final VoidCallback? onRetry;
  final List<String>? suggestions;

  const SearchEmptyState({
    super.key,
    required this.type,
    this.customMessage,
    this.onRetry,
    this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    if (type == EmptyStateType.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.pageInset,
          vertical: BmTokens.s6,
        ),
        child: BmSkeleton.list(count: 4),
      );
    }

    final colors = context.bmColors;
    final typography = context.bmType;
    final message = customMessage;

    return FadeInWidget(
      child: BmEmptyState(
        title: message ?? _defaultTitle,
        icon: _icon,
        action: _buildAction(colors, typography),
      ),
    );
  }

  String get _defaultTitle {
    switch (type) {
      case EmptyStateType.initial:
        return '开始搜索你喜欢的音乐';
      case EmptyStateType.noResults:
        return '没有找到相关结果';
      case EmptyStateType.error:
        return '加载失败，请稍后重试';
      case EmptyStateType.loading:
        return '搜索中...';
    }
  }

  IconData get _icon {
    switch (type) {
      case EmptyStateType.initial:
        return Icons.search_rounded;
      case EmptyStateType.noResults:
        return Icons.music_off_outlined;
      case EmptyStateType.error:
        return Icons.error_outline_rounded;
      case EmptyStateType.loading:
        return Icons.search_rounded;
    }
  }

  Widget? _buildAction(BmColors colors, BmTypographySet typography) {
    final suggestionList = suggestions;
    final canRetry = type == EmptyStateType.error && onRetry != null;

    if (suggestionList == null || suggestionList.isEmpty) {
      if (!canRetry) return null;
      return TextButton(onPressed: onRetry, child: const Text('重试'));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '热门搜索',
          style: typography.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: BmTokens.s2),
        Wrap(
          spacing: BmTokens.s2,
          runSpacing: BmTokens.s2,
          alignment: WrapAlignment.center,
          children: [
            for (final suggestion in suggestionList) BmChip(label: suggestion),
          ],
        ),
      ],
    );
  }
}

/// 热门搜索建议：标题 + [BmChip] 的 [Wrap]。
class HotSearchSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final Function(String) onSuggestionTap;

  const HotSearchSuggestions({
    super.key,
    required this.suggestions,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return FadeInWidget(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.pageInset),
            child: Text(
              '热门搜索',
              style: type.bodyStrong.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: BmTokens.s3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.pageInset),
            child: Wrap(
              spacing: BmTokens.s2,
              runSpacing: BmTokens.s2,
              children: [
                for (final suggestion in suggestions)
                  BmChip(
                    label: suggestion,
                    onTap: () => onSuggestionTap(suggestion),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
