import 'package:flutter/material.dart';
import 'package:bilimusic/models/search_result.dart';

/// 搜索类型Tab组件
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

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: types.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = types[index];
          final isSelected = type == selectedType;
          return _buildTypeChip(context, type, isSelected);
        },
      ),
    );
  }

  Widget _buildTypeChip(
    BuildContext context,
    SearchResultType type,
    bool isSelected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTypeChanged(type),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _getTypeLabel(type),
              style: TextStyle(
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
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

  const SearchTypeDropdown({
    super.key,
    required this.selectedType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SearchResultType>(
      initialValue: selectedType,
      onSelected: onTypeChanged,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getTypeIcon(selectedType),
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              _getTypeLabel(selectedType),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => SearchResultType.values
          .where((t) => t != SearchResultType.upuser) // 隐藏用户类型
          .map(
            (type) => PopupMenuItem<SearchResultType>(
              value: type,
              child: Row(
                children: [
                  Icon(
                    _getTypeIcon(type),
                    size: 18,
                    color: type == selectedType
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(_getTypeLabel(type)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  IconData _getTypeIcon(SearchResultType type) {
    switch (type) {
      case SearchResultType.video:
        return Icons.music_note;
      case SearchResultType.album:
        return Icons.album;
      case SearchResultType.author:
        return Icons.person;
      case SearchResultType.bangumi:
        return Icons.tv;
      case SearchResultType.topic:
        return Icons.tag;
      case SearchResultType.upuser:
        return Icons.account_circle;
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
