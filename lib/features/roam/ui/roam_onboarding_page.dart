import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_image.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/roam/models/roam_style.dart';
import 'package:bilimusic/features/roam/roam_onboarding_provider.dart';
import 'package:bilimusic/features/roam/ui/import_config_dialog.dart';
import 'package:bilimusic/features/roam/ui/roam_cover_waterfall.dart';
import 'package:bilimusic/features/roam/ui/roam_playlist_picker.dart';
import 'package:bilimusic/features/roam/ui/seed_card.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/utils/animations.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

const _motionFast = Duration(milliseconds: 180);
const _motionSlow = Duration(milliseconds: 620);

/// 漫游引导主页（多步状态机）。
/// 很炫的页面，man
///
/// 步骤：
/// - [OnboardingStep.pickPlaylist]  → _PlaylistStep
/// - [OnboardingStep.prefetchLoading] → _PrefetchStep
/// - [OnboardingStep.pickSeeds]     → _SeedStep (PageView)
/// - [OnboardingStep.pickStyle]     → _StyleStep
/// - [OnboardingStep.finalLoading]  → _FinalLoadingStep
/// - [OnboardingStep.error]         → _ErrorStep
/// - [OnboardingStep.done]          → 立即触发 apply()
class RoamOnboardingPage extends ConsumerWidget {
  const RoamOnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);

    // 监听 step=done 触发 apply
    ref.listen<OnboardingState>(roamOnboardingProvider, (prev, next) {
      if (next.step == OnboardingStep.done) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(roamOnboardingProvider.notifier).apply();
        });
      }
    });

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(
        context: context,
        title: '漫游模式',
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => ShellPageManager.instance.pop(),
        ),
      ),
      backgroundColor: Colors.transparent,
      body: PopScope(
        canPop: state.step != OnboardingStep.finalLoading,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final outgoing =
                            animation.status == AnimationStatus.reverse;
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        );
                        return FadeTransition(
                          opacity: curved,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: outgoing
                                  ? const Offset(0, -0.025)
                                  : const Offset(0, 0.035),
                              end: Offset.zero,
                            ).animate(curved),
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: outgoing ? 1.0 : 0.985,
                                end: 1.0,
                              ).animate(curved),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(state.step),
                        child: _buildStep(state),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingState state) {
    switch (state.step) {
      case OnboardingStep.pickPlaylist:
        return _PlaylistStep();
      case OnboardingStep.prefetchLoading:
        return _PrefetchStep(statusMessage: state.statusMessage);
      case OnboardingStep.pickSeeds:
        return _SeedStep();
      case OnboardingStep.pickStyle:
        return _StyleStep();
      case OnboardingStep.finalLoading:
        return _FinalLoadingStep(statusMessage: state.statusMessage);
      case OnboardingStep.error:
        return _ErrorStep(error: state.error ?? '未知错误');
      case OnboardingStep.done:
        return _PlayingStep();
    }
  }
}

// ────────────────────────────────────────────────────────────
// 背景与通用动效
// ────────────────────────────────────────────────────────────

/// 单块内容的延迟入场：淡入 + 上移 + 轻微缩放。
class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.075),
    this.scale = 0.98,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final double scale;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _motionSlow);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = curved;
    _slide = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curved);
    _scale = Tween<double>(begin: widget.scale, end: 1.0).animate(curved);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
      _started = true;
      return;
    }
    if (_started) return;
    _started = true;
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [A] 选歌单
// ────────────────────────────────────────────────────────────

class _PlaylistStep extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PlaylistStep> createState() => _PlaylistStepState();
}

class _PlaylistStepState extends ConsumerState<_PlaylistStep> {
  Future<void> _onImportTap() async {
    final config = await showImportConfigDialog(context);
    if (config == null) return;
    if (!mounted) return;

    // 复用正常流程：finalLoading → done → apply → _PlayingStep，
    // 由 step=done 监听自动触发 apply；不在此处手动 pop。
    await ref.read(roamOnboardingProvider.notifier).importConfig(config);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final state = ref.watch(roamOnboardingProvider);
    final favorites = ref.watch(favoritesProvider);
    final queue = ref.watch(currentPlaylistProvider);
    final playlists = ref.watch(userPlaylistsProvider);

    final covers = <RoamCoverData>[];
    final seen = <String>{};
    void addCovers(Iterable<RoamCoverData> items) {
      for (final cover in items) {
        if (seen.add(cover.cacheKey)) covers.add(cover);
      }
    }

    addCovers(_coversFromMusic(favorites));
    addCovers(_coversFromMusic(queue));
    addCovers(
      _coversFromPlaylistUrls(playlists.map((playlist) => playlist.coverUrl)),
    );
    final coverPool = covers.take(20).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= 820 &&
            constraints.maxWidth > constraints.maxHeight * 1.1;

        final panel = _PlaylistPanel(
          state: state,
          onImportTap: _onImportTap,
          onPlaylistSelected: (id, name, count) {
            notifier.selectPlaylist(id, name);
          },
        );

        if (isWide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: _Reveal(
                    delay: Duration.zero,
                    child: _RoamHero(covers: coverPool, compact: false),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  flex: 9,
                  child: _Reveal(delay: _motionFast, child: panel),
                ),
              ],
            ),
          );
        }

        final showHero = constraints.maxHeight >= 430;
        final heroHeight = (constraints.maxHeight * 0.3).clamp(148.0, 260.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              if (showHero) ...[
                _Reveal(
                  delay: Duration.zero,
                  child: SizedBox(
                    height: heroHeight,
                    child: _RoamHero(covers: coverPool, compact: true),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: _Reveal(delay: _motionFast, child: panel),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<RoamCoverData> _coversFromMusic(Iterable<Music> music) {
  final covers = <RoamCoverData>[];
  final seen = <String>{};
  for (final item in music) {
    if (!Music.isValidImageUrl(item.coverUrl)) continue;
    if (!seen.add(item.key)) continue;
    covers.add(
      RoamCoverData(
        imageUrl: item.safeCoverUrl,
        cacheKey: 'music_${item.key}',
        seed: covers.length,
      ),
    );
    if (covers.length >= 40) break;
  }
  return covers;
}

List<RoamCoverData> _coversFromPlaylistUrls(Iterable<String?> urls) {
  final covers = <RoamCoverData>[];
  for (final url in urls) {
    if (!Music.isValidImageUrl(url)) continue;
    covers.add(
      RoamCoverData(
        imageUrl: url!,
        cacheKey: 'playlist_$url',
        seed: covers.length,
      ),
    );
    if (covers.length >= 40) break;
  }
  return covers;
}

class _RoamHero extends StatelessWidget {
  const _RoamHero({required this.covers, required this.compact});

  final List<RoamCoverData> covers;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(compact ? 24 : 30);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.14),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surfaceContainerHighest,
                    scheme.surfaceContainerLow,
                  ],
                ),
              ),
            ),
            RoamCoverWaterfall(
              covers: covers,
              minColumnWidth: compact ? 92 : 112,
              maxColumns: 7,
              gap: 6,
              tileRadius: 10,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x18000000),
                    Color(0x0A000000),
                    Color(0xD9000000),
                  ],
                  stops: [0.0, 0.38, 1.0],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.1, -1.0),
                  radius: 1.3,
                  colors: [
                    scheme.primary.withValues(alpha: 0.32),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Positioned(
              left: compact ? 16 : 22,
              top: compact ? 14 : 20,
              child: const _HeroBadge(label: 'ROAM MODE'),
            ),
            Positioned(
              left: compact ? 18 : 26,
              right: compact ? 18 : 26,
              bottom: compact ? 16 : 24,
              child: _Reveal(
                delay: const Duration(milliseconds: 220),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '独属于你的\n漫游电台',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 27 : 42,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: compact ? -0.4 : -1.2,
                        shadows: const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 18,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 12),
                    Text(
                      '选一个歌单，挑几颗种子，推荐符合你口味的歌。',
                      maxLines: compact ? 2 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: compact ? 12 : 14,
                        height: 1.4,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          _HeroChip(
                            icon: Icons.graphic_eq_rounded,
                            label: '相似度漫游',
                          ),
                          _HeroChip(
                            icon: Icons.all_inclusive_rounded,
                            label: '无限续杯',
                          ),
                          _HeroChip(icon: Icons.source_rounded, label: '本地计算'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistPanel extends StatelessWidget {
  const _PlaylistPanel({
    required this.state,
    required this.onImportTap,
    required this.onPlaylistSelected,
  });

  final OnboardingState state;
  final VoidCallback onImportTap;
  final void Function(String id, String name, int count) onPlaylistSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '选择一个歌单',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '从熟悉的收藏出发',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _ImportButton(onTap: onImportTap),
              ],
            ),
          ),
          if (state.error != null) _ErrorBanner(message: state.error!),
          Expanded(
            child: RoamPlaylistPicker(
              showTitle: false,
              showBanner: false,
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              onPlaylistSelected: onPlaylistSelected,
            ),
          ),
          _QueueWarning(),
        ],
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '导入已保存的漫游配置',
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.content_paste_go_rounded, size: 16),
        label: const Text('导入'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _QueueWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: scheme.error.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '进入漫游会清空当前播放队列',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [A.5] 预取
// ────────────────────────────────────────────────────────────

class _PrefetchStep extends ConsumerWidget {
  const _PrefetchStep({this.statusMessage});

  final String? statusMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _RoamLoadingView(
      title: '正在收集歌曲种子',
      statusMessage: statusMessage ?? '正在准备漫游...',
      icon: Icons.travel_explore_rounded,
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [B] 选种子（PageView）
// ────────────────────────────────────────────────────────────

class _SeedStep extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SeedStep> createState() => _SeedStepState();
}

class _SeedStepState extends ConsumerState<_SeedStep> {
  late final PageController _pageController;

  /// 滚轮累计位移（避免一次微动就误触切页）。
  double _accumulatedScroll = 0;

  /// 累计阈值：约 2.5 次鼠标滚轮刻度（≈250 logical px）的 80%。
  static const double _scrollThreshold = 200.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 桌面端滚轮 = 切轮次（PageView 本身不响应 wheel）。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_pageController.hasClients) return;
    final state = ref.read(roamOnboardingProvider);
    if (state.roundsCount <= 1) return;
    final delta = event.scrollDelta.dy;
    if (delta == 0) return;

    _accumulatedScroll += delta;
    if (_accumulatedScroll.abs() < _scrollThreshold) return;

    final forward = _accumulatedScroll > 0;
    _accumulatedScroll = 0;

    if (forward) {
      if (state.currentSectionIndex >= state.roundsCount - 1) return;
      _pageController.nextPage(
        duration: BmMotion.medium,
        curve: BmMotion.standard,
      );
    } else {
      if (state.currentSectionIndex <= 0) return;
      _pageController.previousPage(
        duration: BmMotion.medium,
        curve: BmMotion.standard,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 同步外部 currentSectionIndex 变化（如 dot indicator / 箭头按钮点击）
    ref.listen<OnboardingState>(roamOnboardingProvider, (prev, next) {
      if (prev?.currentSectionIndex != next.currentSectionIndex) {
        // 外部触发的切页要把累计量清零，否则下一次滚轮可能直接再翻一次。
        _accumulatedScroll = 0;
        if (_pageController.hasClients &&
            _pageController.position.hasContentDimensions) {
          final currentPage = _pageController.page ?? next.currentSectionIndex;
          if ((currentPage - next.currentSectionIndex).abs() > 0.01) {
            _pageController.animateToPage(
              next.currentSectionIndex,
              duration: BmMotion.medium,
              curve: BmMotion.standard,
            );
          }
        }
      }
    });

    final state = ref.watch(roamOnboardingProvider);
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final showArrows = state.roundsCount > 1;
    final compact = MediaQuery.sizeOf(context).height < 720;
    final theme = Theme.of(context);

    return Column(
      children: [
        _Reveal(
          delay: Duration.zero,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              compact ? 4 : 8,
              20,
              compact ? 10 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _RoundBadge(
                      current: state.currentSectionIndex + 1,
                      total: state.roundsCount,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '选一颗你想漫游的种子',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '共 ${state.roundsCount} 轮，每轮挑一颗作为这轮的方向',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (showArrows) ...[const SizedBox(height: 8), _SwipeHint()],
              ],
            ),
          ),
        ),
        Expanded(
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => notifier.setSectionIndex(i),
                  itemCount: state.roundsCount,
                  itemBuilder: (_, round) {
                    return AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        double page = round.toDouble();
                        if (_pageController.hasClients &&
                            _pageController.position.hasContentDimensions) {
                          page = _pageController.page ?? page;
                        }
                        final distance = (page - round).abs().clamp(0.0, 1.0);
                        return Opacity(
                          opacity: 1 - distance * 0.35,
                          child: Transform.scale(
                            scale: 1 - distance * 0.045,
                            child: child,
                          ),
                        );
                      },
                      child: _RoundPage(round: round),
                    );
                  },
                ),
                if (showArrows) ...[
                  _PageArrowButton(
                    direction: _ArrowDirection.prev,
                    enabled: state.currentSectionIndex > 0,
                    onPressed: () => _pageController.previousPage(
                      duration: BmMotion.medium,
                      curve: BmMotion.standard,
                    ),
                  ),
                  _PageArrowButton(
                    direction: _ArrowDirection.next,
                    enabled: state.currentSectionIndex < state.roundsCount - 1,
                    onPressed: () => _pageController.nextPage(
                      duration: BmMotion.medium,
                      curve: BmMotion.standard,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _SeedBottomBar(),
      ],
    );
  }
}

class _RoundBadge extends StatelessWidget {
  const _RoundBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: switcherFadeTransition,
            child: Text(
              '第 $current / $total 轮',
              key: ValueKey(current),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ArrowDirection { prev, next }

/// PageView 左右浮动的圆形箭头按钮。
class _PageArrowButton extends StatelessWidget {
  const _PageArrowButton({
    required this.direction,
    required this.enabled,
    required this.onPressed,
  });

  final _ArrowDirection direction;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPrev = direction == _ArrowDirection.prev;
    return Positioned(
      left: isPrev ? 8 : null,
      right: isPrev ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: Material(
          color: scheme.surface.withValues(alpha: 0.82),
          shape: CircleBorder(
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                isPrev
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                size: 24,
                color: enabled
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundPage extends ConsumerWidget {
  const _RoundPage({required this.round});

  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);
    final options = state.roundOptions[round];
    final selectedIndex = state.selectedSeedIndex[round] ?? 0;
    final notifier = ref.read(roamOnboardingProvider.notifier);

    if (options.isEmpty) {
      return Center(
        child: Text('这轮没有候选歌曲', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return _SeedMosaic(
      options: options,
      selectedIndex: selectedIndex,
      onSelect: (index) => notifier.selectSeed(round, index),
    );
  }
}

class _SeedMosaic extends StatelessWidget {
  const _SeedMosaic({
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<Music> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) return const SizedBox.shrink();

        final gap = 12.0;
        final availableWidth = math.max(0.0, width - 32);
        final availableHeight = math.max(0.0, height - 16);
        if (availableHeight < 100) return const SizedBox.shrink();

        if (options.length == 1) {
          final cardWidth = math.min(availableWidth, 520.0);
          final cardHeight = math.min(availableHeight, 460.0);
          return Center(
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _card(0, compact: false),
            ),
          );
        }

        final threeColumns = availableWidth >= 900 && options.length >= 3;

        if (threeColumns) {
          const heights = [0.94, 0.8, 0.88];
          const tops = [0.0, 0.1, 0.04];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < 3; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: availableHeight * tops[i]),
                      child: SizedBox(
                        height: availableHeight * heights[i],
                        child: _card(i, compact: false),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        if (options.length == 2) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SizedBox(
                    height: availableHeight * 0.96,
                    child: _card(0, compact: availableWidth < 520),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: availableHeight * 0.06),
                    child: SizedBox(
                      height: availableHeight * 0.82,
                      child: _card(1, compact: availableWidth < 520),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final leftHeight = availableHeight * 0.96;
        final rightTop = availableHeight * 0.05;
        final rightCardHeight = (availableHeight - rightTop - gap) / 2;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: leftHeight,
                  child: _card(0, compact: availableWidth < 520),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: rightTop),
                  child: Column(
                    children: [
                      SizedBox(
                        height: rightCardHeight,
                        child: _card(1, compact: availableWidth < 520),
                      ),
                      SizedBox(height: gap),
                      SizedBox(
                        height: rightCardHeight,
                        child: _card(2, compact: availableWidth < 520),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(int index, {required bool compact}) {
    if (index >= options.length) return const SizedBox.shrink();
    return _Reveal(
      delay: Duration(milliseconds: 70 * index),
      offset: const Offset(0, 0.06),
      scale: 0.97,
      child: SeedCard(
        music: options[index],
        selected: index == selectedIndex,
        index: index,
        compact: compact,
        onTap: () => onSelect(index),
      ),
    );
  }
}

class _SeedBottomBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picked = state.userPicks.whereType<Music>().length;

    return _Reveal(
      delay: const Duration(milliseconds: 120),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < state.roundsCount; i++) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => notifier.setSectionIndex(i),
                    child: AnimatedContainer(
                      duration: BmMotion.medium,
                      curve: BmMotion.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == state.currentSectionIndex ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == state.currentSectionIndex
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: i == state.currentSectionIndex
                            ? [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Text(
                  '已选 $picked / ${state.roundsCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GradientActionButton(
              label: '继续',
              icon: Icons.arrow_forward_rounded,
              enabled: state.allSeedsPicked,
              onTap: notifier.goToStyle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 切换轮次的小提示徽章：桌面端用滚轮，移动端用滑动。
class _SwipeHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final platform = theme.platform;
    final isDesktop =
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    final message = isDesktop ? '滚轮切换轮次 · 点击卡片选择' : '左右滑动切换轮次 · 点击卡片选择';
    final iconData = isDesktop ? Icons.mouse_rounded : Icons.swipe_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            message,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [C] 选风格
// ────────────────────────────────────────────────────────────

class _StyleStep extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roamOnboardingProvider);
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picks = state.userPicks.whereType<Music>().toList();
    final covers = _coversFromMusic(picks);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final cards = <Widget>[
          _styleCard(
            context,
            style: RoamStyle.similar,
            selected: state.style == RoamStyle.similar,
            vertical: wide,
            onTap: () => notifier.setStyle(RoamStyle.similar),
          ),
          _styleCard(
            context,
            style: RoamStyle.balanced,
            selected: state.style == RoamStyle.balanced,
            vertical: wide,
            onTap: () => notifier.setStyle(RoamStyle.balanced),
          ),
          _styleCard(
            context,
            style: RoamStyle.explore,
            selected: state.style == RoamStyle.explore,
            vertical: wide,
            onTap: () => notifier.setStyle(RoamStyle.explore),
          ),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Reveal(
                delay: Duration.zero,
                child: Row(
                  children: [
                    _SeedAvatarStack(
                      covers: covers,
                      size: 48,
                      borderColor: scheme.surface,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '选一种漫游方式',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${picks.length} 颗种子已就位 · 决定下一步往哪走',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < cards.length; i++) ...[
                            if (i > 0) const SizedBox(width: 12),
                            Expanded(
                              child: _Reveal(
                                delay: Duration(milliseconds: 70 * i),
                                child: cards[i],
                              ),
                            ),
                          ],
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, cardConstraints) {
                          const gap = 10.0;
                          final cardHeight = math.min(
                            176.0,
                            math.max(
                              104.0,
                              (cardConstraints.maxHeight - gap * 2) / 3,
                            ),
                          );
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                for (int i = 0; i < cards.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      bottom: i == cards.length - 1 ? 0 : gap,
                                    ),
                                    child: SizedBox(
                                      height: cardHeight,
                                      child: _Reveal(
                                        delay: Duration(milliseconds: 60 * i),
                                        child: cards[i],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),
              _Reveal(
                delay: const Duration(milliseconds: 240),
                child: _GradientActionButton(
                  label: '开始漫游',
                  icon: Icons.rocket_launch_rounded,
                  onTap: notifier.goToFinalFetch,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _styleCard(
    BuildContext context, {
    required RoamStyle style,
    required bool selected,
    required bool vertical,
    required VoidCallback onTap,
  }) {
    return _StyleOptionCard(
      style: style,
      selected: selected,
      vertical: vertical,
      onTap: onTap,
    );
  }
}

class _StyleOptionCard extends StatefulWidget {
  const _StyleOptionCard({
    required this.style,
    required this.selected,
    required this.vertical,
    required this.onTap,
  });

  final RoamStyle style;
  final bool selected;
  final bool vertical;
  final VoidCallback onTap;

  @override
  State<_StyleOptionCard> createState() => _StyleOptionCardState();
}

class _StyleOptionCardState extends State<_StyleOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final radius = BorderRadius.circular(20);

    return Semantics(
      button: true,
      selected: selected,
      label: _label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.012 : 1.0,
          duration: _motionFast,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary.withValues(alpha: 0.3),
                        scheme.tertiary.withValues(alpha: 0.16),
                      ],
                    )
                  : null,
              color: selected ? null : scheme.surface.withValues(alpha: 0.56),
              border: Border.all(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.8)
                    : scheme.outlineVariant.withValues(alpha: 0.6),
                width: selected ? 1.6 : 1.0,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.2),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: radius,
                child: Padding(
                  padding: EdgeInsets.all(widget.vertical ? 18 : 14),
                  child: widget.vertical
                      ? _buildVertical(theme, scheme)
                      : _buildHorizontal(theme, scheme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVertical(ThemeData theme, ColorScheme scheme) {
    final selected = widget.selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _StyleIcon(icon: _icon, selected: selected, size: 54),
            _SelectionDot(selected: selected),
          ],
        ),
        const Spacer(),
        Text(
          _tag,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _label,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _description,
          maxLines: 3,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontal(ThemeData theme, ColorScheme scheme) {
    final selected = widget.selected;
    return Row(
      children: [
        _StyleIcon(icon: _icon, selected: selected, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _SelectionDot(selected: selected),
      ],
    );
  }

  String get _label => switch (widget.style) {
    RoamStyle.similar => '相似',
    RoamStyle.balanced => '平衡',
    RoamStyle.explore => '探索',
  };

  String get _tag => switch (widget.style) {
    RoamStyle.similar => 'SAME WAVE',
    RoamStyle.balanced => 'MIXED',
    RoamStyle.explore => 'WILD',
  };

  String get _description => switch (widget.style) {
    RoamStyle.similar => '顺着现在的方向走，每一首都像上一首的延续',
    RoamStyle.balanced => '在熟悉和陌生之间随机摇摆',
    RoamStyle.explore => '往反方向走，每一首都是新风格',
  };

  IconData get _icon => switch (widget.style) {
    RoamStyle.similar => Icons.compare_arrows_rounded,
    RoamStyle.balanced => Icons.balance_rounded,
    RoamStyle.explore => Icons.travel_explore_rounded,
  };
}

class _StyleIcon extends StatelessWidget {
  const _StyleIcon({
    required this.icon,
    required this.selected,
    required this.size,
  });

  final IconData icon;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              )
            : null,
        color: selected ? null : scheme.surfaceContainerHigh,
        boxShadow: selected
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: size * 0.46,
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: 1.5,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.4),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
          : null,
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [D] 最终拉取
// ────────────────────────────────────────────────────────────

class _FinalLoadingStep extends ConsumerWidget {
  const _FinalLoadingStep({this.statusMessage});

  final String? statusMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _RoamLoadingView(
      title: '即将完成',
      statusMessage: statusMessage ?? '正在为你生成歌单...',
      icon: Icons.auto_awesome_rounded,
    );
  }
}

class _RoamLoadingView extends StatelessWidget {
  const _RoamLoadingView({
    required this.title,
    required this.statusMessage,
    required this.icon,
  });

  final String title;
  final String statusMessage;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = constraints.maxHeight < 600 ? 112.0 : 132.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LoadingIcon(icon: icon, size: iconSize),
                    const SizedBox(height: 26),
                    _Reveal(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: switcherFadeTransition,
                        child: Text(
                          statusMessage,
                          key: ValueKey(statusMessage),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const SizedBox(width: 180, child: _ShimmerBar()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LoadingIcon extends StatefulWidget {
  const _LoadingIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  State<_LoadingIcon> createState() => _LoadingIconState();
}

class _LoadingIconState extends State<_LoadingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled == _animationsDisabled) return;
    _animationsDisabled = disabled;
    if (disabled) {
      _controller.stop();
    } else {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = widget.size;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.16),
                  scheme.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            child: Container(
              width: size * 0.58,
              height: size * 0.58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.32),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                widget.icon,
                size: size * 0.28,
                color: scheme.onPrimary,
              ),
            ),
            builder: (context, child) {
              final t = _animationsDisabled ? 0.0 : _controller.value;
              final pulse = 1 + 0.05 * math.sin(t * math.pi * 2);
              return Transform.scale(scale: pulse, child: child);
            },
          ),
        ],
      ),
    );
  }
}

/// 加载中的一条细光带。
class _ShimmerBar extends StatefulWidget {
  const _ShimmerBar();

  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disabled == _animationsDisabled) return;
    _animationsDisabled = disabled;
    if (disabled) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 3,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: scheme.outlineVariant.withValues(alpha: 0.38),
                  ),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _animationsDisabled ? 0.35 : _controller.value;
                    final x = -80 + (width + 160) * t;
                    return Transform.translate(
                      offset: Offset(x, 0),
                      child: Container(
                        width: 80,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              scheme.primary.withValues(alpha: 0.85),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
// 错误步骤
// ────────────────────────────────────────────────────────────

class _ErrorStep extends ConsumerWidget {
  const _ErrorStep({required this.error});

  final String error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(roamOnboardingProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: _Reveal(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 26,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.errorContainer.withValues(alpha: 0.55),
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '漫游中断了',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => ShellPageManager.instance.pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('返回'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: notifier.retryFinalFetch,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重试'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 步骤 [F] 已开始漫游（成功落地页）
// ────────────────────────────────────────────────────────────

class _PlayingStep extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(roamOnboardingProvider);
    final songCount = state.finalPlaylist?.length ?? 0;
    final covers = _coversFromMusic(state.finalPlaylist ?? const []);
    final styleName = switch (state.style) {
      RoamStyle.similar => '相似',
      RoamStyle.balanced => '平衡',
      RoamStyle.explore => '探索',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - 48),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _SuccessBadge(),
                const SizedBox(height: 12),
                Text(
                  '已开始漫游',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TweenAnimationBuilder<int>(
                  tween: IntTween(begin: 0, end: songCount),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, count, _) {
                    return Text(
                      '已为你生成 $count 首歌 · $styleName风格',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
                if (state.playlistName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '基于歌单：${state.playlistName}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (covers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _Reveal(
                    delay: const Duration(milliseconds: 320),
                    child: _CoverStack(covers: covers, total: songCount),
                  ),
                ],
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _GradientActionButton(
                    label: '返回',
                    icon: Icons.arrow_back_rounded,
                    onTap: () => ShellPageManager.instance.pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SuccessBadge extends StatefulWidget {
  const _SuccessBadge();

  @override
  State<_SuccessBadge> createState() => _SuccessBadgeState();
}

class _SuccessBadgeState extends State<_SuccessBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final raw = _controller.value.clamp(0.0, 1.0);
          final progress = Curves.easeOutCubic.transform(raw);
          final checkScale = Curves.elasticOut.transform(raw);

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < 2; i++)
                Opacity(
                  opacity: ((1 - progress) * (i == 0 ? 0.36 : 0.2)).clamp(
                    0.0,
                    1.0,
                  ),
                  child: Container(
                    width: 96 + (72 + i * 26) * progress,
                    height: 96 + (72 + i * 26) * progress,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.34),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Transform.scale(
                  scale: checkScale,
                  child: Icon(
                    Icons.check_rounded,
                    size: 54,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.covers, required this.total});

  final List<RoamCoverData> covers;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = covers.take(6).toList();
    final overlap = 16.0;
    final size = 48.0;
    final extra = total > items.length ? 1 : 0;
    final width = items.isEmpty
        ? size
        : size + overlap * (items.length + extra - 1);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < items.length; i++)
            Positioned(
              left: i * overlap,
              top: 0,
              child: _CoverAvatar(
                cover: items[i],
                size: size,
                borderColor: scheme.surface,
                borderWidth: 2,
              ),
            ),
          if (total > items.length)
            Positioned(
              left: items.length * overlap,
              top: 0,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHigh,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+${total - items.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 共享小组件
// ────────────────────────────────────────────────────────────

class _SeedAvatarStack extends StatelessWidget {
  const _SeedAvatarStack({
    required this.covers,
    required this.size,
    required this.borderColor,
  });

  final List<RoamCoverData> covers;
  final double size;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final items = covers.take(4).toList();
    if (items.isEmpty) {
      return _CoverAvatar(
        cover: null,
        size: size,
        borderColor: borderColor,
        borderWidth: 2,
      );
    }
    final overlap = size * 0.34;
    return SizedBox(
      width: size + overlap * (items.length - 1),
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < items.length; i++)
            Positioned(
              left: i * overlap,
              top: 0,
              child: _CoverAvatar(
                cover: items[i],
                size: size,
                borderColor: borderColor,
                borderWidth: 2,
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverAvatar extends StatelessWidget {
  const _CoverAvatar({
    required this.cover,
    required this.size,
    required this.borderColor,
    this.borderWidth = 2,
  });

  final RoamCoverData? cover;
  final double size;
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = cover;
    final hasImage = data != null && _isValidImageUrl(data.imageUrl);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: biliSquareUrl(data.imageUrl, 192),
                cacheKey: '${data.cacheKey}_192',
                memCacheWidth: 192,
                cacheManager: imageCacheManager,
                httpHeaders: NetworkConfig.biliHeaders,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 240),
                placeholder: (_, _) => _placeholder(scheme),
                errorWidget: (_, _, _) => _placeholder(scheme),
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.7),
            scheme.tertiary.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.46,
        color: scheme.onPrimary.withValues(alpha: 0.72),
      ),
    );
  }

  bool _isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    return Uri.tryParse(url)?.hasAbsolutePath == true;
  }
}

class _GradientActionButton extends StatefulWidget {
  const _GradientActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_GradientActionButton> createState() => _GradientActionButtonState();
}

class _GradientActionButtonState extends State<_GradientActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.enabled;
    final radius = BorderRadius.circular(16);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: enabled ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedScale(
          scale: _hovered ? 1.012 : 1.0,
          duration: _motionFast,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.46,
            duration: const Duration(milliseconds: 200),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.32),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: InkWell(
                  onTap: enabled ? widget.onTap : null,
                  borderRadius: radius,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, size: 19, color: scheme.onPrimary),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
