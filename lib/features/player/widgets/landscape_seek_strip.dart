import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 横屏底栏顶端的全宽进度条。
///
/// 细线贴在底栏上沿：常态 [BmTokens.playbarProgressLine]，悬停 / 拖动时加粗到
/// [BmTokens.playbarProgressLineActive]。整条轨道可点可拖，时长读数走跟随指针的
/// 浮层。
class LandscapeSeekStrip extends ConsumerStatefulWidget {
  const LandscapeSeekStrip({super.key});

  @override
  ConsumerState<LandscapeSeekStrip> createState() => _LandscapeSeekStripState();
}

class _LandscapeSeekStripState extends ConsumerState<LandscapeSeekStrip> {
  /// 读数浮层的锚点。
  final LayerLink _link = LayerLink();
  final OverlayPortalController _readout = OverlayPortalController();

  /// 悬停后延迟弹出读数，指针快速划过时不闪。
  Timer? _showTimer;

  /// 指针在轨道上的横向比例（0–1）。
  double _fraction = 0;

  bool _hovering = false;
  bool _dragging = false;

  /// 悬停或拖动中：线加粗、读数可用。
  bool get _expanded => _hovering || _dragging;

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  /// 当前曲目时长；无曲目时为 [Duration.zero]。
  Duration get _duration =>
      ref.read(currentMusicProvider)?.duration ?? Duration.zero;

  static double _fractionAt(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  void _updateFraction(double dx, double width) {
    final next = _fractionAt(dx, width);
    if (next == _fraction) return;
    setState(() => _fraction = next);
  }

  void _handleEnter(double dx, double width) {
    if (_duration <= Duration.zero) return;
    setState(() {
      _hovering = true;
      _fraction = _fractionAt(dx, width);
    });
    _scheduleReadout();
  }

  void _handleHover(double dx, double width) {
    if (!_hovering) return;
    _updateFraction(dx, width);
  }

  void _handleExit() {
    if (!_hovering) return;
    setState(() => _hovering = false);
    if (!_dragging) _hideReadout();
  }

  void _handleDown(PointerDownEvent event, double width) {
    if (event.buttons != kPrimaryButton) return;
    if (_duration <= Duration.zero) return;
    setState(() {
      _dragging = true;
      _fraction = _fractionAt(event.localPosition.dx, width);
    });
    _showReadout();
  }

  void _handleMove(PointerMoveEvent event, double width) {
    if (!_dragging) return;
    _updateFraction(event.localPosition.dx, width);
  }

  Future<void> _handleUp() async {
    if (!_dragging) return;
    final target = _duration * _fraction;
    try {
      // 拖动期间线停在目标位置，seek 落地后再交回播放位置。
      await ref.read(playbackCommandsProvider.notifier).seek(target);
    } finally {
      if (mounted) {
        setState(() => _dragging = false);
        if (!_hovering) _hideReadout();
      }
    }
  }

  void _handleCancel() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    if (!_hovering) _hideReadout();
  }

  void _showReadout() {
    _showTimer?.cancel();
    _showTimer = null;
    if (!mounted || _readout.isShowing) return;
    _readout.show();
  }

  void _scheduleReadout() {
    if (_readout.isShowing || _showTimer != null) return;
    _showTimer = Timer(BmMotion.small, () {
      _showTimer = null;
      if (!mounted || !_hovering) return;
      _readout.show();
    });
  }

  void _hideReadout() {
    _showTimer?.cancel();
    _showTimer = null;
    if (!mounted || !_readout.isShowing) return;
    _readout.hide();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final position = ref.watch(positionProvider);
    final duration = ref.watch(currentMusicProvider)?.duration ?? Duration.zero;
    final hasTrack = duration > Duration.zero;
    final progress = _dragging
        ? _fraction
        : hasTrack
        ? (position.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0)
        : 0.0;
    final lineHeight = _expanded
        ? BmTokens.playbarProgressLineActive
        : BmTokens.playbarProgressLine;

    return SizedBox(
      height: BmTokens.playbarProgressHit,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return OverlayPortal(
            controller: _readout,
            overlayChildBuilder: (overlayContext) =>
                _buildReadout(overlayContext, duration, width),
            child: CompositedTransformTarget(
              link: _link,
              child: MouseRegion(
                cursor: hasTrack ? SystemMouseCursors.click : MouseCursor.defer,
                onEnter: (event) => _handleEnter(event.localPosition.dx, width),
                onHover: (event) => _handleHover(event.localPosition.dx, width),
                onExit: (_) => _handleExit(),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => _handleDown(event, width),
                  onPointerMove: (event) => _handleMove(event, width),
                  onPointerUp: (_) => _handleUp(),
                  onPointerCancel: (_) => _handleCancel(),
                  child: Stack(
                    children: [
                      // 未播放段：整条轨道的底色。
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: _buildLine(colors.lineStrong, lineHeight),
                      ),
                      // 已播放段：按进度截断。
                      Positioned(
                        left: 0,
                        top: 0,
                        width: width * progress,
                        child: _buildLine(colors.accent, lineHeight),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLine(Color color, double height) {
    return AnimatedContainer(
      duration: BmMotion.hoverIn,
      curve: BmMotion.standard,
      height: height,
      color: color,
    );
  }

  /// 跟随指针的时长读数：左为预览位置，右为整首时长。
  Widget _buildReadout(BuildContext context, Duration duration, double width) {
    final colors = context.bmColors;
    final type = context.bmType;
    // 两端各留半个浮层的余量，贴边时不被裁掉。
    final margin = BmTokens.s8 * 2;
    final center = (width * _fraction).clamp(margin, width - margin).toDouble();
    final preview = duration * _fraction;

    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
      offset: Offset(center - width / 2, -BmTokens.s1),
      showWhenUnlinked: false,
      // Overlay 子节点拿的是整屏紧约束：先包一层 [Align]，让浮层按内容定尺寸，
      // 再靠 follower 的 bottomCenter 把它的下沿贴到轨道上沿。
      child: Align(
        alignment: Alignment.bottomCenter,
        child: IgnorePointer(
          child: BmMenuSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: BmTokens.s2,
              vertical: BmTokens.s1,
            ),
            entrance: BmMenuEntranceKind.scale,
            alignment: Alignment.bottomCenter,
            child: Text(
              '${formatDuration(preview)} / ${formatDuration(duration)}',
              style: BmTypography.numeric(
                type.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
