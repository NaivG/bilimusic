import 'package:flutter/material.dart';

import 'package:bilimusic/domain/search_result.dart';
import 'package:bilimusic/shared/ui/controls/bm_chip.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 搜索类型分段：`BmChip` 的 [Wrap]，横屏也不会横向滚动。
class SearchTypeTabs extends StatelessWidget {
  final SearchResultType selectedType;
  final Function(SearchResultType) onTypeChanged;
  final List<SearchResultType> availableTypes;

  const SearchTypeTabs({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    required this.availableTypes,
  });

  @override
  Widget build(BuildContext context) {
    final types = availableTypes.isEmpty
        ? SearchResultType.values.take(4).toList()
        : availableTypes;

    return Wrap(
      spacing: BmTokens.s2,
      runSpacing: BmTokens.s2,
      children: [
        for (final type in types)
          BmChip(
            label: _getTypeLabel(type),
            selected: type == selectedType,
            onTap: () => onTypeChanged(type),
          ),
      ],
    );
  }

  String _getTypeLabel(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return '单曲';
      case SearchResultType.album:
        return '专辑';
      case SearchResultType.author:
        return 'UP主';
      case SearchResultType.bangumi:
        return '番剧';
      case SearchResultType.topic:
        return '话题';
      case SearchResultType.upuser:
        return '用户';
    }
  }
}

/// 搜索类型选择器（桌面端下拉样式）
class SearchTypeDropdown extends StatelessWidget {
  final SearchResultType selectedType;
  final Function(SearchResultType) onTypeChanged;
  final List<SearchResultType> availableTypes;

  const SearchTypeDropdown({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
    this.availableTypes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final types = availableTypes.isEmpty
        ? SearchResultType.values
        : availableTypes;

    return PopupMenuButton<SearchResultType>(
      initialValue: selectedType,
      onSelected: onTypeChanged,
      offset: const Offset(0, BmTokens.controlLg),
      color: colors.floating,
      shape: const RoundedRectangleBorder(borderRadius: BmTokens.r12All),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BmTokens.s3,
          vertical: BmTokens.s2,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BmTokens.rPillAll,
          border: Border.all(
            color: colors.hairline,
            width: BmTokens.hairlineWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getTypeIcon(selectedType),
              size: BmTokens.iconMenu,
              color: colors.accent,
            ),
            const SizedBox(width: BmTokens.s1),
            Text(
              _getTypeLabel(selectedType),
              style: type.label.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: BmTokens.s1),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: BmTokens.icon,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        return types
            .where((t) => t != SearchResultType.upuser) // 隐藏用户类型
            .map(
              (item) => PopupMenuItem<SearchResultType>(
                value: item,
                child: Row(
                  children: [
                    Icon(
                      _getTypeIcon(item),
                      size: BmTokens.iconMenu,
                      color: item == selectedType
                          ? colors.accent
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: BmTokens.s2),
                    Text(
                      _getTypeLabel(item),
                      style: type.label.copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            )
            .toList();
      },
    );
  }

  IconData _getTypeIcon(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return Icons.music_note_rounded;
      case SearchResultType.album:
        return Icons.album_rounded;
      case SearchResultType.author:
        return Icons.person_rounded;
      case SearchResultType.bangumi:
        return Icons.tv_rounded;
      case SearchResultType.topic:
        return Icons.tag_rounded;
      case SearchResultType.upuser:
        return Icons.account_circle_rounded;
    }
  }

  String _getTypeLabel(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return '单曲';
      case SearchResultType.album:
        return '专辑';
      case SearchResultType.author:
        return 'UP主';
      case SearchResultType.bangumi:
        return '番剧';
      case SearchResultType.topic:
        return '话题';
      case SearchResultType.upuser:
        return '用户';
    }
  }
}
