import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:bilimusic/utils/responsive.dart';
import 'package:bilimusic/utils/lyric_parser.dart';

/// 横屏歌词区域组件
/// 包含歌曲信息和可滚动歌词列表
class LandscapeLyricSection extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final LyricParser? lyricParser;
  final Duration position;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final bool isLoadingLyrics;
  final Function(String)? onLyricSourceChanged;
  final Function(Duration)? onLyricTap;

  const LandscapeLyricSection({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    this.lyricParser,
    required this.position,
    this.lyricSources = const [],
    this.selectedLyricId,
    this.isLoadingLyrics = false,
    this.onLyricSourceChanged,
    this.onLyricTap,
  });

  @override
  State<LandscapeLyricSection> createState() => _LandscapeLyricSectionState();
}

class _LandscapeLyricSectionState extends State<LandscapeLyricSection> {
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
  void didUpdateWidget(LandscapeLyricSection oldWidget) {
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
        final lineHeight = 52.0;
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

  @override
  Widget build(BuildContext context) {
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 歌曲信息头部
          _buildSongInfoHeader(),
          const SizedBox(height: 24),
          // 歌词来源选择器
          if (!widget.isLoadingLyrics) _buildLyricSourceSelector(),
          const SizedBox(height: 16),
          // 歌词列表
          Expanded(child: _buildLyricContent()),
        ],
      ),
    );
  }

  Widget _buildSongInfoHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          widget.title,
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
        // 艺术家
        Text(
          widget.artist,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 20,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        // 专辑
        Text(
          widget.album,
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
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.6),
          strokeWidth: 2,
        ),
      );
    }

    if (widget.lyricParser == null) {
      return _buildEmptyLyric('选择歌词来源后显示歌词');
    }

    if (widget.lyricParser!.lines.isEmpty) {
      return _buildEmptyLyric('暂无歌词');
    }

    return _buildLyricList();
  }

  Widget _buildEmptyLyric(String message) {
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

  Widget _buildLyricList() {
    final currentLine = widget.lyricParser!.getCurrentLine(
      widget.position.inMilliseconds / 1000,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.25,
      ),
      itemCount: widget.lyricParser!.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lyricParser!.lines[index];
        final isCurrentLine = line == currentLine;
        final currentFontSize = LandscapeBreakpoints.getCurrentLyricFontSize(
          context,
        );
        final otherFontSize = LandscapeBreakpoints.getOtherLyricFontSize(
          context,
        );

        return GestureDetector(
          onTap: () {
            widget.onLyricTap?.call(Duration(seconds: line.time.toInt()));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: isCurrentLine ? currentFontSize : otherFontSize,
                fontWeight: isCurrentLine ? FontWeight.w700 : FontWeight.w500,
                color: isCurrentLine
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),
                height: 1.5,
              ),
              textAlign: TextAlign.left,
              child: Text(line.content),
            ),
          ),
        );
      },
    );
  }
}

/// 歌词来源数据类
class LyricSource {
  final String id;
  final String name;

  const LyricSource({required this.id, required this.name});

  @override
  String toString() => name;
}

/// 带入场动画的歌词区域组件
class AnimatedLandscapeLyricSection extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final LyricParser? lyricParser;
  final Duration position;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final bool isLoadingLyrics;
  final Function(String)? onLyricSourceChanged;
  final Function(Duration)? onLyricTap;

  const AnimatedLandscapeLyricSection({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    this.lyricParser,
    required this.position,
    this.lyricSources = const [],
    this.selectedLyricId,
    this.isLoadingLyrics = false,
    this.onLyricSourceChanged,
    this.onLyricTap,
  });

  @override
  State<AnimatedLandscapeLyricSection> createState() =>
      _AnimatedLandscapeLyricSectionState();
}

class _AnimatedLandscapeLyricSectionState
    extends State<AnimatedLandscapeLyricSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
          ),
        );

    // 延迟启动动画
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: LandscapeLyricSection(
          title: widget.title,
          artist: widget.artist,
          album: widget.album,
          lyricParser: widget.lyricParser,
          position: widget.position,
          lyricSources: widget.lyricSources,
          selectedLyricId: widget.selectedLyricId,
          isLoadingLyrics: widget.isLoadingLyrics,
          onLyricSourceChanged: widget.onLyricSourceChanged,
          onLyricTap: widget.onLyricTap,
        ),
      ),
    );
  }
}
