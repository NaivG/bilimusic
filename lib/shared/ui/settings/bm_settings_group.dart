import 'package:flutter/material.dart';

import 'package:bilimusic/shared/motion/bm_pressable.dart';
import 'package:bilimusic/shared/ui/controls/bm_switch.dart';
import 'package:bilimusic/shared/ui/surfaces/bm_card.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

/// Theater 设置组：小号分组标题 + 白卡，行与行之间画从文字起点开始的
/// 0.5px 分隔线。
///
/// ```dart
/// BmSettingsGroup(
///   title: '通知',
///   children: [
///     BmSettingsSwitchRow(icon: Icons.notifications_none, title: '推送媒体通知', ...),
///   ],
/// )
/// ```
class BmSettingsGroup extends StatelessWidget {
  const BmSettingsGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });

  /// 分组标题；为 null 时不占位。
  final String? title;

  /// 分组脚注（说明文字）。
  final String? footer;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final titleText = title;
    final footerText = footer;
    return Padding(
      padding: const EdgeInsets.only(
        left: BmTokens.s4,
        right: BmTokens.s4,
        top: BmTokens.s5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titleText != null)
            Padding(
              padding: const EdgeInsets.only(
                left: BmTokens.s1,
                right: BmTokens.s1,
                bottom: BmTokens.s2 / 2,
              ),
              child: Text(
                titleText,
                style: type.label.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          BmCard(
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const _BmGroupDivider(),
                  children[i],
                ],
              ],
            ),
          ),
          if (footerText != null)
            Padding(
              padding: const EdgeInsets.only(
                top: BmTokens.s2,
                left: BmTokens.s2,
                right: BmTokens.s2,
              ),
              child: Text(
                footerText,
                style: type.caption.copyWith(color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// 从文字起点开始的分隔线。
class _BmGroupDivider extends StatelessWidget {
  const _BmGroupDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _BmSettingsRowMetrics.textInset),
      child: SizedBox(
        height: BmTokens.hairlineWidth,
        child: ColoredBox(color: context.bmColors.hairline),
      ),
    );
  }
}

/// 行内的几何常量。
abstract class _BmSettingsRowMetrics {
  /// 左右内边距。
  static const double inset = 14;

  /// 图标底座与文字之间的间距。
  static const double gap = 12;

  /// 文字起点（分隔线从这里开始）。
  static const double textInset = inset + BmTokens.iconTile + gap;
}

/// 设置行：图标底座 + 标题 / 描述 + 右侧内容。
class BmSettingsRow extends StatelessWidget {
  const BmSettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final String title;

  /// 图标；为 null 时不占底座。
  final IconData? icon;

  /// 描述文字（第二行）。
  final String? subtitle;

  /// 右侧内容（开关 / 数值 / 箭头）。
  final Widget? trailing;

  /// 为 null 时不可点击。
  final VoidCallback? onTap;

  /// 危险项：标题与图标走 [BmColors.danger]。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final iconData = icon;
    final subtitleText = subtitle;
    final titleColor = danger ? colors.danger : colors.textPrimary;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _BmSettingsRowMetrics.inset,
        vertical: BmTokens.s2,
      ),
      child: Row(
        children: [
          if (iconData != null) ...[
            _BmSettingsIconTile(icon: iconData, danger: danger),
            const SizedBox(width: _BmSettingsRowMetrics.gap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: type.bodyStrong.copyWith(color: titleColor)),
                if (subtitleText != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitleText,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: BmTokens.s2),
            trailing!,
          ],
        ],
      ),
    );

    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: BmTokens.settingRow),
      child: Center(child: row),
    );

    if (onTap == null) return body;
    return BmPressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: body,
    );
  }
}

/// 开关行。
class BmSettingsSwitchRow extends StatelessWidget {
  const BmSettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return BmSettingsRow(
      title: title,
      icon: icon,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: BmSwitch(
        value: value,
        onChanged: onChanged,
        semanticLabel: title,
      ),
    );
  }
}

/// 数值 / 跳转行：标题 + 右侧数值 + chevron。
class BmSettingsValueRow extends StatelessWidget {
  const BmSettingsValueRow({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.value,
    this.onTap,
    this.danger = false,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final valueText = value;
    return BmSettingsRow(
      title: title,
      icon: icon,
      subtitle: subtitle,
      danger: danger,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (valueText != null)
            Text(
              valueText,
              style: BmTypography.numeric(
                type.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          const SizedBox(width: BmTokens.s1),
          Icon(
            Icons.chevron_right_rounded,
            size: BmTokens.iconMenu,
            color: colors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// 滑块行：标题行 + 下方整条滑块。
class BmSettingsSliderRow extends StatelessWidget {
  const BmSettingsSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.icon,
    this.valueLabel,
    this.divisions,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final IconData? icon;

  /// 右侧展示的当前值文案；为 null 时不显示。
  final String? valueLabel;

  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    final type = context.bmType;
    final iconData = icon;
    final label = valueLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _BmSettingsRowMetrics.inset,
        BmTokens.s2 + 1,
        _BmSettingsRowMetrics.inset,
        BmTokens.s3 - 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (iconData != null) ...[
                _BmSettingsIconTile(icon: iconData),
                const SizedBox(width: _BmSettingsRowMetrics.gap),
              ],
              Expanded(
                child: Text(
                  title,
                  style: type.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              if (label != null)
                Text(
                  label,
                  style: BmTypography.numeric(
                    type.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: BmTokens.s2),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: BmTokens.s1 / 2,
              activeTrackColor: colors.accent,
              inactiveTrackColor: colors.lineStrong,
              thumbColor: colors.surfaceRaised,
              overlayColor: colors.accentSoft,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 32 × 32 图标底座（`accentSoft` 底 + `accentDeep` 图标）。
class _BmSettingsIconTile extends StatelessWidget {
  const _BmSettingsIconTile({required this.icon, this.danger = false});

  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.bmColors;
    return Container(
      width: BmTokens.iconTile,
      height: BmTokens.iconTile,
      decoration: BoxDecoration(
        color: danger
            ? colors.danger.withValues(alpha: BmAlpha.selected)
            : colors.accentSoft,
        borderRadius: BmTokens.iconTileRadius,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: BmTokens.iconTileGlyph,
        color: danger ? colors.danger : colors.accentDeep,
      ),
    );
  }
}
