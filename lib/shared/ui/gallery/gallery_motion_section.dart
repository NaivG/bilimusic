import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/motion/motion_tokens.dart';
import 'package:bilimusic/shared/ui/gallery/gallery_sections.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 分区 7：M0 动效预览。
///
/// 交互四态用 [BmPressable] 直接演示；时长表可直接选中一档，方块按该档
/// 跑一次位移。页面外层用 `MediaQuery.disableAnimations` 广播 reduce motion，
/// 本分区读取它并关闭位移动画。
class GalleryMotionSection extends StatefulWidget {
  const GalleryMotionSection({super.key});

  @override
  State<GalleryMotionSection> createState() => _GalleryMotionSectionState();
}

class _GalleryMotionSectionState extends State<GalleryMotionSection>
    with SingleTickerProviderStateMixin {
  static const List<_MotionToken> _tokens = <_MotionToken>[
    _MotionToken('instant', BmMotion.instant, '文本选择 / 滚动 / 输入法'),
    _MotionToken('micro', BmMotion.micro, 'hover / pressed 状态层'),
    _MotionToken('small', BmMotion.small, '菜单 / tooltip / focus ring'),
    _MotionToken('medium', BmMotion.medium, '对话框 / toast / chip'),
    _MotionToken('large', BmMotion.large, '列表进出 / 展开折叠'),
    _MotionToken('xlarge', BmMotion.xlarge, '页面 push / 详情内容层'),
    _MotionToken('hero', BmMotion.hero, '封面 morph'),
    _MotionToken('backdrop', BmMotion.backdrop, '背景 crossfade'),
    _MotionToken('sheetMax', BmMotion.sheetMax, 'Sheet 弹簧上限'),
  ];

  late final AnimationController _controller;
  _MotionToken _selected = _tokens[3];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _selected.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSquare() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 0;
      return;
    }
    _controller.duration = _selected.duration;
    _controller.forward(from: 0);
  }

  void _resetSquare() {
    _controller.stop();
    _controller.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return GallerySection(
      title: 'M0 动效',
      description:
          'BmPressable 四态、BmMotion 时长表与一次方块位移；'
          'reduce motion 时只关闭位移，不裁剪状态信息。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BmPressable',
            style: type.label.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: BmTokens.s2),
          _buildPressables(context),
          const SizedBox(height: BmTokens.s4),
          const Divider(),
          const SizedBox(height: BmTokens.s3),
          Text(
            '时长表（点一行作为方块动画的时长）',
            style: type.label.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: BmTokens.s2),
          _buildDurationTable(context),
          const SizedBox(height: BmTokens.s4),
          _buildSquare(context),
        ],
      ),
    );
  }

  Widget _buildPressables(BuildContext context) {
    return Wrap(
      spacing: BmTokens.s3,
      runSpacing: BmTokens.s3,
      children: [
        _PressableDemo(
          label: 'hover / pressed',
          hint: '悬停或按住',
          child: BmPressable(
            onTap: () {},
            borderRadius: BmTokens.r10All,
            child: _pressableSurface(context),
          ),
        ),
        _PressableDemo(
          label: 'focus',
          hint: 'Tab 键聚焦',
          child: BmPressable(
            onTap: () {},
            borderRadius: BmTokens.r10All,
            child: _pressableSurface(context),
          ),
        ),
        _PressableDemo(
          label: 'selected',
          hint: 'selected: true',
          child: BmPressable(
            selected: true,
            onTap: () {},
            borderRadius: BmTokens.r10All,
            child: _pressableSurface(context),
          ),
        ),
        _PressableDemo(
          label: 'disabled',
          hint: 'enabled: false',
          child: BmPressable(
            enabled: false,
            borderRadius: BmTokens.r10All,
            child: _pressableSurface(context),
          ),
        ),
      ],
    );
  }

  Widget _pressableSurface(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      height: BmTokens.controlLg,
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BmTokens.r10All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: BmTokens.iconMenu,
            color: colors.textSecondary,
          ),
          const SizedBox(width: BmTokens.s1),
          Text(
            'BmPressable',
            style: type.label.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationTable(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      children: [
        for (final token in _tokens)
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() => _selected = token),
              borderRadius: BmTokens.r10All,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BmTokens.s3,
                  vertical: BmTokens.s1,
                ),
                decoration: BoxDecoration(
                  color: token == _selected ? colors.accentSoft : null,
                  borderRadius: BmTokens.r10All,
                ),
                child: Row(
                  children: [
                    Icon(
                      token == _selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: BmTokens.iconMenu,
                      color: token == _selected
                          ? colors.accent
                          : colors.textTertiary,
                    ),
                    const SizedBox(width: BmTokens.s2),
                    SizedBox(
                      width: BmTokens.s8 * 2,
                      child: Text(
                        token.name,
                        style: type.label.copyWith(color: colors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: BmTokens.s8 * 2,
                      child: Text(
                        _durationText(token.duration),
                        style: BmTypography.numeric(
                          type.caption.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        token.usage,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSquare(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final squareSize = BmTokens.s8 * 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: BmTokens.s3,
          runSpacing: BmTokens.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '方块动画 · ${_selected.name} · '
              '${_selected.duration.inMilliseconds} ms',
              style: type.label.copyWith(color: colors.textPrimary),
            ),
            FilledButton(onPressed: _runSquare, child: const Text('播放一次')),
            TextButton(onPressed: _resetSquare, child: const Text('归位')),
          ],
        ),
        if (reduceMotion) ...[
          const SizedBox(height: BmTokens.s1),
          Text(
            'reduce motion 已开启：位移动画关闭',
            style: type.micro.copyWith(color: colors.warning),
          ),
        ],
        const SizedBox(height: BmTokens.s3),
        Container(
          height: squareSize + BmTokens.s1 * 2,
          padding: const EdgeInsets.all(BmTokens.s1),
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BmTokens.r10All,
            border: Border.all(color: colors.hairline, width: 0.5),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Align(
                alignment: Alignment(-1 + 2 * _controller.value, 0),
                child: child,
              );
            },
            child: Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BmTokens.r10All,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.music_note_rounded,
                size: BmTokens.iconLarge,
                color: colors.onAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Sheet 上限不是固定时长，展示时带 `≤`。
  String _durationText(Duration duration) {
    if (duration == BmMotion.sheetMax) {
      return '≤ ${duration.inMilliseconds} ms';
    }
    return '${duration.inMilliseconds} ms';
  }
}

class _PressableDemo extends StatelessWidget {
  const _PressableDemo({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: type.label.copyWith(color: colors.textPrimary)),
        Text(hint, style: type.micro.copyWith(color: colors.textTertiary)),
        const SizedBox(height: BmTokens.s2),
        child,
      ],
    );
  }
}

/// 一行动效 token：名称、时长与用途。
class _MotionToken {
  const _MotionToken(this.name, this.duration, this.usage);

  final String name;
  final Duration duration;
  final String usage;
}
