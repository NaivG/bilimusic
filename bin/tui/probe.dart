import 'dart:io';

import 'package:bilimusic/domain/music.dart';
import 'package:dart_tui/dart_tui.dart';

import 'app_model.dart';
import 'mpv_player.dart';
import 'tui_api.dart';

/// 无终端环境的分层自检:网络装配 → 推荐 → 搜索 → 取流 → libmpv 解码。
/// 用于验证"复用 App 逻辑 + FFI 播放"这条链路,TTY 交互部分需人工验证。
Future<void> runProbe() async {
  final api = TuiApi();
  await api.init();
  stdout.writeln(
    '[1] 网络装配 OK · cookie: ${api.hasLoginCookies ? "已从 App 导入登录态" : "无(未登录)"}',
  );

  stdout.writeln('[2] 拉取官方推荐(音乐分区)…');
  final recs = await api.recommendations();
  stdout.writeln('    ${recs.length} 条推荐');
  for (final r in recs.take(3)) {
    stdout.writeln('    - ${r.title} | ${r.subtitle}');
  }
  if (recs.isEmpty) {
    stderr.writeln('probe 停止:官方推荐为空(检查网络/cookie/风控)');
    exitCode = 1;
    return;
  }
  // 推荐卡自带 cid,取流应免掉 view API 补全
  final recMusic = await api.resolveAudio(recs.first);
  stdout.writeln(
    '    → 直取流 OK:${recMusic.id} cid=${recMusic.cid} '
    'url=${recMusic.audioUrl.substring(0, recMusic.audioUrl.length > 60 ? 60 : recMusic.audioUrl.length)}…',
  );

  const query = '晴天';
  stdout.writeln('[3] 搜索「$query」…');
  final (results, page, numPages) = await api.search(query);
  stdout.writeln('    第 $page/$numPages 页 · ${results.length} 条视频结果');
  for (final r in results.take(5)) {
    stdout.writeln('    - ${r.title} | ${r.subtitle}');
  }
  if (results.isEmpty) {
    stderr.writeln('probe 停止:搜索无结果(检查网络/cookie/风控)');
    exitCode = 1;
    return;
  }

  final target = results.first;
  stdout.writeln('[4] 解析音频流:${target.title}');
  final Music music;
  try {
    music = await api.resolveAudio(target);
  } catch (e) {
    stderr.writeln('probe 停止:取流失败 $e');
    exitCode = 1;
    return;
  }
  final url = music.audioUrl;
  stdout.writeln(
    '    bvid=${music.id} cid=${music.cid} url=${url.substring(0, url.length > 60 ? 60 : url.length)}…',
  );

  stdout.writeln('[5] 加载 libmpv(headless,ao=null 静音解码 5 秒)…');
  final mpv = MpvPlayer();
  try {
    mpv.load(nullAudio: true);
  } catch (e) {
    stderr.writeln('probe 停止:$e');
    exitCode = 1;
    return;
  }
  mpv.play(music.audioUrl);
  await Future<void>.delayed(const Duration(seconds: 5));
  final st = mpv.pollState();
  mpv.dispose();
  stdout.writeln(
    '    position=${st.position.toStringAsFixed(1)}s / '
    'duration=${st.duration.toStringAsFixed(1)}s · ended=${st.ended}',
  );

  if (st.position > 1) {
    stdout.writeln(
      '[✓] probe 通过:API 复用层、推荐、取流、libmpv FFI 均可用。'
      '交互 TUI 请在真实终端运行 dart run bin/bilimusic_tui.dart 人工验证。',
    );
  } else {
    stderr.writeln('[✗] probe 未推进:音频流未开始解码(检查网络/URL 有效期)');
    exitCode = 1;
  }
}

/// 无终端驱动完整 MUV 循环:init 加载官方推荐 → 主页渲染 → 模拟粘贴 → 回车搜索
/// → 结果页渲染 → enter 播放 → 轮询 → esc 回主页。
/// 验证 AppModel 的 update/view 键路逻辑、双页布局(搜索/状态/内容/播放)
/// 与 80 列窄窗下的溢出守卫。
Future<void> runSmoke() async {
  final api = TuiApi();
  await api.init();
  final model = AppModel(api: api);

  // init:加载 mpv + 拉取官方推荐;再给定 80×24 窄窗几何(触发自适应行数)
  final initMsg = await model.init()?.call();
  model.update(WindowSizeMsg(80, 24));
  if (initMsg is RecsDoneMsg) model.update(initMsg);

  String render() => model.view().content;

  String statusOf(String view) {
    final lines = view.split('\n');
    // 行序:0 标题 → 1-3 搜索面板 → 4 状态行
    return lines.length > 4 ? lines[4].trim() : '(状态行缺失)';
  }

  // 模拟粘贴:bracketed paste 由框架解码为 PasteMsg;
  // 尾部换行是复制杂质,应被丢弃而不是触发回车搜索
  String inputText(String view) {
    final line = stripAnsi(view.split('\n')[2]);
    return line.replaceAll(RegExp(r'^[│╭╰─\s]+|[│╭╰╯─\s]+$'), '');
  }

  // [1] 主页:官方推荐已渲染
  final home = render();
  if (!home.contains('官方推荐')) {
    stderr.writeln('[✗] smoke 失败:主页未渲染官方推荐面板');
    exitCode = 1;
    return;
  }
  if (!RegExp(r'\d+\. ').hasMatch(stripAnsi(home))) {
    stderr.writeln('[✗] smoke 失败:推荐列表缺少序号');
    exitCode = 1;
    return;
  }
  stdout.writeln('[1] 官方推荐→主页渲染 OK · 状态:「${statusOf(home)}」');

  model.update(PasteMsg('晴天 MV\n'));
  final pasted = inputText(render());
  if (pasted != '晴天 MV') {
    stderr.writeln('[✗] smoke 失败:粘贴未正确落入输入框(得到「$pasted」)');
    exitCode = 1;
    return;
  }
  // 退格 3 次修掉「 MV」,保留键路覆盖
  for (var i = 0; i < 3; i++) {
    model.update(KeyPressMsg(TeaKey(code: KeyCode.backspace)));
  }
  final trimmed = inputText(render());
  if (trimmed != '晴天') {
    stderr.writeln('[✗] smoke 失败:退格修剪后输入框为「$trimmed」');
    exitCode = 1;
    return;
  }
  stdout.writeln('[2] 粘贴→修剪 OK · 输入框:「$trimmed」');

  // 回车搜索(主页 → 结果页)
  final (Model _, searchCmd) = model.update(
    KeyPressMsg(TeaKey(code: KeyCode.enter)),
  );
  stdout.writeln('[3] 回车 OK · 状态:「${statusOf(render())}」');
  final msg1 = await searchCmd?.call();
  if (msg1 is! SearchDoneMsg) {
    stderr.writeln('[✗] smoke 失败:搜索命令未返回 SearchDoneMsg');
    exitCode = 1;
    return;
  }
  model.update(msg1);
  final rendered = render();
  if (!rendered.contains('结果') || !rendered.contains('晴天')) {
    stderr.writeln('[✗] smoke 失败:结果页未渲染出结果');
    exitCode = 1;
    return;
  }
  if (!RegExp(r'\d+\. ').hasMatch(stripAnsi(rendered))) {
    stderr.writeln('[✗] smoke 失败:结果列表缺少序号');
    exitCode = 1;
    return;
  }
  stdout.writeln('[4] 搜索→结果页渲染 OK · 状态:「${statusOf(rendered)}」');

  // 列表焦点下 enter → 解析 → 播放
  final (Model _, playCmd) = model.update(
    KeyPressMsg(TeaKey(code: KeyCode.enter)),
  );
  final msg2 = await playCmd?.call();
  if (msg2 is ResolvedMsg) {
    model.update(msg2);
  } else {
    stderr.writeln('[✗] smoke 失败:解析命令未返回 ResolvedMsg($msg2)');
    exitCode = 1;
    return;
  }

  // 等 3 秒真实出声,然后走 3 帧 tick(每 3 帧轮询一次 mpv)
  await Future<void>.delayed(const Duration(seconds: 3));
  for (var i = 0; i < 3; i++) {
    model.update(TickMsg(DateTime.now()));
  }
  final body = render();
  mpvDispose(model);

  final times = RegExp(r'\d+:\d+').allMatches(stripAnsi(body)).toList();
  if (times.length < 2) {
    stderr.writeln('[✗] smoke 失败:播放面板未渲染出 进度/时长');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    '[5] 解析→播放→轮询 OK · 进度:${times.first.group(0)} / ${times[1].group(0)}',
  );

  // 结果页 esc 回主页:第一下焦点回搜索框,第二下退到主页
  model.update(KeyPressMsg(TeaKey(code: KeyCode.escape)));
  model.update(KeyPressMsg(TeaKey(code: KeyCode.escape)));
  final backHome = render();
  if (!backHome.contains('官方推荐')) {
    stderr.writeln('[✗] smoke 失败:esc 未从结果页返回主页');
    exitCode = 1;
    return;
  }
  stdout.writeln('[6] esc 结果页→主页 OK');

  // 布局守卫:80 列窗口下不允许任何一行溢出
  final maxW = backHome
      .split('\n')
      .map(getWidth)
      .fold(0, (a, b) => a > b ? a : b);
  if (maxW > 80) {
    stderr.writeln('[✗] smoke 失败:最宽行 $maxW 列,溢出 80 列终端');
    exitCode = 1;
    return;
  }
  stdout.writeln('[7] 80 列布局守卫 OK · 最宽行 $maxW 列');
  stdout.writeln('[✓] smoke 通过:双页 + 官方推荐 + MUV 键路 + 真实播放全通。');
}

void mpvDispose(AppModel model) => model.mpv.dispose();
