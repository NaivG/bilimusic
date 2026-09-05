import 'package:flutter/material.dart';
import 'package:bilimusic/utils/animations.dart';

/// 空状态类型
enum EmptyStateType {
  initial, // 初始状态（未搜索）
  noResults, // 无搜索结果
  error, // 错误状态
  loading, // 加载状态
}

/// 搜索空状态组件
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildIcon(context),
            const SizedBox(height: 24),
            _buildMessage(context),
            if (type == EmptyStateType.error && onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
            if (suggestions != null && suggestions!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSuggestions(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    IconData iconData;
    Color iconColor;

    switch (type) {
      case EmptyStateType.initial:
        iconData = Icons.search;
        iconColor = Colors.grey[400]!;
        break;
      case EmptyStateType.noResults:
        iconData = Icons.music_off_outlined;
        iconColor = Colors.grey[400]!;
        break;
      case EmptyStateType.error:
        iconData = Icons.error_outline;
        iconColor = Colors.red[300]!;
        break;
      case EmptyStateType.loading:
        return SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: Theme.of(context).primaryColor,
          ),
        );
    }

    return FadeInWidget(
      duration: const Duration(milliseconds: 400),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: iconColor.withValues(alpha: 0.1),
        ),
        child: Icon(iconData, size: 48, color: iconColor),
      ),
    );
  }

  Widget _buildMessage(BuildContext context) {
    String message;
    if (customMessage != null) {
      message = customMessage!;
    } else {
      switch (type) {
        case EmptyStateType.initial:
          message = '开始搜索你喜欢的音乐';
          break;
        case EmptyStateType.noResults:
          message = '没有找到相关结果';
          break;
        case EmptyStateType.error:
          message = '加载失败，请稍后重试';
          break;
        case EmptyStateType.loading:
          message = '搜索中...';
          break;
      }
    }

    return FadeInWidget(
      duration: const Duration(milliseconds: 400),
      delay: const Duration(milliseconds: 100),
      child: Text(
        message,
        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return FadeInWidget(
      duration: const Duration(milliseconds: 400),
      delay: const Duration(milliseconds: 200),
      child: Column(
        children: [
          Text(
            '热门搜索',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: suggestions!.map((suggestion) {
              return ActionChip(
                label: Text(suggestion, style: const TextStyle(fontSize: 13)),
                onPressed: () {
                  // 外部处理搜索建议点击
                },
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// 热门搜索建议组件
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
    return FadeInWidget(
      duration: const Duration(milliseconds: 400),
      delay: const Duration(milliseconds: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '热门搜索',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.asMap().entries.map((entry) {
                final index = entry.key;
                final suggestion = entry.value;
                return _SuggestionChip(
                  index: index + 1,
                  label: suggestion,
                  onTap: () => onSuggestionTap(suggestion),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final int index;
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.index,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTopThree = index <= 3;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isTopThree
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTopThree) ...[
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isTopThree
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
