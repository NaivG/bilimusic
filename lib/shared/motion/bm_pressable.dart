import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// hover / pressed / focus / selected 四态的统一状态层。
///
/// 状态层颜色与时长固定走 token：hover 6%、pressed 10%、selected 12%，
/// 进场 80ms、退场 120ms；reduce motion 下直接切到终态。
/// 不叠 Material 水波（全局 splashFactory 已关），不做布局变化。
///
/// ```dart
/// BmPressable(
///   onTap: play,
///   pressScale: BmMotion.pressScale,
///   child: const Icon(Icons.play_arrow),
/// )
/// ```
class BmPressable extends StatefulWidget {
  const BmPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.pressScale,
    this.selected = false,
    this.enabled = true,
    this.overlayColor,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 状态层的圆角；默认 [BmTokens.r10All]。
  final BorderRadiusGeometry? borderRadius;

  /// 按压缩放；null 表示不缩放（列表行不要缩放）。
  final double? pressScale;

  /// 选中态：accent 12% 底。
  final bool selected;

  final bool enabled;

  /// 覆盖状态层颜色（Stage 上需要白色状态层时用）。
  final Color? overlayColor;

  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<BmPressable> createState() => _BmPressableState();
}

class _BmPressableState extends State<BmPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _showFocusHighlight = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  Color? _stateColor(BmColors colors) {
    final overlay = widget.overlayColor;
    if (overlay != null) {
      if (_pressed && _interactive) return overlay;
      if (_hovered && _interactive) {
        // hover 取覆盖色的 60%（6% / 10% 的固定比例）
        return overlay.withValues(alpha: overlay.a * 0.6);
      }
      return widget.selected
          ? overlay.withValues(alpha: overlay.a * 0.6)
          : null;
    }
    if (_pressed && _interactive) return colors.statePressed;
    if (_hovered && _interactive) return colors.stateHover;
    if (widget.selected) return colors.stateSelected;
    return null;
  }

  void _activate() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final reduce = reduceMotionOf(context);
    final radius = widget.borderRadius ?? BmTokens.r10All;
    final duration = reduce
        ? Duration.zero
        : (_pressed || _hovered ? BmMotion.micro : BmMotion.small);
    final scale = _pressed && _interactive && !reduce
        ? widget.pressScale ?? 1.0
        : 1.0;

    return Semantics(
      button: _interactive,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onShowFocusHighlight: (value) {
          if (_showFocusHighlight == value) return;
          setState(() => _showFocusHighlight = value);
        },
        onShowHoverHighlight: _setHovered,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ButtonActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTapDown: _interactive ? (_) => _setPressed(true) : null,
          onTapUp: _interactive ? (_) => _setPressed(false) : null,
          onTapCancel: _interactive ? () => _setPressed(false) : null,
          onTap: widget.enabled ? widget.onTap : null,
          onLongPress: widget.enabled && widget.onLongPress != null
              ? () {
                  _setPressed(false);
                  widget.onLongPress!.call();
                }
              : null,
          child: AnimatedScale(
            scale: scale,
            duration: duration,
            curve: BmMotion.standard,
            child: AnimatedOpacity(
              // 禁用态统一降到 38%，不靠调用方各自调透明度
              opacity: widget.enabled ? 1.0 : BmAlpha.disabled,
              duration: reduce ? Duration.zero : BmMotion.small,
              child: AnimatedContainer(
                duration: duration,
                curve: BmMotion.standard,
                decoration: BoxDecoration(
                  color: _stateColor(colors),
                  borderRadius: radius,
                  border: _showFocusHighlight
                      ? Border.all(color: colors.accentBorder, width: 2)
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
