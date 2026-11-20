import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lyrics/lyric_progress_source.dart';
import 'package:bilimusic/features/lyrics/widgets/lyric_section.dart';
import 'package:bilimusic/features/player/models/player_state.dart';

/// 歌词版式 / 动效回归。
void main() {
  Future<({LyricPreset preset, LyricController controller})> pumpLyric(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final controller = LyricController()
      ..loadDocument(
        LyricDocument(
          offset: const Duration(milliseconds: 500),
          lines: [
            LyricLine(
              start: const Duration(seconds: 1),
              end: const Duration(seconds: 4),
              text: 'Dance, dance with me, dance',
              translation: '你是我能感受到的光',
            ),
            LyricLine(
              start: const Duration(seconds: 4),
              end: const Duration(seconds: 8),
              text: "You're the light I feel",
            ),
          ],
        ),
      );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricSection(lyricController: controller, onLyricTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    final preset = tester.widget<LyricView>(find.byType(LyricView)).preset!;
    return (preset: preset, controller: controller);
  }

  testWidgets('竖屏：Apple Music 预设 + 逐字上弹悬浮 + 倒计时圆点', (tester) async {
    final result = await pumpLyric(tester, const Size(393, 852));
    final preset = result.preset;

    // 固定折行：切句不改折行，才托得住 AM 的行运动。
    expect(preset.layoutMode, LyricLayoutMode.fixed);
    expect(preset.textAlign, TextAlign.start);
    expect(preset.contentAlignment, LyricContentAlignment.start);
    expect(preset.textStyle.fontSize, 32);
    expect(preset.translationTextStyle.fontSize, 16);
    // 外层页面已有横向 padding，预设里不能再叠一层。
    expect(preset.padding, EdgeInsets.zero);
    expect(preset.lineSpacing, 32 * 0.85);

    // 本次迁移的核心：AM 切句轨迹。
    expect(preset.lineTransition, LyricLineTransitions.appleMusic);
    // 行错位 + 波浪，逐字上弹 + 悬浮。
    expect(preset.lineMotion.waveAmplitude, 12);
    expect(preset.lineMotion.maxDelay, const Duration(milliseconds: 140));
    expect(preset.wordEffects.lift, 2.5);
    expect(preset.wordEffects.floatAmplitude, 1.4);
    expect(preset.wordEffects.simulateTiming, isTrue);
    // 距离模糊 + 前奏/间奏圆点。
    expect(preset.distanceBlur.maxSigma, 4);
    expect(preset.distanceBlur.whenBrowsing, isFalse);
    expect(preset.countdown.enabled, isTrue);
    // 高亮换成纯白逐字填充（带尾部渐隐）。
    expect(preset.highlight.tailFadeWidth, 20);
    expect(preset.highlight.color, Colors.white);
  });

  testWidgets('横屏：大字号双档保留，切句同样走 AM 轨迹', (tester) async {
    final result = await pumpLyric(tester, const Size(1280, 800));
    final preset = result.preset;

    expect(preset.textStyle.fontSize, 34);
    expect(preset.activeTextStyle.fontSize, 40);
    expect(preset.lineSpacing, 32);
    expect(preset.translationSpacing, 10);
    expect(preset.lineTransition, LyricLineTransitions.appleMusic);
    expect(preset.lineMotion.waveAmplitude, 12);
    expect(preset.wordEffects.lift, 2.5);
    // 横屏歌词区高度有限，56px 的圆点行会把行距压掉，保持关闭。
    expect(preset.countdown.enabled, isFalse);
  });

  testWidgets('方屏：保持紧凑居中，不套用 AM 大字与行运动', (tester) async {
    final result = await pumpLyric(tester, const Size(320, 320));
    final preset = result.preset;

    expect(preset.textAlign, TextAlign.center);
    expect(preset.textStyle.fontSize, lessThan(20));
    expect(preset.lineTransition, isNot(LyricLineTransitions.appleMusic));
    expect(preset.lineMotion.waveAmplitude, 0);
    expect(preset.wordEffects.lift, 0);
    expect(preset.countdown.enabled, isFalse);
  });

  testWidgets('点击回调转发的是已扣偏移的 seekPosition', (tester) async {
    Duration? tapped;
    final controller = LyricController();
    addTearDown(controller.dispose);
    controller.loadDocument(
      LyricDocument(
        offset: const Duration(milliseconds: 500),
        lines: [LyricLine(start: const Duration(seconds: 5), text: '第一句')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricSection(
            lyricController: controller,
            onLyricTap: (position) => tapped = position,
          ),
        ),
      ),
    );
    await tester.pump();

    final view = tester.widget<LyricView>(find.byType(LyricView));
    view.onLineTap!(
      LyricLineDetails(
        viewId: 'view',
        index: 0,
        line: controller.document!.lines.first,
        // 4.x 已经在 details 里扣掉文档 offset 与用户校准偏移。
        seekPosition: const Duration(seconds: 4, milliseconds: 500),
      ),
    );

    expect(tapped, const Duration(seconds: 4, milliseconds: 500));
  });

  testWidgets('没有文档时显示空态而不是 LyricView', (tester) async {
    final controller = LyricController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricSection(lyricController: controller, onLyricTap: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LyricView), findsNothing);
    expect(find.text('暂无歌词'), findsOneWidget);
  });

  testWidgets('重复 build 的预设值相等：不会每帧重置布局与动画', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    final controller = LyricController()
      ..loadDocument(
        LyricDocument(
          lines: [LyricLine(start: Duration.zero, text: '一句')],
        ),
      );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 父级真的重建（不是 pump 同一棵树）：合成器每 200ms 会重建详情页，
    // 而 LyricViewSession 靠 preset 值相等来早退，不等就会每帧重排。
    final tick = ValueNotifier(0);
    addTearDown(tick.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: tick,
            builder: (context, _) =>
                LyricSection(lyricController: controller, onLyricTap: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    final first = tester.widget<LyricView>(find.byType(LyricView)).preset;

    tick.value++;
    await tester.pump();
    final second = tester.widget<LyricView>(find.byType(LyricView)).preset;

    expect(identical(first, second), isFalse, reason: '这是两次不同的构建');
    expect(first, equals(second), reason: '值相等才能让 configure 早退');
  });

  testWidgets('进度源驱动 controller：位置前进后激活行随之切换', (tester) async {
    final ticks = ValueNotifier(Duration.zero);
    final playerState = ValueNotifier<PlayerState>(const PlayerPlaying());
    var raw = Duration.zero;
    final source = PlayerLyricProgressSource(
      positionTicks: ticks,
      playerState: playerState,
      readPosition: () => raw,
    );
    final controller = LyricController(progressSource: source)
      ..loadDocument(
        LyricDocument(
          lines: [
            LyricLine(
              start: Duration.zero,
              end: const Duration(seconds: 4),
              text: '第一句',
            ),
            LyricLine(
              start: const Duration(seconds: 4),
              end: const Duration(seconds: 8),
              text: '第二句',
            ),
          ],
        ),
      );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      source.dispose();
      ticks.dispose();
      playerState.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: LyricView(
              controller: controller,
              preset: LyricPresets.appleMusic.copyWith(
                countdown: const LyricCountdown.none(),
              ),
            ),
          ),
        ),
      ),
    );
    // 有界 pump：Word Pop / Character Float 会持续重绘，不能 pumpAndSettle。
    await tester.pump(const Duration(milliseconds: 16));

    raw = const Duration(seconds: 5);
    ticks.value = raw; // 事件源通知一次，controller 立刻采样
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.activeLineIndex, 1);
    expect(controller.effectivePosition, const Duration(seconds: 5));

    raw = const Duration(seconds: 1);
    ticks.value = raw;
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.activeLineIndex, 0, reason: '暂停/回退后也要能跟上');
  });
}
