import 'package:flutter/material.dart';

import '../models/music.dart' as model;

class PageSelectorWidget extends StatelessWidget {
  final model.Music music;
  final int currentPageIndex;
  final ValueChanged<int> onPageChanged;
  final bool compact;

  const PageSelectorWidget({
    super.key,
    required this.music,
    required this.currentPageIndex,
    required this.onPageChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (music.pages.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.list,
                size: compact ? 16 : 18,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                '分P选择',
                style: compact
                    ? Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      )
                    : Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: currentPageIndex,
                items: music.pages.map((page) {
                  final index = music.pages.indexOf(page);
                  return DropdownMenuItem(
                    value: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 12.0,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: currentPageIndex == index
                                  ? Theme.of(context).primaryColor
                                  : Theme.of(context).dividerColor,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: currentPageIndex == index
                                      ? Colors.white
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyMedium?.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              page.part,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            page.formattedDuration,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Theme.of(context).hintColor),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (index) {
                  if (index != null) {
                    onPageChanged(index);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                dropdownColor: Theme.of(context).cardColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
