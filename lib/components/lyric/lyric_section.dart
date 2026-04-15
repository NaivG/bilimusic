import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bilimusic/utils/lyric_parser.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/components/lyric/lyric_line_widget.dart';
import 'package:bilimusic/components/lyric/lyric_source.dart';

/// 统一歌词区域组件
/// 同时支持横屏和竖屏布局
class LyricSection extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? album;
  final LyricParser? lyricParser;
  final Duration position;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final bool isLoadingLyrics;
  final Function(String)? onLyricSourceChanged;
  final Function(Duration)? onLyricTap;

  const LyricSection({
    super.key,
    this.title,
    this.artist,
    this.album,
    this.lyricParser,
    required this.position,
    this.lyricSources = const [],
    this.selectedLyricId,
    this.isLoadingLyrics = false,
    this.onLyricSourceChanged,
    this.onLyricTap,
  });

  @override
  State<LyricSection> createState() => _LyricSectionState();
}

class _LyricSectionState extends State<LyricSection> {
  late ScrollController _scrollController;
  LyricLine? _lastCurrentLine;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LyricSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      _scrollToCurrentLyric();
    }
  }

  void _scrollToCurrentLyric() {
    if (widget.lyricParser == null ||
        widget.lyricParser!.lines.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }

    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );

    if (currentLine != null && currentLine != _lastCurrentLine) {
      _lastCurrentLine = currentLine;
      final index = widget.lyricParser!.lines.indexOf(currentLine);
      if (index != -1) {
        final isLandscape = _isLandscapeMode();
        final lineHeight = isLandscape ? 52.0 : 48.0;
        final viewportHeight = _scrollController.position.viewportDimension;
        final targetPosition =
            index * lineHeight - (viewportHeight * 0.35) + (lineHeight / 2);

        _scrollController.animateTo(
          targetPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  bool _isLandscapeMode() {
    final size = MediaQuery.of(context).size;
    return size.width >= LandscapeBreakpoints.tabletLandscapeMin &&
        size.width > size.height;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscapeMode();

    if (isLandscape) {
      return _buildLandscapeLayout();
    } else {
      return _buildPortraitLayout();
    }
  }

  Widget _buildLandscapeLayout() {
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSongInfoHeader(),
          const SizedBox(height: 24),
          if (!widget.isLoadingLyrics) _buildLyricSourceSelector(),
          const SizedBox(height: 16),
          Expanded(child: _buildLyricContent()),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          _buildPortraitHeader(),
          const SizedBox(height: 16),
          Expanded(child: _buildLyricContent()),
          const SizedBox(height: 12),
          _buildPortraitFooter(),
        ],
      ),
    );
  }

  Widget _buildPortraitHeader() {
    return Row(
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.grey[900],
              ),
            ),
          ],
        ),
        if (widget.selectedLyricId != null) _buildLyricSourceSelector(),
      ],
    );
  }

  Widget _buildPortraitFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.touch_app,
          size: 16,
          color: Theme.of(context).primaryColor.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Text(
          '点击歌词可跳转播放',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSongInfoHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Text(
          widget.artist ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 20,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          widget.album ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildLyricSourceSelector() {
    if (widget.lyricSources.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: DropdownButton<String>(
            value: widget.selectedLyricId,
            dropdownColor: Colors.grey[900]!.withValues(alpha: 0.95),
            underline: const SizedBox(),
            icon: Icon(
              Icons.arrow_drop_down,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
            items: widget.lyricSources.map((source) {
              return DropdownMenuItem<String>(
                value: source.id,
                child: Text(source.name),
              );
            }).toList(),
            onChanged: (id) {
              if (id != null) {
                widget.onLyricSourceChanged?.call(id);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLyricContent() {
    if (widget.isLoadingLyrics) {
      return _buildLoadingState();
    }

    if (widget.lyricParser == null) {
      return _buildEmptyState('选择歌词来源后显示歌词');
    }

    if (widget.lyricParser!.lines.isEmpty) {
      return _buildEmptyState('暂无歌词');
    }

    return _buildLyricList();
  }

  Widget _buildLoadingState() {
    final isLandscape = _isLandscapeMode();

    if (isLandscape) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.6),
          strokeWidth: 2,
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Theme.of(context).primaryColor),
          const SizedBox(height: 16),
          Text(
            '加载歌词中...',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    final isLandscape = _isLandscapeMode();

    if (isLandscape) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

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
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricList() {
    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );
    final isLandscape = _isLandscapeMode();
    final currentFontSize = isLandscape
        ? LandscapeBreakpoints.getCurrentLyricFontSize(context)
        : 20.0;
    final otherFontSize = isLandscape
        ? LandscapeBreakpoints.getOtherLyricFontSize(context)
        : 16.0;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.25,
      ),
      itemCount: widget.lyricParser!.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lyricParser!.lines[index];
        final isCurrentLine = line == currentLine;

        return LyricLineWidget(
          line: line,
          isCurrentLine: isCurrentLine,
          currentFontSize: currentFontSize,
          otherFontSize: otherFontSize,
          onTap: widget.onLyricTap,
        );
      },
    );
  }
}
