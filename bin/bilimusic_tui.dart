import 'dart:io';

import 'package:dart_tui/dart_tui.dart';

import 'tui/app_model.dart';
import 'tui/probe.dart';
import 'tui/tui_api.dart';

/// bilimusic 终端客户端。
///
/// 运行:
///   dart run bin/bilimusic_tui.dart            # 交互 TUI
///   dart run bin/bilimusic_tui.dart --probe    # 无终端的分层自检
///   dart run bin/bilimusic_tui.dart --smoke    # 无终端驱动完整 MUV 循环
///   dart run bin/bilimusic_tui.dart --preview  # 静态设计预览(假数据,无网络无声)
///
/// 界面:主页(搜索框 + 官方推荐,回车搜索 / tab 浏览推荐)与搜索结果页
/// (搜索框 + 结果列表,esc 回主页)两个页面。两页共用播放队列。
Future<void> main(List<String> args) async {
  if (args.contains('--probe')) {
    await runProbe();
    return;
  }
  if (args.contains('--smoke')) {
    await runSmoke();
    return;
  }
  if (args.contains('--preview')) {
    stdout.writeln('── 主页 · 空态(加载中) · 100×26 ${'─' * 15}');
    stdout.writeln(AppModel.previewHomeEmpty(width: 100, height: 26));
    stdout.writeln('── 主页 · 官方推荐 · 100×26 ${'─' * 15}');
    stdout.writeln(AppModel.previewHome(width: 100, height: 26));
    stdout.writeln('── 主页 · 80×24(窄窗) ${'─' * 20}');
    stdout.writeln(AppModel.previewHome(width: 80, height: 24));
    stdout.writeln('── 搜索页 · 结果 · 80×24(窄窗) ${'─' * 13}');
    stdout.writeln(AppModel.previewSearch(width: 80, height: 24));
    return;
  }

  final api = TuiApi();
  await api.init();

  final model = AppModel(api: api);
  await Program(
    options: [
      withAltScreen(),
      withCellRenderer(),
      // 驱动 spinner(忙碌时)与 mpv 状态轮询(每 3 帧)
      withTickInterval(const Duration(milliseconds: 120)),
      withMouseCellMotion(), // 滚轮移动列表游标 / 点击选中
    ],
  ).run(model);

  model.mpv.dispose();
  api.close();
}
