import 'dart:ui';

import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/motion/spring_curve.dart';
import 'package:bilimusic/shared/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';

/// 歌词滚动的弹簧曲线。
///
/// `flutter_lyric` 4.x 的 [LyricScrollAnimation] 仍然接受任意 [Curve]，
/// 这里继续用 [SpringCurve] 近似物理弹簧。
final Curve _lyricScrollCurve = SpringCurve.lyricScroll();

/// 切句 / 行运动 / 逐字效果 / 距离模糊统一取自官方 [LyricPresets.appleMusic]。

/// 前奏 / 间奏小圆点设置覆盖。
const LyricCountdown _countdown = LyricCountdown(
  dotCount: 3,
  dotDuration: Duration(seconds: 3),
  breathDuration: Duration(milliseconds: 1600),
  dotSize: 10,
  dotSpacing: 10,
  height: 32,
  spacing: 24,
  color: Colors.white,
);

/// 统一歌词区域组件 —— 内部使用 [LyricController]/[LyricView] 完成渲染。
///
/// 父组件持有 [lyricController]，并在载荷就绪时调用
/// [LyricController.loadDocument]；本组件只负责排版（预设）、点击转发和
/// 空态，不再逐帧驱动播放进度。
class LyricSection extends StatelessWidget {
  final String? title;
  final String? artist;
  final String? album;
  final LyricController? lyricController;
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
    this.lyricSources = const [],
    this.selectedLyricId,
    this.isLoadingLyrics = false,
    this.showHeader = true,
    this.heroCover,
    this.onLyricSourceChanged,
    this.onLyricTap,
  });

  bool _isLandscapeMode(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width >= LandscapeBreakpoints.tabletLandscapeMin &&
        size.width > size.height;
  }

  LyricPreset _buildPreset(BuildContext context, bool isLandscape) {
    if (isLandscape) return _buildLandscapePreset(context);
    // 方屏（手表 / 折叠外屏 / PiP）或窄幅横屏空间小，维持紧凑居中版式。
    final size = MediaQuery.sizeOf(context);
    if (SquareBreakpoints.shouldUseSquareLayout(context) ||
        size.height < size.width) {
      return _buildCompactPreset();
    }
    return _buildAppleMusicPreset(context);
  }

  /// 横屏：保留大字号双档排版，切句/逐字动效改用 Apple Music 那一套。
  LyricPreset _buildLandscapePreset(BuildContext context) {
    final base = LandscapeBreakpoints.getOtherLyricFontSize(context);
    final active = LandscapeBreakpoints.getCurrentLyricFontSize(context);
    final am = LyricPresets.appleMusic;
    return LyricPreset(
      textStyle: TextStyle(
        fontSize: base,
        color: Colors.white.withValues(alpha: 0.45),
        height: 1.4,
      ),
      activeTextStyle: TextStyle(
        fontSize: active,
        color: Colors.white.withValues(alpha: 0.55),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      translationTextStyle: TextStyle(
        fontSize: base - 6,
        color: Colors.white.withValues(alpha: 0.4),
        height: 1.35,
      ),
      activeTranslationTextStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
      ),
      textAlign: TextAlign.left,
      contentAlignment: LyricContentAlignment.start,
      // 页面外层已经有横向 padding，预设里不再叠加。
      padding: EdgeInsets.zero,
      lineSpacing: 32,
      translationSpacing: 10,
      activeAnchor: const LyricAnchor.fraction(
        0.4,
        target: LyricAnchorTarget.mainText,
      ),
      selectionAnchor: const LyricAnchor.fraction(
        0.4,
        target: LyricAnchorTarget.mainText,
      ),
      edgeFade: const LyricEdgeFade.pixels(top: 80, bottom: 80),
      scrollAnimation: LyricScrollAnimation.fixed(
        duration: BmMotion.lyricScrollMax,
        curve: _lyricScrollCurve,
      ),
      selectedTextColor: Colors.white,
      selectedTranslationTextColor: Colors.white.withValues(alpha: 0.85),
      selectionSnapDelay: const Duration(milliseconds: 320),
      resumeDelay: const Duration(seconds: 3),
      selectionSnapMode: LyricSelectionSnapMode.afterScroll,
      highlight: LyricHighlight.solid(
        Colors.white,
        tailFadeWidth: active * 0.5,
      ),
      lineTransition: am.lineTransition,
      lineMotion: am.lineMotion,
      wordEffects: am.wordEffects,
      distanceBlur: am.distanceBlur,
      countdown: const LyricCountdown.none(),
    );
  }

  /// 竖屏 AM 预设，以 4.1 的 [LyricPresets.appleMusic] 为基底。
  LyricPreset _buildAppleMusicPreset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final lyricSize = width >= 600 ? 34.0 : 32.0;
    final base = LyricPresets.appleMusic;
    return base.copyWith(
      textStyle: base.textStyle.copyWith(fontSize: lyricSize, height: 1.3),
      translationTextStyle: base.translationTextStyle.copyWith(
        fontSize: lyricSize * 0.5,
        height: 1.4,
      ),
      padding: EdgeInsets.zero,
      lineSpacing: lyricSize * 0.85,
      translationSpacing: 8,
      activeAnchor: const LyricAnchor.fraction(
        0.38,
        target: LyricAnchorTarget.mainText,
      ),
      selectionAnchor: const LyricAnchor.fraction(
        0.38,
        target: LyricAnchorTarget.mainText,
      ),
      highlight: const LyricHighlight.solid(Colors.white, tailFadeWidth: 20),
      scrollAnimation: LyricScrollAnimation.fixed(
        duration: BmMotion.lyricScrollMax,
        curve: _lyricScrollCurve,
      ),
      countdown: _countdown,
    );
  }

  /// 紧凑居中版式：方屏 / 窄幅横屏使用，字号与间距都更保守。
  LyricPreset _buildCompactPreset() {
    return LyricPreset(
      textStyle: TextStyle(
        fontSize: 17,
        color: Colors.white.withValues(alpha: 0.55),
        height: 1.4,
      ),
      activeTextStyle: TextStyle(
        fontSize: 23,
        color: Colors.white.withValues(alpha: 0.7),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      translationTextStyle: TextStyle(
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.5),
        height: 1.35,
      ),
      activeTranslationTextStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
      ),
      textAlign: TextAlign.center,
      contentAlignment: LyricContentAlignment.center,
      padding: EdgeInsets.zero,
      lineSpacing: 18,
      translationSpacing: 6,
      activeAnchor: const LyricAnchor.fraction(
        0.4,
        target: LyricAnchorTarget.mainText,
      ),
      selectionAnchor: const LyricAnchor.fraction(
        0.4,
        target: LyricAnchorTarget.mainText,
      ),
      edgeFade: const LyricEdgeFade.pixels(top: 60, bottom: 60),
      scrollAnimation: LyricScrollAnimation.fixed(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
      selectedTextColor: Colors.white,
      selectedTranslationTextColor: Colors.white.withValues(alpha: 0.85),
      selectionSnapDelay: const Duration(milliseconds: 320),
      resumeDelay: const Duration(seconds: 3),
      selectionSnapMode: LyricSelectionSnapMode.afterScroll,
      highlight: const LyricHighlight.solid(Colors.white, tailFadeWidth: 24),
      // 紧凑版正文/当前句字号差 6px，用 4.1 的 classic（保留双样式尺寸
      // 过渡）而不是纯淡入，否则切句时字号会瞬跳。
      lineTransition: LyricLineTransitions.classic.copyWith(
        enterDuration: const Duration(milliseconds: 220),
        exitDuration: const Duration(milliseconds: 220),
      ),
      countdown: const LyricCountdown.none(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscapeMode(context);
    final preset = _buildPreset(context, isLandscape);

    if (isLandscape) {
      return _buildLandscapeLayout(context, preset);
    }
    return _buildPortraitLayout(preset);
  }

  Widget _buildLandscapeLayout(BuildContext context, LyricPreset preset) {
    final padding = LandscapeBreakpoints.getHorizontalPadding(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                _buildSongInfoHeader(isLandscape: true),
                const SizedBox(height: 24),
                const SizedBox(height: 16),
              ],
              Expanded(child: _buildLyricContent(preset)),
            ],
          ),
          if (!isLoadingLyrics && lyricSources.isNotEmpty)
            Positioned(right: 0, bottom: 16, child: _buildLyricSourceButton()),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout(LyricPreset preset) {
    if (heroCover != null) {
      return _buildPortraitHeroLayout(preset);
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
                Expanded(child: _buildLyricContent(preset)),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (!isLoadingLyrics && lyricSources.isNotEmpty)
            Positioned(right: 0, bottom: 24, child: _buildLyricSourceButton()),
        ],
      ),
    );
  }

  /// 竖屏播放页的歌词汇总页：小封面 + 曲名 / 歌手，歌词占满剩余高度。
  Widget _buildPortraitHeroLayout(LyricPreset preset) {
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
            Expanded(child: _buildLyricContent(preset)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Row(
      children: [
        heroCover!,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title ?? '',
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
                artist ?? '',
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
        if (!isLoadingLyrics && lyricSources.isNotEmpty) ...[
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
          title ?? '',
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
          artist ?? '',
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
          album ?? '',
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

  Widget _buildLyricContent(LyricPreset preset) {
    if (isLoadingLyrics) {
      return _buildLoadingState();
    }
    final controller = lyricController;
    if (controller == null) {
      return _buildEmptyState('选择歌词来源后显示歌词');
    }
    final document = controller.document;
    if (document == null || document.lines.isEmpty) {
      return _buildEmptyState('暂无歌词');
    }

    final tap = onLyricTap;
    return RepaintBoundary(
      child: LyricView(
        controller: controller,
        preset: preset,
        // 4.x 的 seekPosition 已经扣掉文档 offset 与用户校准偏移，直接拿去 seek。
        onLineTap: tap == null ? null : (details) => tap(details.seekPosition),
      ),
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
          initialValue: selectedLyricId,
          color: Colors.grey[900]!.withValues(alpha: 0.95),
          tooltip: '歌词来源',
          onSelected: (id) => onLyricSourceChanged?.call(id),
          itemBuilder: (context) {
            return lyricSources.map((source) {
              final selected = source.id == selectedLyricId;
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
