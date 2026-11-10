import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/storage/cache_manager.dart';
import 'package:bilimusic/domain/bili_image.dart';

/// 瀑布流里的一张封面。
///
/// 用轻量数据而不是 [Music]，这样歌单封面、当前队列封面和候选种子
/// 可以混在同一个装饰层里。
@immutable
class RoamCoverData {
  const RoamCoverData({
    required this.imageUrl,
    required this.cacheKey,
    this.seed = 0,
  });

  final String imageUrl;
  final String cacheKey;
  final int seed;
}

/// 慢速漂移的封面瀑布。
///
/// 每列独立速度、上下交错，用两段重复内容做无缝循环；只做装饰，
/// 不接收点击事件。封面为空时用主题渐变占位，不会出现空白列。
class RoamCoverWaterfall extends StatefulWidget {
  const RoamCoverWaterfall({
    super.key,
    required this.covers,
    this.minColumnWidth = 104,
    this.maxColumns = 7,
    this.gap = 8,
    this.tileRadius = 12,
    this.opacity = 1,
    this.fadeEdges = true,
    this.alternateDirection = true,
  });

  final List<RoamCoverData> covers;
  final double minColumnWidth;
  final int maxColumns;
  final double gap;
  final double tileRadius;
  final double opacity;

  /// 上下边缘渐隐，避免生硬的裁切边。
  final bool fadeEdges;

  /// 奇数列反向滚动，形成交错感。
  final bool alternateDirection;

  @override
  State<RoamCoverWaterfall> createState() => _RoamCoverWaterfallState();
}

class _RoamCoverWaterfallState extends State<RoamCoverWaterfall>
    with SingleTickerProviderStateMixin {
  static const List<double> _heightRatios = [
    1.0,
    0.72,
    1.28,
    0.86,
    1.12,
    0.64,
    0.94,
  ];

  static const List<double> _columnSpeeds = [1.0, 2.0, 1.0, 2.0, 1.0, 2.0, 1.0];

  late final AnimationController _controller;
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final columns = (constraints.maxWidth / widget.minColumnWidth)
            .floor()
            .clamp(2, widget.maxColumns);
        final columnWidth =
            (constraints.maxWidth - widget.gap * (columns - 1)) / columns;

        final stack = Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (int i = 0; i < columns; i++)
              _buildColumn(
                context: context,
                column: i,
                columnWidth: columnWidth,
                viewportHeight: constraints.maxHeight,
              ),
          ],
        );

        final faded = widget.fadeEdges
            ? ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.14, 0.86, 1.0],
                ).createShader(rect),
                child: stack,
              )
            : stack;

        return IgnorePointer(
          child: Opacity(opacity: widget.opacity, child: faded),
        );
      },
    );
  }

  Widget _buildColumn({
    required BuildContext context,
    required int column,
    required double columnWidth,
    required double viewportHeight,
  }) {
    final specs = _buildSpecs(
      column: column,
      columnWidth: columnWidth,
      viewportHeight: viewportHeight,
    );
    final passHeight = _passHeight(specs);
    final stride = passHeight + widget.gap;
    final contentHeight = passHeight * 2 + widget.gap;

    final direction = widget.alternateDirection && column.isOdd ? -1.0 : 1.0;
    final speed = _columnSpeeds[column % _columnSpeeds.length];
    final startPhase = (column * 0.137) % 1.0;

    final columnContent = RepaintBoundary(
      child: SizedBox(
        height: contentHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._buildTiles(context, specs, columnWidth),
            SizedBox(height: widget.gap),
            ..._buildTiles(context, specs, columnWidth),
          ],
        ),
      ),
    );

    return Positioned(
      left: column * (columnWidth + widget.gap),
      top: 0,
      width: columnWidth,
      height: contentHeight,
      child: AnimatedBuilder(
        animation: _controller,
        child: columnContent,
        builder: (context, child) {
          final t = _animationsDisabled ? 0.0 : _controller.value;
          final phase = (startPhase + t * speed * direction) % 1.0;
          return Transform.translate(
            offset: Offset(0, -phase * stride),
            child: child,
          );
        },
      ),
    );
  }

  List<_WaterfallSpec> _buildSpecs({
    required int column,
    required double columnWidth,
    required double viewportHeight,
  }) {
    final specs = <_WaterfallSpec>[];
    double height = 0;
    int index = column * 3;
    final extra = (columnWidth * 1.2).clamp(96.0, 260.0);

    while (height < viewportHeight + extra || specs.length < 3) {
      final ratio = _heightRatios[(index + column) % _heightRatios.length];
      final tileHeight = (columnWidth * ratio).clamp(56.0, 260.0);
      specs.add(
        _WaterfallSpec(cover: _coverAt(index), height: tileHeight, seed: index),
      );
      height += tileHeight + (specs.length > 1 ? widget.gap : 0);
      index++;
      if (specs.length >= 40) break;
    }

    return specs;
  }

  RoamCoverData? _coverAt(int index) {
    if (widget.covers.isEmpty) return null;
    // 封面很少时穿插主题占位块，避免同一张图重复铺满整列。
    if (widget.covers.length < 4 && index % 4 == 1) return null;
    return widget.covers[index % widget.covers.length];
  }

  double _passHeight(List<_WaterfallSpec> specs) {
    double height = 0;
    for (int i = 0; i < specs.length; i++) {
      if (i > 0) height += widget.gap;
      height += specs[i].height;
    }
    return height;
  }

  List<Widget> _buildTiles(
    BuildContext context,
    List<_WaterfallSpec> specs,
    double width,
  ) {
    final tiles = <Widget>[];
    for (int i = 0; i < specs.length; i++) {
      if (i > 0) tiles.add(SizedBox(height: widget.gap));
      final spec = specs[i];
      tiles.add(
        SizedBox(
          height: spec.height,
          child: _WaterfallTile(
            cover: spec.cover,
            radius: widget.tileRadius,
            seed: spec.seed,
          ),
        ),
      );
    }
    return tiles;
  }
}

class _WaterfallSpec {
  const _WaterfallSpec({
    required this.cover,
    required this.height,
    required this.seed,
  });

  final RoamCoverData? cover;
  final double height;
  final int seed;
}

class _WaterfallTile extends StatelessWidget {
  const _WaterfallTile({
    required this.cover,
    required this.radius,
    required this.seed,
  });

  final RoamCoverData? cover;
  final double radius;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = cover;
    final hasImage = data != null && _isValidImageUrl(data.imageUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            CachedNetworkImage(
              imageUrl: biliSquareUrl(data.imageUrl, 320),
              cacheKey: '${data.cacheKey}_320',
              memCacheWidth: 320,
              cacheManager: imageCacheManager,
              httpHeaders: NetworkConfig.biliHeaders,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 320),
              placeholder: (_, _) => _placeholder(scheme),
              errorWidget: (_, _, _) => _placeholder(scheme),
            )
          else
            _placeholder(scheme),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x24FFFFFF),
                  Color(0x00FFFFFF),
                  Color(0x33000000),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) {
    final base = Color.lerp(scheme.primary, scheme.tertiary, (seed % 7) / 7)!;
    final accent = Color.lerp(
      scheme.secondary,
      scheme.primary,
      ((seed + 3) % 7) / 7,
    )!;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: 0.78),
            accent.withValues(alpha: 0.92),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 24,
          color: scheme.onPrimary.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  bool _isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    return Uri.tryParse(url)?.hasAbsolutePath == true;
  }
}
