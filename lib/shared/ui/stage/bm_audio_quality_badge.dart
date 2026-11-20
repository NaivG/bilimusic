import 'package:flutter/material.dart';

import 'package:bilimusic/domain/audio_quality.dart';
import 'package:bilimusic/shared/motion/motion_scope.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/motion/spring_curve.dart';
import 'package:bilimusic/shared/ui/stage/audio_quality_icons.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/svg_path.dart';

/// 品牌标志高度：与 11px 档正文同高（对齐 AMLL 的 11px 标志）。
const double _brandGlyphHeight = 11;

/// 杜比字标的一次性辉光：出现 1s 后开始淡出，3s 淡完（对齐 AMLL）。
///
/// 这是品牌出场的艺术化时长，不属于 UI 过渡档位，所以不套 [BmMotion]。
const Duration _dolbyGlowDuration = Duration(seconds: 4);
const double _dolbyGlowDelayFraction = 0.25;
const double _dolbyGlowBlurSigma = 7;

final Path _losslessIconPath = svgPathFromData(kLosslessIconPathData);

final Path _dolbyAtmosIconPath = svgPathFromData(kDolbyAtmosIconPathData)
  ..fillType = PathFillType.evenOdd;

/// Apple Music 风格音质徽标（对齐 AMLL 的 `AudioQualityTag`）。
///
/// 白色 20% 胶囊 + 11/14 w500 文案：无损档在左侧画 ALAC 波形标志，
/// 杜比全景声只画 Dolby Atmos 字标（带一次性辉光），标准档只留文案。
/// 换档时淡入 + 缩放进场；reduce motion 下直接落到终态。
///
/// ```dart
/// BmAudioQualityBadge(qualityId: '30251')
/// ```
class BmAudioQualityBadge extends StatefulWidget {
  const BmAudioQualityBadge({super.key, required this.qualityId});

  /// 取流接口的音质代码（30xxx）；未知代码按 192K HQ 显示。
  final String qualityId;

  @override
  State<BmAudioQualityBadge> createState() => _BmAudioQualityBadgeState();
}

class _BmAudioQualityBadgeState extends State<BmAudioQualityBadge>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final AnimationController _glowController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _glowOpacity;

  AudioQualityInfo get _quality => AudioQualityInfo.of(widget.qualityId);

  bool get _isDolby => _quality.kind == AudioQualityKind.dolbyAtmos;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: BmMotion.xlarge,
    );
    _opacity = CurvedAnimation(
      parent: _enterController,
      curve: BmMotion.standard,
    );
    _scale = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(
        parent: _enterController,
        curve: SpringCurve(BmMotion.pressSpring, seconds: 0.32),
      ),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: _dolbyGlowDuration,
    );
    _glowOpacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _glowController,
        curve: const Interval(
          _dolbyGlowDelayFraction,
          1,
          curve: BmMotion.linear,
        ),
      ),
    );
    _enterController.forward();
    if (_isDolby) _glowController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _enterController.value = 1;
      _glowController.value = 1;
    }
  }

  @override
  void didUpdateWidget(BmAudioQualityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.qualityId == widget.qualityId) return;
    if (reduceMotionOf(context)) {
      _enterController.value = 1;
      _glowController.value = 1;
      return;
    }
    _enterController.forward(from: 0);
    if (_isDolby) {
      _glowController.forward(from: 0);
    } else {
      _glowController.value = 1;
    }
  }

  @override
  void dispose() {
    _enterController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final quality = _quality;
    final reduceMotion = reduceMotionOf(context);
    final glyphHeight = MediaQuery.textScalerOf(context)
        .scale(_brandGlyphHeight);

    final content = quality.showsLabel
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (quality.showsLosslessIcon) ...<Widget>[
                _QualityGlyph(
                  key: const ValueKey<String>('bm-audio-quality-lossless-icon'),
                  path: _losslessIconPath,
                  viewBox: const Size(kLosslessIconWidth, kLosslessIconHeight),
                  height: glyphHeight,
                  color: colors.stageText,
                ),
                const SizedBox(width: BmTokens.s1),
              ],
              Text(
                quality.label,
                maxLines: 1,
                style: type.micro.copyWith(
                  color: colors.stageText,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          )
        : _buildDolbyGlyph(colors, glyphHeight, reduceMotion);

    final badge = ClipRRect(
      borderRadius: BmTokens.rPillAll,
      child: ColoredBox(
        color: colors.stageBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s2,
            vertical: BmTokens.s1,
          ),
          child: content,
        ),
      ),
    );

    return Semantics(
      container: true,
      label: '音质：${quality.label}',
      child: ExcludeSemantics(
        child: FadeTransition(
          key: const ValueKey<String>('bm-audio-quality-badge-fade'),
          opacity: _opacity,
          child: ScaleTransition(scale: _scale, child: badge),
        ),
      ),
    );
  }

  Widget _buildDolbyGlyph(
    BmColors colors,
    double glyphHeight,
    bool reduceMotion,
  ) {
    final glyph = _QualityGlyph(
      key: const ValueKey<String>('bm-audio-quality-dolby-icon'),
      path: _dolbyAtmosIconPath,
      viewBox: const Size(kDolbyAtmosIconWidth, kDolbyAtmosIconHeight),
      height: glyphHeight,
      color: colors.stageText,
    );
    if (reduceMotion) return glyph;

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        FadeTransition(
          key: const ValueKey<String>('bm-audio-quality-dolby-glow'),
          opacity: _glowOpacity,
          child: _QualityGlyph(
            path: _dolbyAtmosIconPath,
            viewBox: const Size(kDolbyAtmosIconWidth, kDolbyAtmosIconHeight),
            height: glyphHeight,
            color: colors.stageText,
            glow: true,
          ),
        ),
        glyph,
      ],
    );
  }
}

/// 按 viewBox 等比缩放的品牌矢量标志。
class _QualityGlyph extends StatelessWidget {
  const _QualityGlyph({
    super.key,
    required this.path,
    required this.viewBox,
    required this.height,
    required this.color,
    this.glow = false,
  });

  final Path path;
  final Size viewBox;
  final double height;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final width = height * viewBox.width / viewBox.height;
    return CustomPaint(
      size: Size(width, height),
      painter: _QualityGlyphPainter(
        path: path,
        viewBox: viewBox,
        color: color,
        glow: glow,
      ),
    );
  }
}

class _QualityGlyphPainter extends CustomPainter {
  const _QualityGlyphPainter({
    required this.path,
    required this.viewBox,
    required this.color,
    required this.glow,
  });

  final Path path;
  final Size viewBox;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || viewBox.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (glow) {
      paint.maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        _dolbyGlowBlurSigma,
      );
    }
    canvas.save();
    canvas.scale(size.width / viewBox.width, size.height / viewBox.height);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QualityGlyphPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.viewBox != viewBox ||
        oldDelegate.color != color ||
        oldDelegate.glow != glow;
  }
}
