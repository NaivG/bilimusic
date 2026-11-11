import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/widgets/playback_buttons.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/menu/bm_menu_surface.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 横屏底栏音量控件。
///
/// 桌面悬停展开竖向音量条、点击喇叭切换静音；触屏 / 触控笔没有 hover，
/// 点按喇叭只展开浮层，点浮层外收起。
class LandscapeVolumeControl extends ConsumerStatefulWidget {
  const LandscapeVolumeControl({super.key});

  @override
  ConsumerState<LandscapeVolumeControl> createState() =>
      _LandscapeVolumeControlState();
}

class _LandscapeVolumeControlState
    extends ConsumerState<LandscapeVolumeControl> {
  /// 音量条长度（竖直方向）。
  static const double _barLength = 104;

  /// 滑块盒子的横向尺寸：轨道只画 4px 细线，其余是拖动命中区。
  static const double _barHitWidth = BmTokens.touchDesktop;

  /// 浮层内容宽度。
  static const double _panelWidth = 32;

  /// 滚轮单格调整量。
  static const double _wheelStep = 0.02;

  /// 没有 hover 的指针类型（一般是触屏）：点按只展开浮层，不切静音。
  static const Set<PointerDeviceKind> _tapPointerKinds = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  /// 浮层锚点。
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// 悬停后延迟展开，快速划过不闪浮层。
  Timer? _showTimer;

  /// 指针离开后延迟收起，留出跨过图标与浮层间隙的时间。
  Timer? _hideTimer;

  /// 正在拖动音量条：此时不因指针移出浮层而收起。
  bool _dragging = false;

  /// 浮层由点按展开：额外挂一层全屏遮罩，点浮层外即收起。
  bool _tapOpen = false;

  /// 最近一次按下图标的指针类型，用来把触屏点按与鼠标点击分流。
  PointerDeviceKind? _lastPointerKind;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _handleTriggerEnter() {
    _hideTimer?.cancel();
    if (_portal.isShowing) return;
    _showTimer?.cancel();
    _showTimer = Timer(BmMotion.micro, _show);
  }

  void _handleTriggerExit() {
    _showTimer?.cancel();
    _scheduleHide();
  }

  /// 记录按下图标的指针类型；触屏 / 触控笔没有 hover，按下直接展开浮层。
  void _handleTriggerPointerDown(PointerDownEvent event) {
    _lastPointerKind = event.kind;
    if (!_tapPointerKinds.contains(event.kind)) return;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    if (!_tapOpen) setState(() => _tapOpen = true);
    _show();
  }

  /// 触屏点按只展开浮层；鼠标点击与键盘激活保留静音切换。
  void _handleTriggerPressed() {
    final kind = _lastPointerKind;
    _lastPointerKind = null;
    if (kind != null && _tapPointerKinds.contains(kind)) {
      _show();
      return;
    }
    ref.read(playbackCommandsProvider.notifier).toggleMute();
  }

  void _handlePanelEnter() => _hideTimer?.cancel();

  void _handlePanelExit() => _scheduleHide();

  void _show() {
    if (!mounted || _portal.isShowing) return;
    _portal.show();
  }

  void _hide() {
    if (!mounted) return;
    if (_tapOpen) setState(() => _tapOpen = false);
    if (!_portal.isShowing) return;
    _portal.hide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_dragging) return;
    _hideTimer = Timer(BmMotion.medium, _hide);
  }

  void _setDragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    if (value) {
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  /// 指针滚轮调音量。注册进 pointerSignalResolver：这次滚轮要算作音量调节，
  /// 不再传给背后的滚动视图。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final scrollDelta = event.scrollDelta;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final delta = scrollDelta.dy < 0 ? _wheelStep : -_wheelStep;
      final volume = ref.read(volumeProvider);
      ref
          .read(playbackCommandsProvider.notifier)
          .setVolume((volume + delta).clamp(0.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(volumeProvider);
    final isMuted = volume == 0;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: Listener(
          onPointerDown: _handleTriggerPointerDown,
          onPointerSignal: _handlePointerSignal,
          child: MouseRegion(
            onEnter: (_) => _handleTriggerEnter(),
            onExit: (_) => _handleTriggerExit(),
            child: BmIconButton(
              icon: isMuted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              semanticLabel: '音量',
              onPressed: _handleTriggerPressed,
            ),
          ),
        ),
      ),
    );
  }

  /// 点按展开时的全屏收起遮罩 + 锚在图标上沿的音量浮层。
  Widget _buildOverlay(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_tapOpen)
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _hide),
        _buildPanel(context),
      ],
    );
  }

  /// 锚在喇叭图标上沿的竖向音量条浮层。
  Widget _buildPanel(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;

    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.topCenter,
      followerAnchor: Alignment.bottomCenter,
      offset: const Offset(0, -BmTokens.s2),
      showWhenUnlinked: false,
      // Overlay 子节点拿的是整屏紧约束：先包一层 [Align]，让浮层按内容定宽，
      // 再靠 follower 的 bottomCenter 把它的下沿贴到图标上沿。
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MouseRegion(
          onEnter: (_) => _handlePanelEnter(),
          onExit: (_) => _handlePanelExit(),
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: BmMenuSurface(
              padding: const EdgeInsets.all(BmTokens.s3),
              entrance: BmMenuEntranceKind.scale,
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: _panelWidth,
                child: Consumer(
                  builder: (context, ref, _) {
                    final volume = ref.watch(volumeProvider);
                    final commands = ref.read(
                      playbackCommandsProvider.notifier,
                    );
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(volume * 100).round()}%',
                          style: BmTypography.numeric(
                            type.caption.copyWith(color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: BmTokens.s2),
                        SizedBox(
                          width: _barHitWidth,
                          height: _barLength,
                          // 横向 Slider 竖过来：0 在底部，拖动 / 点击向上增大音量。
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                trackShape: const FullWidthTrackShape(),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                                overlayColor: colors.stateHover,
                                thumbColor: colors.accent,
                                activeTrackColor: colors.accent,
                                inactiveTrackColor: colors.hairline,
                              ),
                              child: Slider(
                                value: volume.clamp(0.0, 1.0),
                                onChangeStart: (_) => _setDragging(true),
                                onChangeEnd: (_) => _setDragging(false),
                                onChanged: commands.setVolume,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
