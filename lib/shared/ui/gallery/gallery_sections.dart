import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/stage/bm_audio_quality_badge.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// 预览页每个分区的统一外壳：标题、说明与内容。
///
/// 背景 / 边框 / 排版全部读当前 [Theme] 里的 Lucent token，
/// 让同一份布局在 12 套主题组合下只换色不换形。
class GallerySection extends StatelessWidget {
  const GallerySection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BmTokens.s4),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: type.headline.copyWith(color: colors.textPrimary),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: BmTokens.s3),
                trailing!,
              ],
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: BmTokens.s1),
            Text(
              description!,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: BmTokens.s4),
          child,
        ],
      ),
    );
  }
}

/// 分区 2：遍历 [BmColors] 的全部角色，色块 + 角色名 + hex。
class GalleryColorRolesSection extends StatelessWidget {
  const GalleryColorRolesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final roles = <(String, Color, String)>[
      ('bg', colors.bg, '页面底'),
      ('surface', colors.surface, '内容面'),
      ('surfaceRaised', colors.surfaceRaised, '卡片 / 行'),
      ('surfaceSunken', colors.surfaceSunken, '输入框 / 搜索框'),
      ('chrome', colors.chrome, '贴边栏 72%'),
      ('chromeOpaque', colors.chromeOpaque, '无模糊贴边栏 96%'),
      ('floating', colors.floating, '浮层 96%'),
      ('textPrimary', colors.textPrimary, '主文字'),
      ('textSecondary', colors.textSecondary, '次文字'),
      ('textTertiary', colors.textTertiary, '辅助信息'),
      ('accent', colors.accent, '主色'),
      ('onAccent', colors.onAccent, '主色上的文字'),
      ('accentSoft', colors.accentSoft, '选中底 12%'),
      ('accentBorder', colors.accentBorder, '描边 / 指示条 24%'),
      ('hairline', colors.hairline, '0.5px 分割线'),
      ('stateHover', colors.stateHover, 'hover 状态层'),
      ('statePressed', colors.statePressed, 'pressed 状态层'),
      ('stateSelected', colors.stateSelected, 'selected 状态层'),
      ('danger', colors.danger, '危险'),
      ('onDanger', colors.onDanger, '危险上的文字'),
      ('warning', colors.warning, '警告'),
      ('success', colors.success, '成功'),
      ('stageText', colors.stageText, 'Stage 主文字'),
      ('stageTextSecondary', colors.stageTextSecondary, 'Stage 次文字 72%'),
      ('stageControlFill', colors.stageControlFill, 'Stage 控件填充'),
      ('stageBorder', colors.stageBorder, 'Stage 控件描边'),
      ('shadow', colors.shadow, '浮层阴影'),
      ('shadowStrong', colors.shadowStrong, '强阴影'),
      ('scrim', colors.scrim, '遮罩 32%'),
      ('dim', colors.dim, '页面切换压暗 15%'),
    ];
    return GallerySection(
      title: '颜色角色',
      description:
          'BmColors 全部 ${roles.length} 个角色；色值由当前主题的 ColorScheme + AppPalette 派生，'
          '半透明角色按当前 surface 叠加显示。',
      child: Wrap(
        spacing: BmTokens.s2,
        runSpacing: BmTokens.s2,
        children: [
          for (final (name, color, note) in roles)
            _ColorRoleCard(name: name, color: color, note: note),
        ],
      ),
    );
  }
}

class _ColorRoleCard extends StatelessWidget {
  const _ColorRoleCard({
    required this.name,
    required this.color,
    required this.note,
  });

  final String name;
  final Color color;
  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      width: BmTokens.s8 * 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: BmTokens.s8 * 2,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BmTokens.r10All,
              border: Border.all(color: colors.hairline, width: 0.5),
            ),
          ),
          const SizedBox(height: BmTokens.s1),
          Text(
            name,
            style: type.label.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _hex(color),
            style: BmTypography.numeric(
              type.micro.copyWith(color: colors.textSecondary),
            ),
            maxLines: 1,
          ),
          Text(
            note,
            style: type.micro.copyWith(color: colors.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 分区 3：Chrome / Canvas / Stage 三档材质示意。
class GalleryMaterialTiersSection extends StatelessWidget {
  const GalleryMaterialTiersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: '三档材质',
      description:
          '同一套 token，按界面位置切换背景、边框与文字层级：Chrome 退后、Canvas 承载内容、Stage 给封面让位。',
      child: Wrap(
        spacing: BmTokens.s3,
        runSpacing: BmTokens.s3,
        children: const [
          _MaterialTierCard(
            title: 'Chrome',
            spec: 'surface 72% · hairline · r14 浮块',
            child: _ChromeDemo(),
          ),
          _MaterialTierCard(
            title: 'Canvas',
            spec: 'surface 不透明 · r10 / r14',
            child: _CanvasDemo(),
          ),
          _MaterialTierCard(
            title: 'Stage',
            spec: '主色 → surface 渐变 · 胶囊',
            child: _StageDemo(),
          ),
        ],
      ),
    );
  }
}

class _MaterialTierCard extends StatelessWidget {
  const _MaterialTierCard({
    required this.title,
    required this.spec,
    required this.child,
  });

  final String title;
  final String spec;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      width: BmTokens.s8 * 9,
      padding: const EdgeInsets.all(BmTokens.s3),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: type.label.copyWith(color: colors.textPrimary)),
          Text(
            spec,
            style: type.micro.copyWith(color: colors.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: BmTokens.s2),
          Container(
            padding: const EdgeInsets.all(BmTokens.s2),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BmTokens.r10All,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ChromeDemo extends StatelessWidget {
  const _ChromeDemo();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: BmTokens.s3,
            vertical: BmTokens.s2,
          ),
          decoration: BoxDecoration(
            color: colors.chrome,
            border: Border(
              bottom: BorderSide(color: colors.hairline, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.music_note_rounded,
                size: BmTokens.iconMenu,
                color: colors.textSecondary,
              ),
              const SizedBox(width: BmTokens.s2),
              Expanded(
                child: Text(
                  '贴边栏：直角 + 底边 hairline',
                  style: type.label.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BmTokens.s3),
        Container(
          padding: const EdgeInsets.all(BmTokens.s3),
          decoration: BoxDecoration(
            color: colors.floating,
            borderRadius: BmTokens.r14All,
            border: Border.all(color: colors.hairline, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: BmTokens.s4,
                offset: const Offset(0, BmTokens.s1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '浮块：14 圆角 + shadow',
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: BmTokens.s1),
              Text(
                '菜单 / 对话框 / Sheet / Tooltip / Toast',
                style: type.micro.copyWith(color: colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CanvasDemo extends StatelessWidget {
  const _CanvasDemo();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      padding: const EdgeInsets.all(BmTokens.s1),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BmTokens.r10All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: const Column(
        children: [
          _CanvasRow(
            title: '当前播放',
            subtitle: '选中：accent 12% 底 + 2px 条',
            selected: true,
          ),
          SizedBox(height: BmTokens.s1),
          _CanvasRow(
            title: '普通列表行',
            subtitle: 'rowTall 56 / 10 圆角',
            selected: false,
          ),
        ],
      ),
    );
  }
}

class _CanvasRow extends StatelessWidget {
  const _CanvasRow({
    required this.title,
    required this.subtitle,
    required this.selected,
  });

  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      height: BmTokens.rowTall,
      padding: const EdgeInsets.symmetric(horizontal: BmTokens.s3),
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.surfaceRaised,
        borderRadius: BmTokens.r10All,
      ),
      child: Row(
        children: [
          if (selected) ...[
            Container(
              width: 2,
              height: BmTokens.s6,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BmTokens.rPillAll,
              ),
            ),
            const SizedBox(width: BmTokens.s2),
          ],
          Container(
            width: BmTokens.s8 + BmTokens.s2,
            height: BmTokens.s8 + BmTokens.s2,
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BmTokens.r10All,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.music_note_rounded,
              size: BmTokens.iconMenu,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: BmTokens.s3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: type.bodyStrong.copyWith(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: type.micro.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: BmTokens.icon,
            color: colors.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _StageDemo extends StatelessWidget {
  const _StageDemo();

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      padding: const EdgeInsets.all(BmTokens.s3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.accent, colors.surface],
        ),
        borderRadius: BmTokens.r14All,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: BmTokens.s8 + BmTokens.s2,
                height: BmTokens.s8 + BmTokens.s2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[colors.accentBorder, colors.accent],
                  ),
                  borderRadius: BmTokens.r10All,
                ),
              ),
              const SizedBox(width: BmTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stage 曲名',
                      style: type.title.copyWith(color: colors.stageText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '歌手 · 副标题',
                      style: type.caption.copyWith(
                        color: colors.stageTextSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BmTokens.s3),
          Row(
            children: const [
              _StageControl(icon: Icons.skip_previous_rounded),
              SizedBox(width: BmTokens.s2),
              _StageControl(icon: Icons.play_arrow_rounded),
              SizedBox(width: BmTokens.s2),
              _StageControl(icon: Icons.skip_next_rounded),
              Spacer(),
              _StageControl(icon: Icons.more_horiz_rounded),
            ],
          ),
          const SizedBox(height: BmTokens.s3),
          Wrap(
            spacing: BmTokens.s2,
            runSpacing: BmTokens.s1,
            children: const <Widget>[
              BmAudioQualityBadge(qualityId: '30251'),
              BmAudioQualityBadge(qualityId: '30250'),
              BmAudioQualityBadge(qualityId: '30280'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageControl extends StatelessWidget {
  const _StageControl({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      width: BmTokens.s8 + BmTokens.s2,
      height: BmTokens.s8 + BmTokens.s2,
      decoration: BoxDecoration(
        color: colors.stageControlFill,
        borderRadius: BmTokens.rPillAll,
        border: Border.all(color: colors.stageBorder, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: BmTokens.icon, color: colors.stageText),
    );
  }
}

/// 分区 4：8 档排版，角色名 + 规格 + 中英文样例。
class GalleryTypographySection extends StatelessWidget {
  const GalleryTypographySection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final roles = <(String, TextStyle, String)>[
      ('display', type.display, '舞台大标题'),
      ('title', type.title, '详情页曲名 / 空态标题'),
      ('headline', type.headline, '页面标题 / 对话框标题'),
      ('body', type.body, '正文 / 列表主标题'),
      ('bodyStrong', type.bodyStrong, '强调 / 当前播放'),
      ('label', type.label, '按钮 / Tab / 次要操作'),
      ('caption', type.caption, '次要信息 / 歌手 / 时间'),
      ('micro', type.micro, '徽标 / HQ / 辅助'),
    ];
    return GallerySection(
      title: '排版 8 档',
      description: '字号 / 行高 / 字重全部来自 BmTypography；时间与进度用等宽数字。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, style, usage) in roles)
            Padding(
              padding: const EdgeInsets.only(bottom: BmTokens.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: BmTokens.s8 * 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: type.label.copyWith(color: colors.textPrimary),
                        ),
                        Text(
                          _typeSpec(style),
                          style: BmTypography.numeric(
                            type.micro.copyWith(color: colors.textTertiary),
                          ),
                        ),
                        Text(
                          usage,
                          style: type.micro.copyWith(
                            color: colors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BmTokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BiliMusic 音乐播放器',
                          style: style.copyWith(color: colors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'The quick brown fox jumps over the lazy dog',
                          style: style.copyWith(color: colors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Divider(),
          const SizedBox(height: BmTokens.s2),
          Wrap(
            spacing: BmTokens.s3,
            runSpacing: BmTokens.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '等宽数字',
                style: type.label.copyWith(color: colors.textSecondary),
              ),
              Text(
                '00:00 / 03:45',
                style: BmTypography.numeric(
                  type.body.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                '320 kbps · 48 kHz',
                style: BmTypography.numeric(
                  type.caption.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 分区 5：形状 / 间距 / 行高 / 控件高 / 图标。
class GalleryGeometrySection extends StatelessWidget {
  const GalleryGeometrySection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final radii = <(String, BorderRadius, double)>[
      ('r4', BmTokens.r4All, BmTokens.r4),
      ('r10', BmTokens.r10All, BmTokens.r10),
      ('r14', BmTokens.r14All, BmTokens.r14),
      ('r20', BmTokens.r20All, BmTokens.r20),
      ('r28', BmTokens.r28All, BmTokens.r28),
      ('rPill', BmTokens.rPillAll, BmTokens.rPill),
    ];
    final spacings = <(String, double)>[
      ('s1', BmTokens.s1),
      ('s2', BmTokens.s2),
      ('s3', BmTokens.s3),
      ('s4', BmTokens.s4),
      ('s5', BmTokens.s5),
      ('s6', BmTokens.s6),
      ('s8', BmTokens.s8),
    ];
    final rows = <(String, double)>[
      ('rowCompact', BmTokens.rowCompact),
      ('row', BmTokens.row),
      ('rowTall', BmTokens.rowTall),
    ];
    final controls = <(String, double)>[
      ('controlSm', BmTokens.controlSm),
      ('controlMd', BmTokens.controlMd),
      ('controlLg', BmTokens.controlLg),
    ];
    final icons = <(String, double)>[
      ('iconInline', BmTokens.iconInline),
      ('iconMenu', BmTokens.iconMenu),
      ('icon', BmTokens.icon),
      ('iconLarge', BmTokens.iconLarge),
    ];
    return GallerySection(
      title: '形状 / 间距 / 尺寸',
      description: '6 档圆角、7 档间距、3 档行高、3 档控件高、4 档图标。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GeometryGroup(
            title: '圆角',
            children: [
              for (final (name, radius, value) in radii)
                _MetricTile(
                  label: '$name · ${_number(value)}',
                  sample: Container(
                    width: BmTokens.s8 + BmTokens.s4,
                    height: BmTokens.s8 + BmTokens.s4,
                    decoration: BoxDecoration(
                      color: colors.surfaceSunken,
                      borderRadius: radius,
                      border: Border.all(
                        color: colors.accentBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BmTokens.s4),
          _GeometryGroup(
            title: '间距',
            children: [
              for (final (name, value) in spacings)
                _MetricTile(
                  label: '$name · ${_number(value)}',
                  sample: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: value,
                      height: BmTokens.s2,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BmTokens.r4All,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BmTokens.s4),
          _GeometryGroup(
            title: '行高',
            children: [
              for (final (name, value) in rows)
                _MetricTile(
                  label: '$name · ${_number(value)}',
                  sample: _SizeBar(
                    width: BmTokens.s8 * 3,
                    height: value,
                    label: name,
                  ),
                ),
            ],
          ),
          const SizedBox(height: BmTokens.s4),
          _GeometryGroup(
            title: '控件高',
            children: [
              for (final (name, value) in controls)
                _MetricTile(
                  label: '$name · ${_number(value)}',
                  sample: _SizeBar(
                    width: BmTokens.s8 * 3,
                    height: value,
                    label: name,
                    subdued: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: BmTokens.s4),
          _GeometryGroup(
            title: '图标',
            children: [
              for (final (name, value) in icons)
                _MetricTile(
                  label: '$name · ${_number(value)}',
                  sample: Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: value,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeometryGroup extends StatelessWidget {
  const _GeometryGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: type.label.copyWith(color: colors.textSecondary)),
        const SizedBox(height: BmTokens.s2),
        Wrap(spacing: BmTokens.s3, runSpacing: BmTokens.s3, children: children),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.sample});

  final String label;
  final Widget sample;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      width: BmTokens.s8 * 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: BmTokens.s8 * 2, child: sample),
          const SizedBox(height: BmTokens.s1),
          Text(
            label,
            style: BmTypography.numeric(
              type.micro.copyWith(color: colors.textSecondary),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SizeBar extends StatelessWidget {
  const _SizeBar({
    required this.width,
    required this.height,
    required this.label,
    this.subdued = false,
  });

  final double width;
  final double height;
  final String label;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return SizedBox(
      height: BmTokens.s8 * 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: subdued ? colors.surfaceSunken : colors.accentSoft,
            borderRadius: BmTokens.r4All,
            border: Border.all(
              color: subdued ? colors.hairline : colors.accentBorder,
              width: 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: type.micro.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// 分区 6：Material 组件在 Lucent ThemeData 下的默认表现。
class GalleryComponentsSection extends StatelessWidget {
  const GalleryComponentsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return GallerySection(
      title: 'Material 组件',
      description:
          '同一批 Material 组件只靠 Lucent ThemeData 换皮；'
          '对话框 / 底部单 / Toast 用来核对浮层主题。',
      child: Wrap(
        spacing: BmTokens.s3,
        runSpacing: BmTokens.s3,
        children: [
          _ComponentDemo(
            label: 'Filled / Text / Outlined / Elevated',
            width: BmTokens.s8 * 12,
            child: Wrap(
              spacing: BmTokens.s2,
              runSpacing: BmTokens.s2,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
              ],
            ),
          ),
          _ComponentDemo(
            label: 'IconButton',
            child: Row(
              children: [
                IconButton(
                  onPressed: () {},
                  tooltip: '播放',
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
                IconButton(
                  onPressed: () {},
                  tooltip: '收藏',
                  icon: const Icon(Icons.favorite_border_rounded),
                ),
                IconButton(
                  onPressed: null,
                  tooltip: '禁用',
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
          _ComponentDemo(
            label: 'Chip',
            child: Wrap(
              spacing: BmTokens.s2,
              runSpacing: BmTokens.s2,
              children: const [
                Chip(label: Text('192K HQ')),
                Chip(label: Text('无损')),
              ],
            ),
          ),
          _ComponentDemo(
            label: 'TextField',
            child: const TextField(
              decoration: InputDecoration(
                hintText: '搜索歌曲',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const _ComponentDemo(label: 'Switch', child: _DemoSwitch()),
          const _ComponentDemo(label: 'Slider', child: _DemoSlider()),
          _ComponentDemo(
            label: 'Divider',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '分组一',
                  style: type.label.copyWith(color: colors.textSecondary),
                ),
                const Divider(),
                Text(
                  '分组二',
                  style: type.label.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          _ComponentDemo(
            label: 'ListTile',
            width: BmTokens.s8 * 10,
            child: const ListTile(
              leading: Icon(Icons.music_note_rounded),
              title: Text('列表项标题'),
              subtitle: Text('ListTileTheme · 15 / 12'),
              trailing: Icon(Icons.chevron_right_rounded),
            ),
          ),
          _ComponentDemo(
            label: 'Card',
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(BmTokens.s3),
                child: Text(
                  'Card · surfaceRaised + r10',
                  style: type.body.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
          _ComponentDemo(
            label: 'Tooltip',
            child: Tooltip(
              message: 'Chrome 浮层：floating + hairline + r14',
              child: OutlinedButton(
                onPressed: () {},
                child: const Text('悬停查看 Tooltip'),
              ),
            ),
          ),
          _ComponentDemo(
            label: '对话框 / 底部单 / Toast',
            width: BmTokens.s8 * 12,
            child: Wrap(
              spacing: BmTokens.s2,
              runSpacing: BmTokens.s2,
              children: [
                OutlinedButton(
                  onPressed: () => _showDialog(context),
                  child: const Text('打开对话框'),
                ),
                OutlinedButton(
                  onPressed: () => _showSheet(context),
                  child: const Text('底部单'),
                ),
                OutlinedButton(
                  onPressed: () => _showToast(context),
                  child: const Text('Toast'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Theme(
          data: theme,
          child: AlertDialog(
            title: const Text('BmDialog'),
            content: const Text('20 圆角 / floating 底 / scrim 遮罩；按钮行右对齐。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Theme(
          data: theme,
          child: Builder(
            builder: (context) {
              final colors = context.bmColors;
              final type = context.bmType;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BmTokens.s5,
                    BmTokens.s2,
                    BmTokens.s5,
                    BmTokens.s5,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: BmTokens.s8 + BmTokens.s1,
                          height: BmTokens.s1,
                          decoration: BoxDecoration(
                            color: colors.textTertiary,
                            borderRadius: BmTokens.rPillAll,
                          ),
                        ),
                      ),
                      const SizedBox(height: BmTokens.s4),
                      Text(
                        'BmSheet',
                        style: type.headline.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: BmTokens.s1),
                      Text(
                        '顶部 20 圆角，拖拽关闭由后续里程碑接入。',
                        style: type.body.copyWith(color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showToast(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(const SnackBar(content: Text('BmToast：操作成功')));
  }
}

class _ComponentDemo extends StatelessWidget {
  const _ComponentDemo({
    required this.label,
    required this.child,
    this.width = BmTokens.s8 * 8,
  });

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return Container(
      width: width,
      padding: const EdgeInsets.all(BmTokens.s3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BmTokens.r14All,
        border: Border.all(color: colors.hairline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: type.micro.copyWith(color: colors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: BmTokens.s2),
          child,
        ],
      ),
    );
  }
}

class _DemoSwitch extends StatefulWidget {
  const _DemoSwitch();

  @override
  State<_DemoSwitch> createState() => _DemoSwitchState();
}

class _DemoSwitchState extends State<_DemoSwitch> {
  bool _value = true;

  @override
  Widget build(BuildContext context) {
    return Switch(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
    );
  }
}

class _DemoSlider extends StatefulWidget {
  const _DemoSlider();

  @override
  State<_DemoSlider> createState() => _DemoSliderState();
}

class _DemoSliderState extends State<_DemoSlider> {
  double _value = 0.4;

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
    );
  }
}

/// 色值展示：只做格式化，不参与取色。
String _hex(Color color) {
  final argb = color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  return '#$argb';
}

/// 去掉 token 数值的 `.0` 尾巴。
String _number(double value) => value.round().toString();

/// 展示排版规格：`15/22 · w400`。
String _typeSpec(TextStyle style) {
  final size = style.fontSize ?? 0;
  final lineHeight = (size * (style.height ?? 1)).round();
  return '${size.round()}/$lineHeight · w${style.fontWeight?.value ?? 400}';
}
