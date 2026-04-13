import 'package:flutter/material.dart';

class FunctionControlsWidget extends StatelessWidget {
  final bool isFavorite;
  final bool isLyricSyncEnabled;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final ValueChanged<bool> onToggleLyricSync;
  final VoidCallback onOpenLyricMenu;
  final bool compact;

  const FunctionControlsWidget({
    super.key,
    required this.isFavorite,
    required this.isLyricSyncEnabled,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onToggleLyricSync,
    required this.onOpenLyricMenu,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 收藏按钮
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.red : Theme.of(context).primaryColor,
            ),
            iconSize: compact ? 20 : 24,
            onPressed: onToggleFavorite,
          ),

          // 分享按钮
          IconButton(
            icon: const Icon(Icons.share),
            iconSize: compact ? 20 : 24,
            color: Theme.of(context).primaryColor,
            onPressed: onShare,
          ),

          // 歌词同步开关
          Row(
            children: [
              Icon(
                Icons.lyrics,
                size: compact ? 18 : 20,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 6),
              Switch(
                value: isLyricSyncEnabled,
                onChanged: onToggleLyricSync,
                activeColor: Theme.of(context).primaryColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),

          // 歌词菜单按钮
          IconButton(
            icon: const Icon(Icons.more_vert),
            iconSize: compact ? 20 : 24,
            color: Theme.of(context).primaryColor,
            onPressed: onOpenLyricMenu,
          ),
        ],
      ),
    );
  }
}
