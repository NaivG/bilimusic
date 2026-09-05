import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bilimusic/domain/music.dart';

/// 分享一首歌 —— 统一分享文案与分享定位参数（详情页 / 长按菜单共用）。
void shareMusic(Music music) {
  final String shareText =
      '由 BiliMusic 分享：${music.title}\n'
      'https://b23.tv/${music.id}';
  SharePlus.instance.share(
    ShareParams(
      text: shareText,
      sharePositionOrigin: Rect.fromCenter(
        center: Offset.zero,
        width: 100,
        height: 100,
      ),
    ),
  );
}
