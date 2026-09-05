import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/features/player/widgets/landscape_seek_bar.dart';
import 'package:bilimusic/features/player/widgets/playback_buttons.dart';
import 'package:bilimusic/features/player/now_playing/apple_cover.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/utils/animations.dart';

/// 详情页单面板
/// 这回切成自适应应该好一点
/// 封面 + 歌曲信息 + 收藏/分享 + 进度条 + 5 个播放按钮 + 音量（+「查看歌词」入口）。
/// 切歌时，封面与歌曲信息行淡入 + 上滑，其余控件保持不动。
///
/// 尺寸与间距完全由实际分配到的宽高决定（[LayoutBuilder]，不读屏幕断点）：
/// - 宽度 → 水平留白、封面、字号、按钮尺寸，并保证控制行不溢出；
/// - 高度 → 封面的高度预算，以及纵向节奏：
///   内容放得下时，富余高度以弹性间距分摊到封面上下（每侧不超过封面的一半），
///   超长屏（如 22:9）由此消化底部空白；放不下时（如横屏窄面板）整体可滚动。
class AlbumSection extends ConsumerStatefulWidget {
  final String coverUrl;
  final String title;
  final String artist;
  final String album;
  final Color? dominantColor;
  final bool isFavorite;
  final String? trackId;
  final VoidCallback? onFavoritePressed;
  final VoidCallback? onSharePressed;
  final VoidCallback? onCoverTap;
  final VoidCallback? onShowLyrics;

  // 播放控制
  final bool isPlaying;
  final IconData playModeIcon;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayModeToggle;
  final VoidCallback? onPlaylist;

  const AlbumSection({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.artist,
    required this.album,
    this.dominantColor,
    this.isFavorite = false,
    this.trackId,
    this.onFavoritePressed,
    this.onSharePressed,
    this.onCoverTap,
    this.onShowLyrics,
    required this.isPlaying,
    required this.playModeIcon,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onPlayModeToggle,
    this.onPlaylist,
  });

  @override
  ConsumerState<AlbumSection> createState() => _AlbumSectionState();
}

class _AlbumSectionState extends ConsumerState<AlbumSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  String? _previousTrackId;

  @override
  void initState() {
    super.initState();
    _previousTrackId = widget.trackId;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
          ),
        );

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(AlbumSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackId != null &&
        widget.trackId != _previousTrackId &&
        widget.trackId != oldWidget.trackId) {
      _previousTrackId = widget.trackId;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _animated(Widget child) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _AlbumMetrics.resolve(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          hasLyricsEntry: widget.onShowLyrics != null,
          textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
        );

        // 富余高度 ≥ 24（估算余量）才走填充模式，避免临界抖动。
        final fill = constraints.maxHeight.isFinite &&
            constraints.maxHeight - metrics.estimatedContentHeight >= 24;

        if (!fill) {
          // 高度不受限（外层是滚动容器）或内容放不下 → 滚动模式，间距取基础值。
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.horizontalPadding,
              vertical: metrics.verticalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: _buildContent(metrics, fillHeight: false),
            ),
          );
        }

        // 填充模式：富余高度由封面上下两个弹性间距实时吸收（零估算误差），
        // 每侧最多吃掉半个封面，再多的留白沉到面板底部。
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.horizontalPadding,
            vertical: metrics.verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _buildContent(metrics, fillHeight: true),
          ),
        );
      },
    );
  }

  List<Widget> _buildContent(_AlbumMetrics m, {required bool fillHeight}) {
    return [
      // 封面（带切歌过渡）；填充模式下上下各留一个弹性间距
      if (fillHeight)
        Flexible(child: SizedBox(height: m.coverSize * 0.5)),
      _animated(
        AppleMusicCover(
          coverUrl: widget.coverUrl,
          dominantColor: widget.dominantColor,
          onTap: widget.onCoverTap,
          customSize: m.coverSize,
        ),
      ),
      if (fillHeight)
        Flexible(child: SizedBox(height: m.coverSize * 0.5)),
      SizedBox(height: m.gapCoverInfo),
      // 歌曲信息 + 收藏/分享（带切歌过渡）
      _animated(_buildInfoRow(m)),
      SizedBox(height: m.gapInfoSeek),
      // 进度条（无 thumb，可拖拽，带时长标签）
      const LandscapeSeekBar(
        color: Colors.white,
        widgetHeight: 20,
        seekBarHeight: 8,
      ),
      SizedBox(height: m.gapSeekControls),
      // 5 个播放控制按钮
      _buildControlRow(m),
      SizedBox(height: m.gapControlsVolume),
      // 音量调节（喇叭图标 + 细条）
      _buildVolumeControl(m),
      // 「查看歌词」入口
      if (widget.onShowLyrics != null) ...[
        SizedBox(height: m.gapVolumeLyrics),
        _buildLyricsEntry(),
      ],
      SizedBox(height: m.gapVolumeLyrics), // 这边直接复用，让底部留白更大一点，避免贴边
    ];
  }

  Widget _buildVolumeControl(_AlbumMetrics m) {
    final volume = ref.watch(volumeProvider);
    final commands = ref.read(playbackCommandsProvider.notifier);
    final isMuted = volume == 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TapScaleWidget(
          pressedScale: 0.9,
          onTap: () => commands.toggleMute(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: m.volumeSliderWidth,
          height: 20,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              trackShape: const FullWidthTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayColor: Colors.transparent,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              onChanged: commands.setVolume,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(_AlbumMetrics m) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSongInfo(m)),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleIconButton(
              icon: widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              iconColor: widget.isFavorite
                  ? (Colors.red[400] ?? Colors.red)
                  : Colors.white,
              size: m.actionSize,
              iconSize: m.actionSize * 0.5,
              onTap: widget.onFavoritePressed,
            ),
            const SizedBox(height: 10),
            CircleIconButton(
              icon: Icons.share_outlined,
              iconColor: Colors.white,
              size: m.actionSize,
              iconSize: m.actionSize * 0.5,
              onTap: widget.onSharePressed,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSongInfo(_AlbumMetrics m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(
            color: Colors.white,
            fontSize: m.titleFontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            height: 1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 4),
        Text(
          widget.artist,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: m.artistFontSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
        const SizedBox(height: 2),
        Text(
          widget.album,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: m.albumFontSize,
            fontWeight: FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.left,
        ),
      ],
    );
  }

  Widget _buildControlRow(_AlbumMetrics m) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 播放模式
        PlaybackControlButton(
          icon: widget.playModeIcon,
          size: m.sideButtonSize,
          iconSize: m.sideIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: widget.onPlayModeToggle,
        ),
        SizedBox(width: m.gapSide),
        // 上一曲
        PlaybackControlButton(
          icon: Icons.skip_previous,
          size: m.sideButtonSize,
          iconSize: m.sideIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: widget.onPrevious,
        ),
        SizedBox(width: m.gapMain),
        // 播放/暂停
        PlaybackPlayPauseButton(
          isPlaying: widget.isPlaying,
          size: m.mainButtonSize,
          iconSize: m.mainIconSize,
          onTap: widget.onPlayPause,
        ),
        SizedBox(width: m.gapMain),
        // 下一曲
        PlaybackControlButton(
          icon: Icons.skip_next,
          size: m.sideButtonSize,
          iconSize: m.sideIconSize,
          iconColor: Colors.white.withValues(alpha: 0.9),
          onTap: widget.onNext,
        ),
        SizedBox(width: m.gapSide),
        // 播放列表
        PlaybackControlButton(
          icon: Icons.queue_music,
          size: m.sideButtonSize,
          iconSize: m.sideIconSize,
          iconColor: Colors.white.withValues(alpha: 0.7),
          onTap: widget.onPlaylist,
        ),
      ],
    );
  }

  Widget _buildLyricsEntry() {
    return TapScaleWidget(
      pressedScale: 0.95,
      onTap: widget.onShowLyrics,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              color: Colors.white.withValues(alpha: 0.85),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '查看歌词',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 由实际分配到的宽高解析出的布局度量。
class _AlbumMetrics {
  final double horizontalPadding;
  final double verticalPadding;
  final double coverSize;
  final double titleFontSize;
  final double artistFontSize;
  final double albumFontSize;
  final double actionSize;
  final double mainButtonSize;
  final double sideButtonSize;
  final double mainIconSize;
  final double sideIconSize;
  final double gapMain;
  final double gapSide;
  final double gapCoverInfo;
  final double gapInfoSeek;
  final double gapSeekControls;
  final double gapControlsVolume;
  final double gapVolumeLyrics;
  final double volumeSliderWidth;
  final double estimatedContentHeight;

  const _AlbumMetrics({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.coverSize,
    required this.titleFontSize,
    required this.artistFontSize,
    required this.albumFontSize,
    required this.actionSize,
    required this.mainButtonSize,
    required this.sideButtonSize,
    required this.mainIconSize,
    required this.sideIconSize,
    required this.gapMain,
    required this.gapSide,
    required this.gapCoverInfo,
    required this.gapInfoSeek,
    required this.gapSeekControls,
    required this.gapControlsVolume,
    required this.gapVolumeLyrics,
    required this.volumeSliderWidth,
    required this.estimatedContentHeight,
  });

  factory _AlbumMetrics.resolve({
    required double maxWidth,
    required double maxHeight,
    required bool hasLyricsEntry,
    required double textScale,
  }) {
    final width = maxWidth.isFinite ? maxWidth : 360.0;
    final horizontalPadding = (width * 0.055).clamp(16.0, 40.0);
    final contentWidth = width - horizontalPadding * 2;

    // 收藏/分享圆钮只依赖宽度
    final actionSize = (contentWidth * 0.14).clamp(40.0, 52.0);
    final actionColumnHeight = actionSize * 2 + 10;

    // 封面宽度预算：≤ 内容宽的 80%，收在 200~320
    final widthCover =
        math.min(contentWidth, (contentWidth * 0.8).clamp(200.0, 320.0));

    // 封面高度预算：内容高 ≈ 固定件 + 系数 × cover
    //（cover + 55% 基础间距 + 24% 主按钮，有歌词入口再 +10% 间距），
    // 目标让内容约占可用高度的 95%，剩余交给弹性间距。字号按封顶值估，偏保守。
    final infoRowAtCap = math.max(
      2 * 22.0 * 1.25 + 4 + 15.0 * 1.4 + 2 + 13.5 * 1.4, // 字号封顶时的文本列
      actionColumnHeight,
    );
    final fixedHeight = 24.0 /*纵向 padding*/ +
        20.0 /*进度条*/ +
        32.0 /*音量行*/ +
        (hasLyricsEntry ? 48.0 * textScale : 0.0) /*歌词入口（文字随缩放）*/ +
        24.0 /*估算余量*/ +
        infoRowAtCap * textScale;
    final coverHeightFactor = hasLyricsEntry ? 1.9 : 1.8;
    final heightCover = maxHeight.isFinite
        ? ((maxHeight * 0.95 - fixedHeight) / coverHeightFactor)
            .clamp(160.0, 400.0)
        : double.infinity;
    final coverSize = math.min(widthCover, heightCover);

    // 字号跟随封面（原横屏策略，封顶到原竖屏字号）
    final titleFontSize = (coverSize * 0.11).clamp(16.0, 22.0);
    final artistFontSize = (coverSize * 0.07).clamp(12.0, 15.0);

    // 控制行总宽 ≈ 4.94 × 主按钮（4 副按钮×0.62 + 主按钮 + 4 间距），保证不溢出
    final mainButtonSize = math.max(
      32.0,
      math.min(coverSize * 0.24, math.min(contentWidth / 4.94, 76.0)),
    );
    final sideButtonSize = mainButtonSize * 0.62;

    // 信息行实测高度（字号/缩放就位后），供「填充 vs 滚动」判定
    final infoTextHeight =
        (2 * titleFontSize * 1.25 +
                4 +
                artistFontSize * 1.4 +
                2 +
                artistFontSize * 0.9 * 1.4) *
            textScale;
    final infoRowHeight = math.max(infoTextHeight, actionColumnHeight);
    final estimatedContentHeight = 24.0 +
        coverSize +
        coverSize * 0.55 + // 封面→信息 / 信息→进度 / 进度→控制 / 控制→音量
        infoRowHeight +
        20.0 +
        mainButtonSize +
        32.0 +
        (hasLyricsEntry ? coverSize * 0.1 + 48.0 * textScale : 0.0);

    return _AlbumMetrics(
      horizontalPadding: horizontalPadding,
      verticalPadding: 12,
      coverSize: coverSize,
      titleFontSize: titleFontSize,
      artistFontSize: artistFontSize,
      albumFontSize: artistFontSize * 0.9,
      actionSize: actionSize,
      mainButtonSize: mainButtonSize,
      sideButtonSize: sideButtonSize,
      mainIconSize: mainButtonSize * 0.5,
      sideIconSize: sideButtonSize * 0.55,
      gapMain: mainButtonSize * 0.35,
      gapSide: mainButtonSize * 0.38,
      gapCoverInfo: coverSize * 0.2,
      gapInfoSeek: coverSize * 0.15,
      gapSeekControls: coverSize * 0.1,
      gapControlsVolume: coverSize * 0.1,
      gapVolumeLyrics: coverSize * 0.1,
      volumeSliderWidth: (contentWidth - 48).clamp(100.0, 160.0),
      estimatedContentHeight: estimatedContentHeight,
    );
  }
}
