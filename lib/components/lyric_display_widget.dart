import 'package:flutter/material.dart';
import 'package:bilimusic/utils/lyric_parser.dart';

class LyricDisplayWidget extends StatefulWidget {
  final LyricParser? lyricParser;
  final Duration position;
  final bool isLyricSyncEnabled;
  final bool isLoading;
  final String? selectedLyricName;
  final String? selectedLyricArtist;
  final VoidCallback onOpenLyricMenu;

  const LyricDisplayWidget({
    super.key,
    required this.lyricParser,
    required this.position,
    required this.isLyricSyncEnabled,
    required this.isLoading,
    required this.selectedLyricName,
    required this.selectedLyricArtist,
    required this.onOpenLyricMenu,
  });

  @override
  State<LyricDisplayWidget> createState() => _LyricDisplayWidgetState();
}

class _LyricDisplayWidgetState extends State<LyricDisplayWidget> {
  final ScrollController _scrollController = ScrollController();
  LyricLine? _lastCurrentLine;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {});
  }

  @override
  void didUpdateWidget(LyricDisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 当歌词解析器或位置变化时，自动滚动到当前歌词
    if (widget.lyricParser != oldWidget.lyricParser ||
        widget.position != oldWidget.position) {
      _scrollToCurrentLyric();
    }
  }

  void _scrollToCurrentLyric() {
    if (!widget.isLyricSyncEnabled ||
        widget.lyricParser == null ||
        widget.lyricParser!.lines.isEmpty) {
      return;
    }

    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );

    // 只有当当前行发生变化时才滚动
    if (currentLine != null && currentLine != _lastCurrentLine) {
      _lastCurrentLine = currentLine;

      // 找到当前行在列表中的索引
      final index = widget.lyricParser!.lines.indexOf(currentLine);
      if (index != -1) {
        // 计算滚动位置，使当前行居中显示
        final lineHeight = 48.0;
        final viewportHeight = MediaQuery.of(context).size.height * 0.6;
        final targetPosition =
            index * lineHeight - (viewportHeight / 2) + (lineHeight / 2);

        // 滚动到目标位置
        _scrollController.animateTo(
          targetPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 5,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题区域
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.lyrics, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    '歌词',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.grey[900],
                    ),
                  ),
                ],
              ),

              // 歌词来源信息
              if (widget.selectedLyricName != null)
                GestureDetector(
                  onTap: widget.onOpenLyricMenu,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.selectedLyricName!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).primaryColor,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.selectedLyricArtist != null)
                          Text(
                            widget.selectedLyricArtist!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 10,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // 歌词显示区域
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildLyricContent(),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 歌词控制提示
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app,
                size: 16,
                color: Theme.of(context).primaryColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                '点击歌词来源可切换歌词',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricContent() {
    if (widget.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(
              '加载歌词中...',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.lyricParser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.music_note,
              size: 48,
              color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '请选择歌词来源',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.lyricParser!.lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lyrics,
              size: 48,
              color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无歌词',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      );
    }

    // 获取当前歌词行
    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: widget.lyricParser!.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lyricParser!.lines[index];
        final isCurrentLine = line == currentLine;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isCurrentLine
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isCurrentLine
                  ? Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                line.content,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: isCurrentLine ? 20 : 16,
                  fontWeight: isCurrentLine
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isCurrentLine
                      ? Theme.of(context).primaryColor
                      : (isDark ? Colors.grey[300] : Colors.grey[700]),
                  height: 1.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
