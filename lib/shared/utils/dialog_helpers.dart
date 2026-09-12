import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

/// 详情页「更多」底部操作单骨架 —— 拖动条 + ListTile 列表（先关单再回调）。
/// [dense] 用于方屏紧凑样式（内边距 16、图标 22、字号 14），默认竖/横屏样式。
void showOptionsSheet(
  BuildContext context, {
  required List<SheetAction> actions,
  bool dense = false,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => Container(
      padding: EdgeInsets.symmetric(vertical: dense ? 16 : 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: dense ? 16 : 20),
          ...actions.map(
            (action) => ListTile(
              dense: dense,
              leading: Icon(
                action.icon,
                color: action.iconColor ?? Colors.white,
                size: dense ? 22 : null,
              ),
              title: _actionTitle(action, dense),
              onTap: () {
                Navigator.pop(sheetContext);
                action.onTap();
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// 条目标题：带实时标签时用 [ValueListenableBuilder] 跟随刷新，
/// 否则渲染静态 [SheetAction.label]。
Widget _actionTitle(SheetAction action, bool dense) {
  final style = TextStyle(color: Colors.white, fontSize: dense ? 14 : null);
  final listenable = action.labelListenable;
  if (listenable == null) {
    return Text(action.label!, style: style);
  }
  return ValueListenableBuilder<String>(
    valueListenable: listenable,
    builder: (context, value, _) => Text(value, style: style),
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
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.grey[900],
      title: const Text('歌曲信息', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          infoRow('标题', title),
          infoRow('艺术家', artist),
          infoRow('专辑', album),
          infoRow('时长', formatDuration(duration)),
          infoRow('来源', 'Bilibili'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Widget infoRow(
  String label,
  String value, {
  TextStyle? labelStyle,
  TextStyle? valueStyle,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 60, child: Text(label, style: labelStyle)),
        Expanded(
          child: Text(
            value,
            style: valueStyle ?? const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}
