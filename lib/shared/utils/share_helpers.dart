import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bilimusic/domain/music.dart';

/// B 站短链根域 —— 分享文案 / 打开原网页共用同一份 URL 拼接逻辑。
String biliShortUrl(String bvid) => 'https://b23.tv/$bvid';

/// 分享一首歌 —— 统一分享文案与分享定位参数（详情页 / 长按菜单共用）。
void shareMusic(Music music) {
  final String shareText =
      '由 BiliMusic 分享：${music.title}\n'
      '${biliShortUrl(music.id)}';
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

/// 用系统浏览器打开歌曲对应的 B 站原网页（b23.tv/{bvid}）。
/// 与 [shareMusic] 共用短链构造，详情页「更多」与长按菜单共用入口。
void openOriginalPage(Music music) {
  final url = Uri.parse(biliShortUrl(music.id));
  launchUrl(url, mode: LaunchMode.externalApplication);
}
