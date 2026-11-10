import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/menu/bm_menu_row.dart';
import 'package:bilimusic/shared/ui/overlay/bm_overlays.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 底部操作单条目 —— icon/label/iconColor 由调用方解析好再传入。
class SheetAction {
  final IconData icon;

  /// 静态文案；提供 [labelListenable] 时不参与渲染。
  final String? label;

  /// 可选实时文案 listenable：提供时条目文案跟随其变化实时刷新
  /// （如定时关闭的剩余时间倒计时）。
  final ValueListenable<String>? labelListenable;

  final Color? iconColor;
  final VoidCallback onTap;

  const SheetAction({
    required this.icon,
    this.label,
    this.labelListenable,
    this.iconColor,
    required this.onTap,
  }) : assert(
         label != null || labelListenable != null,
         'label 与 labelListenable 至少提供一个',
       );
}

/// 详情页「更多」底部操作单 —— [BmMenuRow] 列表（先关单再回调）。
///
/// [dense] 用于方屏紧凑样式：行高 [BmTokens.rowCompact]、内边距更小；
/// 默认行高 [BmTokens.touchScreen]。
void showOptionsSheet(
  BuildContext context, {
  required List<SheetAction> actions,
  bool dense = false,
}) {
  showBmSheet<void>(
    context: context,
    builder: (sheetContext) => BmSheet(
      padding: EdgeInsets.symmetric(
        horizontal: BmTokens.s2,
        vertical: dense ? BmTokens.s2 : BmTokens.s4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            _actionRow(sheetContext, action, dense: dense),
        ],
      ),
    ),
  );
}

/// 一条操作：带 [SheetAction.labelListenable] 时跟随其刷新文案。
Widget _actionRow(
  BuildContext sheetContext,
  SheetAction action, {
  required bool dense,
}) {
  final leading = Icon(
    action.icon,
    size: BmTokens.icon,
    color: action.iconColor,
  );

  Widget row(String title) {
    return BmMenuRow(
      title: title,
      leading: leading,
      height: dense ? BmTokens.rowCompact : BmTokens.touchScreen,
      onTap: () {
        Navigator.of(sheetContext).pop();
        action.onTap();
      },
    );
  }

  final listenable = action.labelListenable;
  if (listenable == null) return row(action.label!);
  return ValueListenableBuilder<String>(
    valueListenable: listenable,
    builder: (_, value, _) => row(value),
  );
}

/// 「歌曲信息」弹窗 —— 标题/艺术家/专辑/时长/来源 五行，detail 三页共用。
void showSongInfoDialog(
  BuildContext context, {
  required String title,
  required String artist,
  required String album,
  required Duration duration,
}) {
  showBmDialog<void>(
    context: context,
    builder: (dialogContext) => BmDialog(
      title: '歌曲信息',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          infoRow('标题', title),
          infoRow('艺术家', artist),
          if (album.trim().isNotEmpty) infoRow('专辑', album),
          infoRow('时长', formatDuration(duration)),
          infoRow('来源', 'Bilibili'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 「标签 + 值」信息行；未指定样式时标签用次要色、值用主文字色。
Widget infoRow(
  String label,
  String value, {
  TextStyle? labelStyle,
  TextStyle? valueStyle,
}) {
  return Builder(
    builder: (context) {
      final colors = context.bmColors;
      final type = context.bmType;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: BmTokens.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text(
                label,
                style:
                    labelStyle ??
                    type.body.copyWith(color: colors.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style:
                    valueStyle ?? type.body.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      );
    },
  );
}
