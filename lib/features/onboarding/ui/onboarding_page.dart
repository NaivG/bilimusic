import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'package:bilimusic/app/shells/widgets/desktop_window_controls.dart';
import 'package:bilimusic/features/onboarding/ui/onboarding_content.dart';
import 'package:bilimusic/features/onboarding/ui/onboarding_visuals.dart';
import 'package:bilimusic/shared/motion/motion.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 通用引导页。
///
/// 一页一件事：欢迎 → 登录 → 找歌 → 播放 → 离线 → 外观 → 横屏 → 歌词 → 收尾。
/// 不是版本更新说明，所以页面上不出现版本号；页面列表由调用方传入，
/// 首启、设置回看共用同一个壳。
///
/// 视觉是 iOS 味的（大标题、hairline、玻璃浮层、胶囊按钮），动效刻意克制：
/// 只做 240ms 的方向性淡入淡出 + 8px 位移（Fluent / MD3 的轻量手感），
/// 不使用回弹、循环漂浮或大幅缩放。所有时长 / 曲线都走 [BmMotion]。
///
/// 键盘：→ / ← 翻页，Esc 跳过；触屏与触控板支持横向快滑。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.pages,
    required this.onDone,
    this.onSkip,
  });

  /// 本次要展示的页面；首启和设置回看都传同一份常量列表。
  final List<OnboardingPageSpec> pages;

  /// 看完（最后一页点「开始聆听」）。
  final VoidCallback onDone;

  /// 跳过；为空时等同 [onDone]。
  final VoidCallback? onSkip;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  static const double _topBarHeight = 44;
  static const double _ctaHeight = 52;
  static const double _ctaHeightCompact = 44;

  /// 翻页位移：只给 8–12px 的方向感，不做整屏平移。
  static const double _pageShift = 12;

  late final AnimationController _pageAnim;

  int _index = 0;
  int? _outgoing;
  int _direction = 1;
  double _dragDx = 0;
  bool _handledDone = false;

  bool get _isLast => _index == widget.pages.length - 1;

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: BmMotion.large,
      value: 1,
    )..addStatusListener(_onPageAnimStatus);
  }

  @override
  void dispose() {
    _pageAnim.removeStatusListener(_onPageAnimStatus);
    _pageAnim.dispose();
    super.dispose();
  }

  void _onPageAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null) {
      setState(() => _outgoing = null);
    }
  }

  void _goTo(int target) {
    if (target < 0 || target >= widget.pages.length) return;
    if (target == _index || _pageAnim.isAnimating) return;
    setState(() {
      _outgoing = _index;
      _direction = target > _index ? 1 : -1;
      _index = target;
      _pageAnim.value = 0;
    });
    if (reduceMotionOf(context)) {
      setState(() => _outgoing = null);
    } else {
      _pageAnim.forward();
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _goTo(_index + 1);
    }
  }

  void _previous() => _goTo(_index - 1);

  void _finish() {
    if (_handledDone) return;
    _handledDone = true;
    widget.onDone();
  }

  void _skip() {
    if (_handledDone) return;
    _handledDone = true;
    (widget.onSkip ?? widget.onDone)();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _dragDx += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final dragX = _dragDx;
    _dragDx = 0;
    if (dragX < -60 || velocity < -280) {
      _next();
    } else if (dragX > 60 || velocity > 280) {
      _previous();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
        const SingleActivator(LogicalKeyboardKey.escape): _skip,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.bg,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                const _OnboardingBackdrop(),
                SafeArea(
                  child: Column(
                    children: <Widget>[
                      _buildTopBar(context),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide =
                                constraints.maxWidth > constraints.maxHeight &&
                                constraints.maxWidth >= 640;
                            final compact =
                                constraints.maxHeight < 420 ||
                                constraints.maxWidth < 380;
                            return _buildPager(
                              context,
                              wide: wide,
                              compact: compact,
                            );
                          },
                        ),
                      ),
                      _buildBottomBar(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    // 桌面窗口被拖到很窄时，窗口控制按钮会吃掉品牌区的宽度；
    // 这时只留图标，把「BiliMusic」让给真正要点的东西。
    final narrowDesktop =
        PlatformHelper.isDesktop && MediaQuery.sizeOf(context).width < 560;
    return SizedBox(
      height: _topBarHeight,
      child: Stack(
        children: <Widget>[
          // 桌面端整条标题区可拖动 / 双击最大化，与壳层标题栏一致。
          if (PlatformHelper.isDesktop)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s4),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BmTokens.r4All,
                  child: Image.asset(
                    'assets/ic_launcher.png',
                    width: 16,
                    height: 16,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                if (!narrowDesktop) ...<Widget>[
                  const SizedBox(width: BmTokens.s2),
                  Text(
                    'BiliMusic',
                    style: type.label.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const Spacer(),
                if (!_isLast) _SkipButton(onTap: _skip),
                if (PlatformHelper.isDesktop) ...<Widget>[
                  const SizedBox(width: BmTokens.s2),
                  const BmWindowControls(showPip: false),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    if (!PlatformHelper.isDesktop) return;
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _buildPager(
    BuildContext context, {
    required bool wide,
    required bool compact,
  }) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _pageAnim,
        builder: (context, _) {
          final reduce = reduceMotionOf(context);
          final t = reduce ? 1.0 : BmMotion.standard.transform(_pageAnim.value);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_outgoing != null)
                _buildPageLayer(
                  _outgoing!,
                  wide: wide,
                  compact: compact,
                  opacity: 1 - t,
                  offset: -_direction * _pageShift * t,
                  ignorePointer: true,
                ),
              _buildPageLayer(
                _index,
                wide: wide,
                compact: compact,
                opacity: t,
                offset: _direction * _pageShift * (1 - t),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPageLayer(
    int index, {
    required bool wide,
    required bool compact,
    required double opacity,
    required double offset,
    bool ignorePointer = false,
  }) {
    return IgnorePointer(
      // 翻页动画结束时 `_outgoing` 被清空，Stack 的子项从两项缩回一项。
      key: ValueKey<int>(index),
      ignoring: ignorePointer,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(offset, 0),
          child: _PageBody(
            key: ValueKey<int>(index),
            spec: widget.pages[index],
            wide: wide,
            compact: compact,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height && size.width >= 640;
    final compact = size.height < 420 || size.width < 380;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        landscape ? BmTokens.contentInset : BmTokens.s6,
        BmTokens.s2,
        landscape ? BmTokens.contentInset : BmTokens.s6,
        BmTokens.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _PageDots(
            count: widget.pages.length,
            index: _index,
            onSelected: _goTo,
          ),
          const SizedBox(height: BmTokens.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SizedBox(
              width: double.infinity,
              height: compact ? _ctaHeightCompact : _ctaHeight,
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  textStyle: type.bodyStrong,
                  padding: const EdgeInsets.symmetric(horizontal: BmTokens.s6),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BmTokens.rPillAll,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(_isLast ? '开始聆听' : '继续'),
              ),
            ),
          ),
          if (PlatformHelper.isDesktop && !compact) ...<Widget>[
            const SizedBox(height: BmTokens.s2),
            Text(
              _isLast ? '← 返回 · Esc 完成' : '← → 切换 · Esc 跳过',
              style: type.micro.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// 页面底：两团极淡的色雾，随主题换色，不参与动画。
class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        gradient: RadialGradient(
          center: const Alignment(-0.9, -1.1),
          radius: 1.4,
          colors: <Color>[
            colors.accent.withValues(alpha: 0.12),
            colors.bg.withValues(alpha: 0),
          ],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1.1, 0.95),
            radius: 1.2,
            colors: <Color>[
              colors.highlight.withValues(alpha: 0.1),
              colors.bg.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// 跳过：右上角的小号文字按钮（不抢主按钮的注意力）。
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Tooltip(
      message: '跳过引导（Esc）',
      child: BmPressable(
        onTap: onTap,
        borderRadius: BmTokens.rPillAll,
        semanticLabel: '跳过引导',
        child: SizedBox(
          height: BmTokens.touchDesktop,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
            child: Center(
              child: Text(
                '跳过',
                style: type.label.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 页码点：当前页拉长成胶囊，点击可跳页。
///
/// 不画悬停 / 选中底色：这里的最小视觉单位是 6px 的圆点，
/// BmPressable 的状态层按 24×40 的点击区铺色，会变成一排竖药丸。
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.onSelected,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final duration = motionDuration(context, BmMotion.medium);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var dot = 0; dot < count; dot++)
          BmPressable(
            onTap: () => onSelected(dot),
            selected: dot == index,
            borderRadius: BmTokens.rPillAll,
            // 状态层交给圆点自己：当前页拉长成胶囊就够了。
            // 默认的 24×40 悬停 / 选中底色会在这里变成一块竖着的大药丸。
            overlayColor: Colors.transparent,
            semanticLabel: '第 ${dot + 1} 页，共 $count 页',
            child: SizedBox(
              width: BmTokens.s6,
              height: BmTokens.touchDesktop,
              child: Center(
                child: AnimatedContainer(
                  duration: duration,
                  curve: BmMotion.standard,
                  width: dot == index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dot == index ? colors.accent : colors.lineStrong,
                    borderRadius: BmTokens.rPillAll,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 一页的排版容器：宽屏左右分栏，窄屏上下叠放。
class _PageBody extends StatefulWidget {
  const _PageBody({
    super.key,
    required this.spec,
    required this.wide,
    required this.compact,
  });

  final OnboardingPageSpec spec;
  final bool wide;
  final bool compact;

  @override
  State<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<_PageBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: BmMotion.xlarge,
    value: 1,
  );

  /// 插画 / 文案 / 配件各自一段区间，形成 30ms 级的错峰。
  /// 用 drive 而不是 CurvedAnimation：不需要 dispose 中间对象。
  late final Animation<double> _visualReveal = _reveal.drive(
    CurveTween(curve: const Interval(0, 0.62, curve: BmMotion.standard)),
  );
  late final Animation<double> _copyReveal = _reveal.drive(
    CurveTween(curve: const Interval(0.16, 0.92, curve: BmMotion.standard)),
  );
  late final Animation<double> _accessoryReveal = _reveal.drive(
    CurveTween(curve: const Interval(0.42, 1, curve: BmMotion.standard)),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotionOf(context)) {
      _reveal.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = _Reveal(
      animation: _visualReveal,
      // 插画里的菜单 / 对话框 / 歌词都是示意，不参与语义树；
      // 真正可交互的只有主题色板（在文案区）。
      child: ExcludeSemantics(
        child: _VisualStage(
          size: widget.spec.visualSize,
          child: widget.spec.visual,
        ),
      ),
    );
    final copy = _Reveal(animation: _copyReveal, child: _buildCopy(context));

    if (widget.wide) {
      // 内容居中并设上限：宽屏上左右留白对等，文案与插画不会被拉得太开。
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BmTokens.s8,
              BmTokens.s4,
              BmTokens.s8,
              BmTokens.s4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(child: copy),
                  ),
                ),
                const SizedBox(width: BmTokens.s8),
                Expanded(flex: 5, child: Center(child: visual)),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? BmTokens.s4 : BmTokens.s6,
            BmTokens.s2,
            widget.compact ? BmTokens.s4 : BmTokens.s6,
            0,
          ),
          child: Column(
            children: <Widget>[
              Expanded(flex: 5, child: visual),
              SizedBox(height: widget.compact ? BmTokens.s2 : BmTokens.s4),
              Flexible(
                flex: 4,
                child: Center(child: SingleChildScrollView(child: copy)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopy(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final spec = widget.spec;
    final textAlign = widget.wide ? TextAlign.left : TextAlign.center;
    final crossAxisAlignment = widget.wide
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: <Widget>[
        Text(
          spec.kicker,
          textAlign: textAlign,
          style: type.micro.copyWith(
            color: colors.accent,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: BmTokens.s2),
        Text(spec.title, textAlign: textAlign, style: _titleStyle(context)),
        const SizedBox(height: BmTokens.s3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            spec.subtitle,
            textAlign: textAlign,
            style: _subtitleStyle(context),
          ),
        ),
        if (spec.accessory == OnboardingAccessory.themePicker) ...<Widget>[
          SizedBox(height: widget.wide ? BmTokens.s5 : BmTokens.s3),
          _Reveal(
            animation: _accessoryReveal,
            child: const OnboardingThemePicker(),
          ),
        ],
      ],
    );
  }

  /// 副标题比 body 档略大一档（16 / 1.5）。
  ///
  /// 整屏演示面上 15/21 读起来偏小，但也不为此新增常用字号 token：
  /// 这是引导页这一层自己的排版参数。
  TextStyle _subtitleStyle(BuildContext context) =>
      context.bmType.body.copyWith(
        fontSize: 16,
        height: 1.5,
        color: context.bmColors.textSecondary,
      );

  /// 引导页是整屏演示面，标题需要在 36 的 display 档之上按视口放大。
  /// 其余字号仍走 [BmTypography] 的 8 档 token。
  TextStyle _titleStyle(BuildContext context) {
    final base = context.bmType.display.copyWith(
      color: context.bmColors.textPrimary,
    );
    final double size;
    if (widget.spec.hero) {
      if (widget.wide) {
        // 手机横屏 / 矮窗口：分栏还在，但没有 56px 标题的纵向空间。
        size = widget.compact ? 40 : 56;
      } else {
        size = widget.compact ? 34 : 42;
      }
    } else {
      if (widget.wide) {
        size = widget.compact ? 30 : 44;
      } else {
        size = widget.compact ? 26 : 32;
      }
    }
    return base.copyWith(
      fontSize: size,
      height: 1.12,
      letterSpacing: -size * 0.035,
    );
  }
}

/// 按设计尺寸渲染插画，再整体等比缩放到可用空间。
///
/// 每个插画内部都有固定的版式（mock 卡片、歌词行、面板位置），直接摊到
/// 大小不一的窗口里时，超矮 / 超窄的情况会把假设撑破。这里让插画始终按
/// [size] 布局，再用 FittedBox 整体缩小；插画内部因此不需要再关心窗口。
class _VisualStage extends StatelessWidget {
  const _VisualStage({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          1.0,
          math.min(
            constraints.maxWidth / size.width,
            constraints.maxHeight / size.height,
          ),
        );
        return Center(
          child: SizedBox(
            width: size.width * scale,
            height: size.height * scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// 轻量入场：透明度 + 8px 上移，reduce motion 时直接到终态。
///
/// 必须监听 [animation] 重建，不能只在父 build 里读一次 controller value。
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, BmTokens.s2 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
