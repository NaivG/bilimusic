import 'dart:ui' show lerpDouble;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:bilimusic/features/lyrics/widgets/lyric_section.dart';
import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/features/player/now_playing/album_section.dart';
import 'package:bilimusic/features/player/now_playing/now_playing_action_bar.dart';
import 'package:bilimusic/domain/bili_image.dart';
import 'package:bilimusic/domain/music.dart' as model;
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/widgets/sleep_timer_sheet.dart';
import 'package:bilimusic/features/lan_sync/lan_sync_providers.dart';
import 'package:bilimusic/features/lan_sync/ui/sync_panel.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/ui/stage/bm_stage_backdrop.dart';
import 'package:bilimusic/shared/utils/dialog_helpers.dart';
import 'package:bilimusic/shared/utils/share_helpers.dart';

/// 竖屏详情页 —— Apple Music 风格单面板布局
/// （封面 + 信息 + 操作 + 进度 + 5 按钮 + 音量 + 同步 / 定时 / 歌词）。
class PortraitDetailPage extends ConsumerStatefulWidget {
  final model.Music music;
  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isFavorite;
  final bool showLyrics;
  final List<LyricSource> lyricSources;
  final String? selectedLyricId;
  final LyricController? lyricController;
  final bool isLoadingLyrics;
  final Color? dominantColor;
  final IconData playModeIcon;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShare;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleShowLyrics;
  final VoidCallback onPlaylist;
  final Function(String) onLoadLyric;
  final Function(Duration) onSeek;
  final VoidCallback onTogglePlayMode;

  const PortraitDetailPage({
    super.key,
    required this.music,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isFavorite,
    required this.showLyrics,
    required this.lyricSources,
    required this.selectedLyricId,
    required this.lyricController,
    required this.isLoadingLyrics,
    required this.dominantColor,
    required this.playModeIcon,
    required this.onToggleFavorite,
    required this.onShare,
    required this.onTogglePlay,
    required this.onToggleShowLyrics,
    required this.onPlaylist,
    required this.onLoadLyric,
    required this.onSeek,
    required this.onTogglePlayMode,
  });

  @override
  ConsumerState<PortraitDetailPage> createState() => _PortraitDetailPageState();
}

class _PortraitDetailPageState extends ConsumerState<PortraitDetailPage>
    with SingleTickerProviderStateMixin {
  static const Duration _morphDuration = Duration(milliseconds: 460);

  /// 播放面板与歌词面板始终同时存在于 Stack 中：
  /// 非活动页保留布局，才能在不切页的情况下测量两张封面的位置。
  final GlobalKey _contentStackKey = GlobalKey();
  final GlobalKey _albumCoverKey = GlobalKey();
  final GlobalKey _heroCoverKey = GlobalKey();

  late final AnimationController _morph;
  late final Animation<double> _albumOpacity;
  late final Animation<double> _lyricsOpacity;

  bool _lyricsTarget = false;
  bool _transitioning = false;
  bool _overlayReady = false;

  Rect? _albumCoverRect;
  Rect? _heroCoverRect;

  @override
  void initState() {
    super.initState();
    _lyricsTarget = widget.showLyrics;

    _morph = AnimationController(
      vsync: this,
      duration: _morphDuration,
      value: widget.showLyrics ? 1 : 0,
    )..addStatusListener(_onMorphStatus);

    _albumOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _morph,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );
    _lyricsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _morph,
        curve: const Interval(0.28, 1.0, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void didUpdateWidget(PortraitDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.music.id != widget.music.id && _transitioning) {
      // 切歌可能改变信息行高度，过渡中使用旧封面坐标会跳位，直接落到目标页。
      _transitioning = false;
      _overlayReady = false;
      _albumCoverRect = null;
      _heroCoverRect = null;
      _lyricsTarget = widget.showLyrics;
      _morph.value = widget.showLyrics ? 1 : 0;
    }

    if (widget.showLyrics != _lyricsTarget) {
      _startLyricsTransition(widget.showLyrics);
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fluid = ref.watch(
      settingsProvider.select((settings) => settings.fluidBackground),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBackground(context, fluid)),
          Column(
            children: [
              Expanded(child: _buildContentStack()),
              _buildActionBar(),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AutoAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 24,
          ),
        ),
        onPressed: () => ShellPageManager.instance.pop(),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
          ),
          onPressed: () => _showOptionsSheet(context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBackground(BuildContext context, bool fluid) {
    return BmStageBackdrop(
      coverUrl: widget.music.coverUrl,
      dominantColor: widget.dominantColor,
      fallbackColor: Theme.of(context).colorScheme.primary,
      fluid: fluid,
      cacheManager: imageCacheManager,
    );
  }

  Widget _buildContentStack() {
    return Stack(
      key: _contentStackKey,
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // 播放面板
        TickerMode(
          enabled: !_lyricsTarget,
          child: IgnorePointer(
            ignoring: _lyricsTarget,
            child: ExcludeSemantics(
              excluding: _lyricsTarget,
              child: FadeTransition(
                opacity: _albumOpacity,
                child: _buildAlbumView(context),
              ),
            ),
          ),
        ),
        // 歌词面板
        TickerMode(
          enabled: _lyricsTarget,
          child: IgnorePointer(
            ignoring: !_lyricsTarget,
            child: ExcludeSemantics(
              excluding: !_lyricsTarget,
              child: FadeTransition(
                opacity: _lyricsOpacity,
                child: _buildLyricsView(context),
              ),
            ),
          ),
        ),
        if (_transitioning &&
            _overlayReady &&
            _albumCoverRect != null &&
            _heroCoverRect != null)
          _buildMorphingCover(),
      ],
    );
  }

  Widget _buildAlbumView(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: AlbumSection(
        coverUrl: widget.music.coverUrl,
        title: widget.music.title,
        artist: widget.music.artist.displayName,
        album: widget.music.album,
        dominantColor: widget.dominantColor,
        isFavorite: widget.isFavorite,
        trackId: widget.music.id,
        coverKey: _albumCoverKey,
        coverOpacity: _overlayReady ? 0 : 1,
        onFavoritePressed: widget.onToggleFavorite,
        onSharePressed: widget.onShare,
        isPlaying: widget.isPlaying,
        playModeIcon: widget.playModeIcon,
        onPlayPause: widget.onTogglePlay,
        onPrevious: () =>
            ref.read(playbackCommandsProvider.notifier).playPrevious(),
        onNext: () => ref.read(playbackCommandsProvider.notifier).playNext(),
        onPlayModeToggle: widget.onTogglePlayMode,
        onPlaylist: widget.onPlaylist,
      ),
    );
  }

  Widget _buildLyricsView(BuildContext context) {
    return LyricSection(
      title: widget.music.title,
      artist: widget.music.artist.displayName,
      album: widget.music.album,
      lyricController: widget.lyricController,
      position: widget.position,
      lyricSources: widget.lyricSources,
      selectedLyricId: widget.selectedLyricId,
      isLoadingLyrics: widget.isLoadingLyrics,
      heroCover: Opacity(
        opacity: _overlayReady ? 0 : 1,
        child: KeyedSubtree(
          key: _heroCoverKey,
          child: _CoverArtwork(
            coverUrl: widget.music.coverUrl,
            dominantColor: widget.dominantColor,
            size: _heroCoverSize(context),
            borderRadius: 8,
            shadowStrength: 0.35,
          ),
        ),
      ),
      onLyricSourceChanged: widget.onLoadLyric,
      onLyricTap: widget.onSeek,
    );
  }

  Widget _buildActionBar() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
        child: NowPlayingActionBar(
          lyricsActive: _lyricsTarget,
          onSync: () => showSyncPanel(context),
          onTimer: () => showSleepTimerSheet(context),
          onToggleLyrics: _toggleLyrics,
        ),
      ),
    );
  }

  /// 封面从播放面板的大封面移动到歌词页 hero 的完整过程。
  Widget _buildMorphingCover() {
    final from = _albumCoverRect!;
    final to = _heroCoverRect!;
    final albumRadius = from.width > 300
        ? AppTokens.radiusLg
        : AppTokens.radiusMd;

    return AnimatedBuilder(
      animation: _morph,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_morph.value);
        final rect = Rect.lerp(from, to, t)!;
        final radius = lerpDouble(albumRadius, 8, t) ?? 8;

        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: _CoverArtwork(
              coverUrl: widget.music.coverUrl,
              dominantColor: widget.dominantColor,
              size: rect.width,
              borderRadius: radius,
              shadowStrength: 1 - t * 0.65,
            ),
          ),
        );
      },
    );
  }

  double _heroCoverSize(BuildContext context) {
    return (MediaQuery.sizeOf(context).width * 0.15)
        .clamp(52.0, 64.0)
        .toDouble();
  }

  void _toggleLyrics() {
    final next = !_lyricsTarget;
    _startLyricsTransition(next);
    widget.onToggleShowLyrics();
  }

  /// 切换歌词页。先在下一帧测量两张封面的位置，再让独立封面图层接管动画。
  void _startLyricsTransition(bool showLyrics) {
    if (_lyricsTarget == showLyrics) return;

    setState(() {
      _lyricsTarget = showLyrics;
      _transitioning = true;
    });

    if (_overlayReady && _albumCoverRect != null && _heroCoverRect != null) {
      _runMorph();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_transitioning) return;
      if (!_measureCoverRects()) {
        _morph.value = _lyricsTarget ? 1 : 0;
        _finishTransition();
        return;
      }
      setState(() => _overlayReady = true);
      _runMorph();
    });
  }

  void _runMorph() {
    final target = _lyricsTarget ? 1.0 : 0.0;
    final distance = (target - _morph.value).abs();
    if (distance < 0.001) {
      _finishTransition();
      return;
    }

    final duration = Duration(
      milliseconds: (_morphDuration.inMilliseconds * distance).round().clamp(
        120,
        _morphDuration.inMilliseconds,
      ),
    );
    _morph.animateTo(target, duration: duration, curve: Curves.linear);
  }

  void _onMorphStatus(AnimationStatus status) {
    if (!_transitioning) return;
    final finished = _lyricsTarget
        ? status == AnimationStatus.completed
        : status == AnimationStatus.dismissed;
    if (finished) _finishTransition();
  }

  void _finishTransition() {
    if (!mounted || !_transitioning) return;
    setState(() {
      _transitioning = false;
      _overlayReady = false;
      _albumCoverRect = null;
      _heroCoverRect = null;
    });
  }

  /// 记录两张封面相对内容 Stack 的位置，供 [_buildMorphingCover] 插值。
  bool _measureCoverRects() {
    final stack =
        _contentStackKey.currentContext?.findRenderObject() as RenderBox?;
    final album =
        _albumCoverKey.currentContext?.findRenderObject() as RenderBox?;
    final hero = _heroCoverKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null ||
        album == null ||
        hero == null ||
        !stack.hasSize ||
        !album.hasSize ||
        !hero.hasSize) {
      return false;
    }

    final origin = stack.localToGlobal(Offset.zero);
    Rect rectOf(RenderBox box) {
      final topLeft = box.localToGlobal(Offset.zero) - origin;
      return topLeft & box.size;
    }

    _albumCoverRect = rectOf(album);
    _heroCoverRect = rectOf(hero);
    return true;
  }

  void _showOptionsSheet(BuildContext context) {
    showOptionsSheet(
      context,
      actions: [
        SheetAction(
          icon: widget.isFavorite ? Icons.favorite : Icons.favorite_border,
          iconColor: widget.isFavorite ? Colors.red : null,
          label: widget.isFavorite ? '取消收藏' : '收藏',
          onTap: widget.onToggleFavorite,
        ),
        SheetAction(icon: Icons.share, label: '分享', onTap: widget.onShare),
        if (widget.music.id.isNotEmpty)
          SheetAction(
            icon: Icons.open_in_new,
            label: '打开原网页',
            onTap: () => openOriginalPage(widget.music),
          ),
        // 临时接线：同步面板入口（后续挪到常驻入口时删掉这里与另两个布局的同名项）
        syncPanelSheetAction(
          context,
          onlinePeers: ref.read(connectedPeersProvider).length,
        ),
        SheetAction(
          icon: Icons.timer_outlined,
          // 实时文案：倒计时进行中随剩余时间刷新。
          labelListenable: ref.read(sleepTimerServiceProvider).menuLabel,
          onTap: () => showSleepTimerSheet(context),
        ),
        SheetAction(
          icon: widget.showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
          label: widget.showLyrics ? '隐藏歌词' : '显示歌词',
          onTap: widget.onToggleShowLyrics,
        ),
        SheetAction(
          icon: Icons.info_outline,
          label: '歌曲信息',
          onTap: () => _showSongInfo(context),
        ),
      ],
    );
  }

  void _showSongInfo(BuildContext context) {
    showSongInfoDialog(
      context,
      title: widget.music.title,
      artist: widget.music.artist.displayName,
      album: widget.music.album,
      duration: widget.duration ?? Duration.zero,
    );
  }
}

/// 详情页使用的封面。尺寸 / 圆角 / 阴影强度都是参数，供 hero 动画插值。
class _CoverArtwork extends StatelessWidget {
  final String coverUrl;
  final Color? dominantColor;
  final double size;
  final double borderRadius;
  final double shadowStrength;

  const _CoverArtwork({
    required this.coverUrl,
    required this.size,
    required this.borderRadius,
    required this.shadowStrength,
    this.dominantColor,
  });

  @override
  Widget build(BuildContext context) {
    final strength = shadowStrength.clamp(0.0, 1.0);
    final shadowColor = dominantColor ?? Colors.pink;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: strength <= 0
            ? null
            : [
                BoxShadow(
                  color: shadowColor.withValues(alpha: 0.45 * strength),
                  blurRadius: 50 * strength,
                  spreadRadius: 8 * strength,
                  offset: Offset(0, 25 * strength),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35 * strength),
                  blurRadius: 40 * strength,
                  spreadRadius: 12 * strength,
                  offset: Offset(0, 30 * strength),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildCoverImage(),
      ),
    );
  }

  Widget _buildCoverImage() {
    if (coverUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: biliSquareUrl(coverUrl, 640),
      memCacheWidth: 640,
      fit: BoxFit.cover,
      placeholder: (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[800],
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note,
        color: Colors.white.withValues(alpha: 0.5),
        size: size * 0.4,
      ),
    );
  }
}
