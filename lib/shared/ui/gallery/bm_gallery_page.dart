import 'package:flutter/material.dart';

import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/gallery/gallery_chrome_section.dart';
import 'package:bilimusic/shared/ui/gallery/gallery_motion_section.dart';
import 'package:bilimusic/shared/ui/gallery/gallery_overlay_section.dart';
import 'package:bilimusic/shared/ui/gallery/gallery_sections.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Lucent P0 验收入口：12 套「主题 × 亮度」组合的组件预览。
///
/// 组合只在本地 State 里切换，内部用 [Theme] 重新注入 [BmTokens] /
/// [BmColors] / `BmTypography`，不读写全局设置，也不依赖 Riverpod。
/// 入口是设置 → 关于应用的长按。
class BmGalleryPage extends StatefulWidget {
  const BmGalleryPage({super.key});

  @override
  State<BmGalleryPage> createState() => _BmGalleryPageState();
}

class _BmGalleryPageState extends State<BmGalleryPage> {
  int _themeIndex = 0;
  Brightness _brightness = Brightness.light;
  bool _reduceMotion = false;

  AppThemeDescriptor get _descriptor => ThemeRegistry.all[_themeIndex];

  ThemeData get _activeTheme =>
      _brightness == Brightness.dark ? _descriptor.dark() : _descriptor.light();

  @override
  Widget build(BuildContext context) {
    return Theme(
      key: const Key('bm-gallery'),
      data: _activeTheme,
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final label =
        '${_descriptor.label} · ${_brightness == Brightness.dark ? '深色' : '浅色'}';
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('Lucent Gallery'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BmTokens.s4),
            child: Center(
              child: Text(
                label,
                style: type.micro.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: _reduceMotion),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            BmTokens.s4,
            BmTokens.s4,
            BmTokens.s4,
            BmTokens.s8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSelector(context),
              const SizedBox(height: BmTokens.s4),
              const GalleryColorRolesSection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryMaterialTiersSection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryTypographySection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryGeometrySection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryComponentsSection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryMotionSection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryOverlaySection(),
              const SizedBox(height: BmTokens.s4),
              const GalleryChromeSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelector(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    return GallerySection(
      title: '主题 × 亮度',
      description:
          '6 套主题 × 明暗 2 档 = 12 套组合：每张卡片里的两块色板就是全部组合，'
          '点任意一块切换下方预览。',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'reduce motion',
            style: type.label.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(width: BmTokens.s2),
          Switch(
            key: const Key('bm-gallery-reduce-motion'),
            value: _reduceMotion,
            onChanged: (value) => setState(() => _reduceMotion = value),
          ),
        ],
      ),
      child: Wrap(
        spacing: BmTokens.s3,
        runSpacing: BmTokens.s3,
        children: [
          for (var index = 0; index < ThemeRegistry.all.length; index++)
            _ThemeComboCard(
              descriptor: ThemeRegistry.all[index],
              activeBrightness: index == _themeIndex ? _brightness : null,
              onSelected: (brightness) {
                setState(() {
                  _themeIndex = index;
                  _brightness = brightness;
                });
              },
            ),
        ],
      ),
    );
  }
}

/// 一张主题卡片：上半是该主题的名字，下半是浅色 / 深色两块可选色板。
class _ThemeComboCard extends StatelessWidget {
  const _ThemeComboCard({
    required this.descriptor,
    required this.activeBrightness,
    required this.onSelected,
  });

  final AppThemeDescriptor descriptor;

  /// null 表示该主题不是当前预览的主题。
  final Brightness? activeBrightness;
  final ValueChanged<Brightness> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final selected = activeBrightness != null;
    final subtitle = descriptor.subtitle;
    return Container(
      width: BmTokens.s8 * 8,
      padding: const EdgeInsets.all(BmTokens.s2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BmTokens.r14All,
        border: Border.all(
          color: selected ? colors.accent : colors.hairline,
          width: selected ? 2 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            descriptor.label,
            style: type.label.copyWith(color: colors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: type.micro.copyWith(color: colors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: BmTokens.s2),
          Row(
            children: [
              Expanded(
                child: _ThemeComboHalf(
                  key: ValueKey('combo-${descriptor.id}-light'),
                  descriptor: descriptor,
                  brightness: Brightness.light,
                  active: activeBrightness == Brightness.light,
                  onTap: () => onSelected(Brightness.light),
                ),
              ),
              const SizedBox(width: BmTokens.s2),
              Expanded(
                child: _ThemeComboHalf(
                  key: ValueKey('combo-${descriptor.id}-dark'),
                  descriptor: descriptor,
                  brightness: Brightness.dark,
                  active: activeBrightness == Brightness.dark,
                  onTap: () => onSelected(Brightness.dark),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单个「主题 × 亮度」色板；自己在 [Theme] 里渲染，12 块可以同屏对照。
class _ThemeComboHalf extends StatelessWidget {
  const _ThemeComboHalf({
    super.key,
    required this.descriptor,
    required this.brightness,
    required this.active,
    required this.onTap,
  });

  final AppThemeDescriptor descriptor;
  final Brightness brightness;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = brightness == Brightness.dark
        ? descriptor.dark()
        : descriptor.light();
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final colors = context.bmColors;
          final type = context.bmType;
          return Material(
            color: colors.bg,
            borderRadius: BmTokens.r10All,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(BmTokens.s2),
                decoration: BoxDecoration(
                  borderRadius: BmTokens.r10All,
                  border: Border.all(
                    color: active ? colors.accent : colors.hairline,
                    width: active ? 2 : 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: BmTokens.s2,
                          height: BmTokens.s2,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BmTokens.r4All,
                          ),
                        ),
                        const SizedBox(width: BmTokens.s1),
                        Text(
                          brightness == Brightness.dark ? '深色' : '浅色',
                          style: type.micro.copyWith(color: colors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: BmTokens.s2),
                    Container(
                      height: BmTokens.s5,
                      decoration: BoxDecoration(
                        color: colors.surfaceRaised,
                        borderRadius: BmTokens.r4All,
                        border: Border.all(color: colors.hairline, width: 0.5),
                      ),
                    ),
                    const SizedBox(height: BmTokens.s1),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: BmTokens.s1,
                            decoration: BoxDecoration(
                              color: colors.accentSoft,
                              borderRadius: BmTokens.rPillAll,
                            ),
                          ),
                        ),
                        const SizedBox(width: BmTokens.s1),
                        Container(
                          width: BmTokens.s3,
                          height: BmTokens.s1,
                          decoration: BoxDecoration(
                            color: colors.accentBorder,
                            borderRadius: BmTokens.rPillAll,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
