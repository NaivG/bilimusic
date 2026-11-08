import 'dart:ui';

import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/motion/spring_curve.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/widgets/lyric_view.dart';

/// 歌词滚动弹簧；`flutter_lyric` 只接受 Curve，用 [SpringCurve] 近似物理弹簧。
final Curve _lyricScrollCurve = SpringCurve.lyricScroll();

/// 歌词行切换（缩放 + 颜色）弹簧。
final Curve _lyricLineCurve = SpringCurve.lyricLine();

/// 统一歌词区域组件 —— 内部使用 [LyricController]/[LyricView] 完成渲染。
///
/// 父组件持有 [lyricController] 并在加载完成时调用 [LyricController.loadLyricModel]
/// 或 [LyricController.loadLyric];本组件仅负责渲染 + 驱动 [setProgress] + 转发点击事件。
class LyricSection extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? album;
  final LyricController? lyricController;
  final Duration position;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final bool isLoadingLyrics;
  final bool showHeader;

  /// 竖屏歌词页头部的封面缩略图。
  final Widget? heroCover;
  final Function(String)? onLyricSourceChanged;
  final Function(Duration)? onLyricTap;

  const LyricSection({
    super.key,
    this.title,
    this.artist,
    this.album,
    this.lyricController,
    required this.position,
    this.lyricSources = const [],
    this.selectedLyricId,
    this.isLoadingLyrics = false,
    this.showHeader = true,
    this.heroCover,
    this.onLyricSourceChanged,
    this.onLyricTap,
  });

  @override
  State<LyricSection> createState() => _LyricSectionState();
}

class _LyricSectionState extends State<LyricSection> {
  Duration _lastPosition = Duration.zero;
  LyricController? _hookedController;

  @override
  void didUpdateWidget(LyricSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != _lastPosition) {
      _lastPosition = widget.position;
      widget.lyricController?.setProgress(widget.position);
    }
    // controller 第一次挂上时立即同步一次进度 + 注册点击回调,避免 0→有歌时的延迟。
    if (widget.lyricController != _hookedController) {
      _hookedController = widget.lyricController;
      if (widget.lyricController != null) {
        widget.lyricController!.setProgress(widget.position);
        if (widget.onLyricTap != null) {
          widget.lyricController!.setOnTapLineCallback(widget.onLyricTap!);
        }
      }
    }
  }

  bool _isLandscapeMode() {
    final size = MediaQuery.of(context).size;
    return size.width >= LandscapeBreakpoints.tabletLandscapeMin &&
        size.width > size.height;
  }

  LyricStyle _buildStyle(bool isLandscape) {
    if (isLandscape) {
      final base = LandscapeBreakpoints.getOtherLyricFontSize(context);
      final active = LandscapeBreakpoints.getCurrentLyricFontSize(context);
      return LyricStyle(
        textStyle: TextStyle(
          fontSize: base,
          color: Colors.white.withValues(alpha: 0.45),
          height: 1.4,
        ),
        activeStyle: TextStyle(
          fontSize: active,
          color: Colors.white.withValues(alpha: 0.55),
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        translationStyle: TextStyle(
          fontSize: base - 6,
          color: Colors.white.withValues(alpha: 0.4),
          height: 1.35,
        ),
        translationActiveColor: Colors.white.withValues(alpha: 0.7),
        lineTextAlign: TextAlign.left,
        lineGap: 32,
        translationLineGap: 10,
        contentAlignment: CrossAxisAlignment.start,
        selectionAnchorPosition: 0.4,
        activeAnchorPosition: 0.4,
        activeAlignment: MainAxisAlignment.start,
        selectionAlignment: MainAxisAlignment.start,
        fadeRange: FadeRange(top: 80, bottom: 80),
        scrollDuration: BmMotion.lyricScrollMax,
        scrollCurve: _lyricScrollCurve,
        scrollAnimationBuilder: (_) => LyricScrollAnimationConfig(
          duration: BmMotion.lyricScrollMax,
          curve: _lyricScrollCurve,
        ),
        selectedColor: Colors.white,
        selectedTranslationColor: Colors.white.withValues(alpha: 0.85),
        selectionAutoResumeDuration: const Duration(milliseconds: 320),
        activeAutoResumeDuration: const Duration(milliseconds: 3000),
        selectionAutoResumeMode: SelectionAutoResumeMode.selecting,
        activeHighlightColor: Colors.white,
        activeHighlightExtraFadeWidth: active * 0.5,
        enableSwitchAnimation: true,
        switchEnterDuration: BmMotion.lyricSwitchMax,
        switchExitDuration: BmMotion.lyricSwitchMax,
        switchEnterCurve: _lyricLineCurve,
        switchExitCurve: _lyricLineCurve,
      );
    }
    // 方屏（手表 / 折叠外屏 / PiP）或窄幅横屏空间小，维持紧凑居中版式。
    final size = MediaQuery.sizeOf(context);
    if (SquareBreakpoints.shouldUseSquareLayout(context) ||
        size.height < size.width) {
      return _buildCompactPortraitStyle();
    }
    return _buildAppleMusicPortraitStyle();
  }

  /// 竖屏 AM 风格歌词：大字号 + 左对齐 + 逐字填充。
  ///
  /// 当前行按 100:97 行缩放略放大并加粗，未唱到的字压到 52% 白，
  /// 唱过的字由 [LyricStyle.activeHighlightColor] 逐字填成纯白；滚动与行切换
  /// 都走弹簧曲线，与横屏保持同一套动画。
  LyricStyle _buildAppleMusicPortraitStyle() {
    final width = MediaQuery.sizeOf(context).width;
    final lyricSize = width >= 600 ? 34.0 : 32.0;
    final activeSize = lyricSize / 0.97;
    final translationSize = lyricSize * 0.66;
    final lineGap = lyricSize * 0.9;

    return LyricStyle(
      textStyle: TextStyle(
        fontSize: lyricSize,
        color: Colors.white.withValues(alpha: 0.38),
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      activeStyle: TextStyle(
        fontSize: activeSize,
        color: Colors.white.withValues(alpha: 0.52),
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      translationStyle: TextStyle(
        fontSize: translationSize,
        color: Colors.white.withValues(alpha: 0.45),
        height: 1.35,
      ),
      translationActiveColor: Colors.white.withValues(alpha: 0.8),
      lineTextAlign: TextAlign.left,
      lineGap: lineGap,
      translationLineGap: 8,
      contentAlignment: CrossAxisAlignment.start,
      selectionAnchorPosition: 0.4,
      activeAnchorPosition: 0.36,
      activeAlignment: MainAxisAlignment.start,
      selectionAlignment: MainAxisAlignment.start,
      fadeRange: FadeRange(top: lyricSize * 3, bottom: lyricSize * 3),
      scrollDuration: BmMotion.lyricScrollMax,
      scrollCurve: _lyricScrollCurve,
      scrollAnimationBuilder: (_) => LyricScrollAnimationConfig(
        duration: BmMotion.lyricScrollMax,
        curve: _lyricScrollCurve,
      ),
      selectedColor: Colors.white,
      selectedTranslationColor: Colors.white.withValues(alpha: 0.85),
      selectionAutoResumeDuration: const Duration(milliseconds: 320),
      activeAutoResumeDuration: const Duration(milliseconds: 3000),
      selectionAutoResumeMode: SelectionAutoResumeMode.selecting,
      activeHighlightColor: Colors.white,
      activeHighlightExtraFadeWidth: activeSize * 0.5,
      enableSwitchAnimation: true,
      switchEnterDuration: BmMotion.lyricSwitchMax,
      switchExitDuration: BmMotion.lyricSwitchMax,
      switchEnterCurve: _lyricLineCurve,
      switchExitCurve: _lyricLineCurve,
    );
  }

  /// 紧凑居中版式：方屏 / 窄幅横屏使用，字号与间距都更保守。
  LyricStyle _buildCompactPortraitStyle() {
    return LyricStyle(
      textStyle: TextStyle(
        fontSize: 17,
        color: Colors.white.withValues(alpha: 0.55),
        height: 1.4,
      ),
      activeStyle: TextStyle(
        fontSize: 23,
        color: Colors.white.withValues(alpha: 0.7),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      translationStyle: TextStyle(
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.5),
        height: 1.35,
      ),
      translationActiveColor: Colors.white.withValues(alpha: 0.85),
      lineTextAlign: TextAlign.center,
      lineGap: 18,
      translationLineGap: 6,
      contentAlignment: CrossAxisAlignment.center,
      selectionAnchorPosition: 0.4,
      activeAnchorPosition: 0.4,
      activeAlignment: MainAxisAlignment.center,
      selectionAlignment: MainAxisAlignment.center,
      fadeRange: FadeRange(top: 60, bottom: 60),
      scrollDuration: const Duration(milliseconds: 320),
      scrollCurve: Curves.easeOutCubic,
      selectedColor: Colors.white,
      selectedTranslationColor: Colors.white.withValues(alpha: 0.85),
      selectionAutoResumeDuration: const Duration(milliseconds: 320),
      activeAutoResumeDuration: const Duration(milliseconds: 3000),
      selectionAutoResumeMode: SelectionAutoResumeMode.selecting,
      activeHighlightColor: Colors.white,
      activeHighlightExtraFadeWidth: 24,
      enableSwitchAnimation: true,
      switchEnterDuration: const Duration(milliseconds: 220),
      switchExitDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscapeMode();
    final style = _buildStyle(isLandscape);

    if (isLandscape) {
      return _buildLandscapeLayout(style);
    }
    return _buildPortraitLayout(style);
  }

  Widget _buildLandscapeLayout(LyricStyle style) {
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader) ...[
                _buildSongInfoHeader(isLandscape: true),
                const SizedBox(height: 24),
                const SizedBox(height: 16),
              ],
              Expanded(child: _buildLyricContent(style)),
            ],
          ),
          if (!widget.isLoadingLyrics && widget.lyricSources.isNotEmpty)
            Positioned(right: 0, bottom: 16, child: _buildLyricSourceButton()),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(LyricStyle style) {
    if (widget.heroCover != null) {
      return _buildPortraitHeroLayout(style);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                _buildSongInfoHeader(isLandscape: false),
                const SizedBox(height: 20),
                Expanded(child: _buildLyricContent(style)),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (!widget.isLoadingLyrics && widget.lyricSources.isNotEmpty)
            Positioned(right: 0, bottom: 24, child: _buildLyricSourceButton()),
        ],
      ),
    );
  }

  /// 竖屏播放页的歌词汇总页：小封面 + 曲名 / 歌手，歌词占满剩余高度。
  Widget _buildPortraitHeroLayout(LyricStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            _buildHeroHeader(),
            const SizedBox(height: 18),
            Expanded(child: _buildLyricContent(style)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Row(
      children: [
        widget.heroCover!,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                widget.artist ?? '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (!widget.isLoadingLyrics && widget.lyricSources.isNotEmpty) ...[
          const SizedBox(width: 10),
          _buildLyricSourceButton(compact: true),
        ],
      ],
    );
  }

  Widget _buildSongInfoHeader({required bool isLandscape}) {
    final titleSize = isLandscape ? 32.0 : 22.0;
    final artistSize = isLandscape ? 20.0 : 16.0;
    final albumSize = isLandscape ? 16.0 : 13.0;
    final alignment = isLandscape
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlign = isLandscape ? TextAlign.left : TextAlign.center;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          widget.title ?? '',
          style: TextStyle(
            color: Colors.white,
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
        const SizedBox(height: 6),
        Text(
          widget.artist ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: artistSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
        const SizedBox(height: 4),
        Text(
          widget.album ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: albumSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        ),
      ],
    );
  }

  Widget _buildLyricContent(LyricStyle style) {
    if (widget.isLoadingLyrics) {
      return _buildLoadingState();
    }
    final controller = widget.lyricController;
    if (controller == null) {
      return _buildEmptyState('选择歌词来源后显示歌词');
    }
    final model = controller.lyricNotifier.value;
    if (model == null || model.lines.isEmpty) {
      return _buildEmptyState('暂无歌词');
    }

    return RepaintBoundary(
      child: LyricView(controller: controller, style: style),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(
        color: Colors.white.withValues(alpha: 0.6),
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildEmptyState(String message) {
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
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricSourceButton({bool compact = false}) {
    final buttonPadding = compact ? 9.0 : 10.0;
    final iconSize = compact ? 20.0 : 22.0;
    final radius = compact ? 20.0 : 24.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: PopupMenuButton<String>(
          initialValue: widget.selectedLyricId,
          color: Colors.grey[900]!.withValues(alpha: 0.95),
          tooltip: '歌词来源',
          onSelected: (id) => widget.onLyricSourceChanged?.call(id),
          itemBuilder: (context) {
            return widget.lyricSources.map((source) {
              final selected = source.id == widget.selectedLyricId;
              return PopupMenuItem<String>(
                value: source.id,
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check : null,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            padding: EdgeInsets.all(buttonPadding),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.lyrics_outlined,
              color: Colors.white.withValues(alpha: 0.7),
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
