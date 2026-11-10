import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/utils/animations.dart';

/// 详情页 Stage 背景：不透明纯黑底 + 封面虚化主层（或主色纯色底）。
///
/// 作为全屏背景层使用（放在 `Positioned.fill` 或紧约束里）。底座是不透明
/// 纯黑：详情层在壳层里淡入 / 上滑时，半透明背景会把底层页面漏出来。
/// 有封面时以 [BmAlpha.stageCover] 不透明度的封面虚化层负责 AM 式亮度；
/// 没有封面时才退回主色流体层。关闭 [fluid] 后退回封面主色纯色底 + 黑色
/// 渐变遮罩。色彩过渡只在 [dominantColor] 变化时做一次
/// [BmMotion.backdrop]，不做常驻环境动画。
class BmStageBackdrop extends StatefulWidget {
  const BmStageBackdrop({
    super.key,
    this.coverUrl = '',
    this.dominantColor,
    this.fallbackColor = const Color(0xFF6D7CFF),
    this.fluid = true,
    this.cacheManager,
  });

  /// 封面地址；为空时只显示流体色层。
  final String coverUrl;

  /// 封面主色：流体层用它的同色相加深版；关闭流体时直接铺成纯色底。
  ///
  /// 为空时流体层用 [fallbackColor]，纯色底保持纯黑。
  final Color? dominantColor;

  /// 主导色缺失 / 无彩色时的品牌色兜底。
  final Color fallbackColor;

  /// 关闭后铺封面主色纯色底 + 黑色渐变遮罩（设置里的「流体背景效果」）。
  final bool fluid;

  /// 封面纹理使用的磁盘缓存；不传则用 [CachedNetworkImage] 的默认缓存。
  final BaseCacheManager? cacheManager;

  @override
  State<BmStageBackdrop> createState() => _BmStageBackdropState();
}

class _BmStageBackdropState extends State<BmStageBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late _StagePalette _from;
  late _StagePalette _to;

  // 页面每帧都会因播放进度重建；缓存封面子树，避免 CachedNetworkImage
  // 每次 build 都新建 ImageProvider、重新 resolve 图片。
  Widget? _coverChild;
  String? _coverChildUrl;
  BaseCacheManager? _coverChildCacheManager;

  @override
  void initState() {
    super.initState();
    _from = _StagePalette.from(
      widget.dominantColor,
      fallback: widget.fallbackColor,
    );
    _to = _from;
    _controller = AnimationController(vsync: this, duration: BmMotion.backdrop)
      ..value = 1;
  }

  @override
  void didUpdateWidget(BmStageBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dominantColor != widget.dominantColor ||
        oldWidget.fallbackColor != widget.fallbackColor) {
      final target = _StagePalette.from(
        widget.dominantColor,
        fallback: widget.fallbackColor,
      );
      if (widget.coverUrl.isNotEmpty) {
        // 有封面时流体层不参与绘制，直接落色，避免空跑 400ms ticker。
        _from = target;
        _to = target;
        _controller.value = 1;
      } else {
        _animateTo(target);
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // 热重载时丢掉缓存的封面子树，让新代码立刻生效。
    _coverChild = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(_StagePalette target) {
    // 快速切歌时从上一次过渡的中间态接着走，避免颜色跳回起点。
    _from = _paletteAt(_controller.value);
    _to = target;
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  _StagePalette _paletteAt(double raw) {
    if (raw >= 1.0) return _to;
    if (raw <= 0.0) return _from;
    final t = BmMotion.standard.transform(raw);
    return _StagePalette.lerp(_from, _to, t);
  }

  @override
  Widget build(BuildContext context) {
    // 背景在稳态下完全静态：根层与封面 / 流体层各自隔离绘制，
    // 详情页随播放进度重建时不会把整幅背景重新画一遍。
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(
            key: ValueKey<String>('bm-stage-base'),
            color: Colors.black,
          ),
          if (widget.fluid) ...[
            if (widget.coverUrl.isNotEmpty)
              RepaintBoundary(child: _buildCoverTexture())
            else
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _StageFluidPainter(_paletteAt(_controller.value)),
                  ),
                ),
              ),
            const _StageVignette(),
          ] else ...[
            // 关闭流体：封面主色纯色底，切歌时做一次颜色过渡。
            AnimatedContainer(
              key: const ValueKey<String>('bm-stage-solid'),
              duration: motionDuration(context, BmMotion.backdrop),
              curve: BmMotion.standard,
              color: _stageSolidColor(widget.dominantColor),
            ),
            const _StageVignette(),
          ],
        ],
      ),
    );
  }

  Widget _buildCoverTexture() {
    return Opacity(
      opacity: BmAlpha.stageCover,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: BmTokens.stageCoverBlurSigma,
          sigmaY: BmTokens.stageCoverBlurSigma,
        ),
        child: AnimatedSwitcher(
          duration: fadeDuration(context, BmMotion.backdrop),
          switchInCurve: BmMotion.linear,
          switchOutCurve: BmMotion.linear,
          transitionBuilder: switcherFadeTransition,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          ),
          child: _buildCoverChild(),
        ),
      ),
    );
  }

  Widget _buildCoverChild() {
    if (_coverChild != null &&
        _coverChildUrl == widget.coverUrl &&
        identical(_coverChildCacheManager, widget.cacheManager)) {
      return _coverChild!;
    }
    _coverChildUrl = widget.coverUrl;
    _coverChildCacheManager = widget.cacheManager;
    return _coverChild = KeyedSubtree(
      key: ValueKey<String>(widget.coverUrl),
      // 放大一点再模糊，避免高斯采样到图片边界后四边发黑。
      child: Transform.scale(
        scale: 1.12,
        child: CachedNetworkImage(
          imageUrl: widget.coverUrl,
          fit: BoxFit.cover,
          fadeInDuration: BmMotion.medium,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => const SizedBox.shrink(),
          errorWidget: (context, url, error) => const SizedBox.shrink(),
          cacheManager: widget.cacheManager,
        ),
      ),
    );
  }
}

/// 关闭流体时的纯色底：把封面主色压到暗色区间。
///
/// 太亮会顶掉白色文字，太暗又看不见色相；无主色时保持纯黑底座。
Color _stageSolidColor(Color? source) {
  if (source == null) return Colors.black;
  final hsl = HSLColor.fromColor(source);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.0, 0.60))
      .withLightness(hsl.lightness.clamp(0.14, 0.40))
      .toColor();
}

/// 无封面时的兜底流体层：几个大尺寸的径向色团叠在纯黑上，形成色雾。
class _StageFluidPainter extends CustomPainter {
  const _StageFluidPainter(this.palette);

  final _StagePalette palette;

  /// 构图参数：每团色雾由一个大椭圆和一颗偏移卫星组成；alpha 是流体层的
  /// 艺术化叠色，不套用 UI 状态层的固定透明度档位。
  static const List<_FluidBlob> _blobs = <_FluidBlob>[
    _FluidBlob(
      center: Offset(0.30, 0.20),
      radius: Size(0.86, 0.66),
      rotation: -0.28,
      tone: _FluidTone.primary,
      alpha: 0.66,
    ),
    _FluidBlob(
      center: Offset(0.86, 0.38),
      radius: Size(0.70, 0.58),
      rotation: 0.42,
      tone: _FluidTone.secondary,
      alpha: 0.44,
    ),
    _FluidBlob(
      center: Offset(0.18, 0.72),
      radius: Size(0.76, 0.54),
      rotation: -0.18,
      tone: _FluidTone.tertiary,
      alpha: 0.38,
    ),
    _FluidBlob(
      center: Offset(0.70, 0.86),
      radius: Size(0.82, 0.48),
      rotation: 0.16,
      tone: _FluidTone.secondary,
      alpha: 0.34,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final blob in _blobs) {
      _paintBlob(canvas, size, blob);
    }
  }

  void _paintBlob(Canvas canvas, Size size, _FluidBlob blob) {
    final color = palette.colorFor(blob.tone);
    final center = Offset(
      blob.center.dx * size.width,
      blob.center.dy * size.height,
    );
    final oval = Rect.fromCenter(
      center: center,
      width: blob.radius.width * size.width * 2,
      height: blob.radius.height * size.height * 2,
    );
    final shader = RadialGradient(
      colors: <Color>[
        color.withValues(alpha: blob.alpha),
        color.withValues(alpha: blob.alpha * 0.55),
        color.withValues(alpha: 0),
      ],
      stops: const <double>[0.0, 0.46, 1.0],
    ).createShader(oval);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(blob.rotation);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawOval(
      oval,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();

    // 一颗偏移的小卫星，让色团边缘不那么像标准椭圆。
    final satellite = Rect.fromCenter(
      center: center.translate(
        blob.radius.width * size.width * 0.42,
        -blob.radius.height * size.height * 0.30,
      ),
      width: blob.radius.width * size.width * 1.05,
      height: blob.radius.height * size.height * 0.92,
    );
    final satelliteShader = RadialGradient(
      colors: <Color>[
        color.withValues(alpha: blob.alpha * 0.62),
        color.withValues(alpha: 0),
      ],
    ).createShader(satellite);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(blob.rotation + 0.45);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawOval(
      satellite,
      Paint()
        ..shader = satelliteShader
        ..blendMode = BlendMode.screen,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StageFluidPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

enum _FluidTone { primary, secondary, tertiary }

class _FluidBlob {
  const _FluidBlob({
    required this.center,
    required this.radius,
    required this.rotation,
    required this.tone,
    required this.alpha,
  });

  final Offset center;
  final Size radius;
  final double rotation;
  final _FluidTone tone;
  final double alpha;
}

/// 由封面主导色推导出的三档色雾：同色相加深、邻近色相偏移、更暗的补色。
class _StagePalette {
  const _StagePalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;

  Color colorFor(_FluidTone tone) {
    switch (tone) {
      case _FluidTone.primary:
        return primary;
      case _FluidTone.secondary:
        return secondary;
      case _FluidTone.tertiary:
        return tertiary;
    }
  }

  static _StagePalette from(Color? source, {required Color fallback}) {
    var hsl = HSLColor.fromColor(source ?? fallback);
    // 黑白封面没有可用的色相，直接借用主题主色，避免画面只剩一团灰。
    if (source != null && hsl.saturation < 0.08) {
      hsl = HSLColor.fromColor(fallback);
    }
    final lightness = hsl.lightness.clamp(0.24, 0.56);
    final saturation = hsl.saturation.clamp(0.12, 0.78);

    Color tone(double hueShift, double saturationScale, double lightnessScale) {
      final shifted = (hsl.hue + hueShift + 360) % 360;
      return hsl
          .withHue(shifted)
          .withSaturation((saturation * saturationScale).clamp(0.0, 1.0))
          .withLightness((lightness * lightnessScale).clamp(0.06, 0.52))
          .toColor();
    }

    return _StagePalette(
      primary: tone(0, 1.0, 1.0),
      secondary: tone(36, 0.9, 0.82),
      tertiary: tone(-46, 0.8, 0.62),
    );
  }

  static _StagePalette lerp(_StagePalette a, _StagePalette b, double t) {
    return _StagePalette(
      primary: Color.lerp(a.primary, b.primary, t)!,
      secondary: Color.lerp(a.secondary, b.secondary, t)!,
      tertiary: Color.lerp(a.tertiary, b.tertiary, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _StagePalette &&
        other.primary == primary &&
        other.secondary == secondary &&
        other.tertiary == tertiary;
  }

  @override
  int get hashCode => Object.hash(primary, secondary, tertiary);
}

/// 顶部轻压暗 + 底部/右侧渐暗，保证白色文字在明亮封面色上也可读。
///
/// 不压整幅画面：AM 式背景的亮度主要来自封面虚化层，只在底部控制区和
/// 右侧歌词区收暗。
class _StageVignette extends StatelessWidget {
  const _StageVignette();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x24000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x52000000),
                  Color(0xB8000000),
                ],
                stops: <double>[0.0, 0.12, 0.55, 0.78, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[Color(0x00000000), Color(0x4D000000)],
                stops: <double>[0.40, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
