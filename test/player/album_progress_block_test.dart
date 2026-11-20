import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/models/player_state.dart';
import 'package:bilimusic/features/player/now_playing/album_section.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/player/widgets/album_progress_bar.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/stage/bm_audio_quality_badge.dart';
import 'package:bilimusic/shared/utils/formatters.dart';

/// 详情页进度区块契约：
/// - 读数行 = 左「已播」/ 中「音质徽标」/ 右「总时长」，全部走 [formatDuration]；
/// - crossfade 时中心位切「过渡中」，但进度块高度与轨道位置不变（不跳行）；
/// - 320 窄宽下三处读数互不重叠、不触发 RenderFlex 溢出；
/// - 手势的 tap / drag / cancel 状态干净：预览不提交，取消不 seek。

const Duration _duration = Duration(minutes: 4, seconds: 12);
const Duration _position = Duration(minutes: 1, seconds: 26);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AlbumSection 进度块读数行', () {
    for (final size in <Size>[const Size(320, 700), const Size(390, 844)]) {
      testWidgets('${size.width.toInt()} 宽：已播 / 音质 / 总时长三处读数都在', (
        tester,
      ) async {
        await _pumpSection(tester, size: size);

        expect(find.text(formatDuration(_position)), findsOneWidget);
        expect(find.text(formatDuration(_duration)), findsOneWidget);
        expect(find.text('192K HQ'), findsOneWidget);

        final track = _trackRect(tester);
        expect(
          tester.getRect(find.text(formatDuration(_position))).top,
          greaterThan(track.bottom),
          reason: '读数行必须在轨道下方，不能再画回轨道两端',
        );

        // 三处读数不越出进度块左右边界。
        final block = tester.getRect(find.byType(AlbumProgressBar));
        final readout = tester.getRect(find.text(formatDuration(_position)));
        final total = tester.getRect(find.text(formatDuration(_duration)));
        expect(readout.left, greaterThanOrEqualTo(block.left - 0.5));
        expect(total.right, lessThanOrEqualTo(block.right + 0.5));

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('320 窄宽：左右读数与中心徽标互不重叠', (tester) async {
      await _pumpSection(tester, size: const Size(320, 700));

      final readout = tester.getRect(find.text(formatDuration(_position)));
      // 用徽标胶囊（含 8px 内边距 + ALAC 标志）而不是内部文字做重叠判定。
      final center = tester.getRect(find.byType(BmAudioQualityBadge));
      final total = tester.getRect(find.text(formatDuration(_duration)));

      expect(
        readout.right,
        lessThanOrEqualTo(center.left),
        reason: '左侧读数不能压到中心音质徽标',
      );
      expect(
        center.right,
        lessThanOrEqualTo(total.left),
        reason: '中心音质徽标不能压到右侧总时长',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('crossfade：中心切「过渡中」，轨道与进度块高度不动', (tester) async {
      final harness = await _pumpSection(tester, size: const Size(390, 844));

      final trackBefore = _trackRect(tester);
      final blockBefore = tester.getRect(find.byType(AlbumProgressBar));
      final badgeCenterBefore = tester.getCenter(find.text('192K HQ'));
      final readoutTopBefore = tester
          .getRect(find.text(formatDuration(_position)))
          .top;

      harness.audio.playerState.value = const PlayerPlaying(fadeCountdown: 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('过渡中'), findsOneWidget);
      expect(find.text('192K HQ'), findsNothing, reason: '过渡中不应再显示上一档徽标');

      final trackAfter = _trackRect(tester);
      final blockAfter = tester.getRect(find.byType(AlbumProgressBar));
      expect(trackAfter.top, trackBefore.top, reason: '徽标换「过渡中」时轨道不能上下跳');
      expect(blockAfter.height, blockBefore.height, reason: '进度块高度必须恒定');
      expect(
        tester.getRect(find.text(formatDuration(_position))).top,
        readoutTopBefore,
        reason: '读数行不能随徽标高度变化',
      );

      // 「过渡中」比徽标胶囊矮，但中心位按胶囊占位，两者垂直中心一致。
      final indicatorCenter = tester.getCenter(find.text('过渡中'));
      expect(indicatorCenter.dy, closeTo(badgeCenterBefore.dy, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('极端高度：矮走滚动模式、高走填充模式，均不溢出', (tester) async {
      // 320x420：内容放不下 → 滚动容器。
      await _pumpSection(tester, size: const Size(320, 420));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text(formatDuration(_duration)), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 390x1200：远高于内容 → 填充模式，富余高度只落在弹性间距里。
      await _pumpSection(tester, size: const Size(390, 1200));
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text(formatDuration(_duration)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('滚动模式：纵向拖动轨道不 seek，滚动容器接管后预览取消', (tester) async {
      // 用 360 高：滚动余量足够验证「手势被滚动容器消费」，同时进度块已在视口内。
      final harness = await _pumpSection(tester, size: const Size(320, 360));
      expect(find.byType(SingleChildScrollView), findsOneWidget);

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offsetBefore = scrollable.position.pixels;
      final track = _trackRect(tester);
      expect(track.bottom, lessThan(360), reason: '进度块应在视口内，手势才打得到轨道');
      final gesture = await tester.startGesture(track.center);
      // 超过 kPressTimeout：onTapDown 先给出点按预览。
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text(formatDuration(_position)), findsNothing);

      // 纵向拖动被滚动容器接管：第一段只越过 slop，第二段才是真实位移。
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        scrollable.position.pixels,
        greaterThan(offsetBefore),
        reason: '纵向手势应由 SingleChildScrollView 消费',
      );
      expect(harness.commands.seeks, isEmpty, reason: '纵向滚动不能触发 seek');
      expect(find.text(formatDuration(_position)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AlbumProgressBar 手势与边界', () {
    testWidgets('点按轨道：按比例预览并提交 seek', (tester) async {
      final harness = await _pumpBar(tester);

      await tester.tapAt(_trackRect(tester).center);
      await tester.pump();

      expect(harness.commands.seeks, hasLength(1));
      expect(
        harness.commands.seeks.single.inMilliseconds,
        closeTo(_duration.inMilliseconds / 2, 2),
        reason: '点按轨道中点应 seek 到总时长的一半',
      );
      // 提交后读数回到真实播放进度。
      expect(find.text(formatDuration(_position)), findsOneWidget);
      expect(find.text(formatDuration(_duration)), findsOneWidget);
    });

    testWidgets('拖动：左侧读数跟随手指，总时长保持不变，松手提交', (tester) async {
      final harness = await _pumpBar(tester);
      final track = _trackRect(tester);
      final start = Offset(track.left + track.width * 0.25, track.center.dy);

      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(
        find.text(formatDuration(_position)),
        findsNothing,
        reason: '拖动中左侧读数应跟随手指，而不是真实播放进度',
      );
      expect(find.text(formatDuration(_duration)), findsOneWidget);

      final firstX = start.dx + 40;
      final firstExpected = _expectedMs(track, firstX);
      expect(
        find.text(formatDuration(Duration(milliseconds: firstExpected))),
        findsOneWidget,
        reason: '读数按手指位置换算',
      );

      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      final secondExpected = _expectedMs(track, start.dx + 120);
      expect(
        find.text(formatDuration(Duration(milliseconds: secondExpected))),
        findsOneWidget,
        reason: '继续拖动时读数继续跟随',
      );
      expect(find.text(formatDuration(_duration)), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(harness.commands.seeks, hasLength(1));
      expect(
        harness.commands.seeks.single.inMilliseconds,
        closeTo(secondExpected, 2),
      );
      expect(find.text(formatDuration(_position)), findsOneWidget);
    });

    testWidgets('取消点按预览：不提交 seek，读数回到真实进度', (tester) async {
      final harness = await _pumpBar(tester);
      final track = _trackRect(tester);
      final start = Offset(track.left + track.width * 0.25, track.center.dy);

      final gesture = await tester.startGesture(start);
      // 超过 kPressTimeout（100ms）后 onTapDown 先给出预览；此时尚未 up，
      // 若指针被取消（例如滚动容器/其他手势抢走），必须清掉预览而不是 seek。
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text(formatDuration(_position)), findsNothing);

      await gesture.cancel();
      await tester.pump();

      expect(harness.commands.seeks, isEmpty, reason: '取消手势不能 seek');
      expect(find.text(formatDuration(_position)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('duration 为 0：读数 00:00，点按不 seek', (tester) async {
      final harness = await _pumpBar(tester, duration: Duration.zero);

      expect(
        find.text(formatDuration(Duration.zero)),
        findsNWidgets(2),
        reason: '左右两侧读数都回退到 00:00',
      );

      await tester.tapAt(_trackRect(tester).center);
      await tester.pump();
      expect(harness.commands.seeks, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('position 超过 duration：比例夹在 0..1，读数取总时长', (tester) async {
      final harness = await _pumpBar(tester);

      harness.audio.position.value = const Duration(minutes: 10);
      await tester.pump();

      expect(find.text(formatDuration(_duration)), findsNWidgets(2));
      final fraction = tester.widget<FractionallySizedBox>(
        find.descendant(
          of: find.byType(AlbumProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(fraction.widthFactor, 1.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('正常进度：比例取 position / duration', (tester) async {
      await _pumpBar(tester);

      final fraction = tester.widget<FractionallySizedBox>(
        find.descendant(
          of: find.byType(AlbumProgressBar),
          matching: find.byType(FractionallySizedBox),
        ),
      );
      expect(
        fraction.widthFactor,
        closeTo(_position.inMilliseconds / _duration.inMilliseconds, 0.001),
      );
    });
  });
}

/// 拖动后的目标毫秒：与组件内「指针 x / 轨道宽」的换算一致。
int _expectedMs(Rect track, double x) {
  final fraction = ((x - track.left) / track.width).clamp(0.0, 1.0);
  return (fraction * _duration.inMilliseconds).round();
}

Rect _trackRect(WidgetTester tester) {
  return tester.getRect(
    find.descendant(
      of: find.byType(AlbumProgressBar),
      matching: find.byType(GestureDetector),
    ),
  );
}

/// 渲染真实的 [AlbumSection]：封面 / 信息行 / 进度块 / 控制行全套。
Future<_Harness> _pumpSection(
  WidgetTester tester, {
  required Size size,
  PlayerState state = const PlayerPlaying(),
  String qualityId = '30280',
}) async {
  _applyViewSize(tester, size);
  final audio = _StubDualAudioService(
    state: state,
    position: _position,
    qualityId: qualityId,
  );
  final commands = _RecordingCommands();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dualAudioServiceProvider.overrideWithValue(audio),
        playbackCommandsProvider.overrideWith(() => commands),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeRegistry.defaultTheme.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: AlbumSection(
              coverUrl: '',
              title: '夜航中的城市灯火与你温柔而漫长的告白',
              artist: '不才',
              album: '夜航星 · Single',
              duration: _duration,
              trackId: 'BV1TEST',
              isPlaying: true,
              playModeIcon: Icons.repeat_rounded,
              onPlayPause: () {},
              onPrevious: () {},
              onNext: () {},
              onPlayModeToggle: () {},
              onPlaylist: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await _settleEntrance(tester);
  return _Harness(audio: audio, commands: commands);
}

/// 单独渲染进度区块，用于手势断言（不经过 AlbumSection 的布局与动画）。
Future<_Harness> _pumpBar(
  WidgetTester tester, {
  Duration duration = _duration,
}) async {
  _applyViewSize(tester, const Size(390, 260));
  final audio = _StubDualAudioService(
    state: const PlayerPlaying(),
    position: _position,
    qualityId: '30280',
  );
  final commands = _RecordingCommands();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dualAudioServiceProvider.overrideWithValue(audio),
        playbackCommandsProvider.overrideWith(() => commands),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeRegistry.defaultTheme.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 320,
              child: AlbumProgressBar(
                duration: duration,
                centerLabel: const Text('SQ'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(audio: audio, commands: commands);
}

void _applyViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// 推进 AlbumSection 的 200ms 延迟 + 400ms 入场动画。
Future<void> _settleEntrance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  await tester.pump(const Duration(milliseconds: 420));
  await tester.pump();
}

class _Harness {
  const _Harness({required this.audio, required this.commands});

  final _StubDualAudioService audio;
  final _RecordingCommands commands;
}

/// 记录 seek 目标的命令层替身：不构造 PlayerCoordinator，也不落库。
class _RecordingCommands extends PlaybackCommands {
  final List<Duration> seeks = <Duration>[];

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }
}

/// 只提供状态通知器、绝不创建 libmpv 播放器的双播放器服务。
class _StubDualAudioService extends DualAudioService {
  _StubDualAudioService({
    required PlayerState state,
    required Duration position,
    required String qualityId,
  }) : _playerState = ValueNotifier<PlayerState>(state),
       _position = ValueNotifier<Duration>(position),
       _durationNotifier = ValueNotifier<Duration>(_duration),
       _volume = ValueNotifier<double>(0.72),
       _qualityId = ValueNotifier<String>(qualityId);

  final ValueNotifier<PlayerState> _playerState;
  final ValueNotifier<Duration> _position;
  final ValueNotifier<Duration> _durationNotifier;
  final ValueNotifier<double> _volume;
  final ValueNotifier<String> _qualityId;

  // playback_providers 的 watcher 会把 playerState 强转成 ValueNotifier 再挂
  // listener，所以这里都收窄成 ValueNotifier。
  @override
  ValueNotifier<PlayerState> get playerState => _playerState;

  @override
  ValueNotifier<Duration> get position => _position;

  @override
  ValueNotifier<Duration> get duration => _durationNotifier;

  @override
  ValueNotifier<double> get volume => _volume;

  @override
  ValueNotifier<String> get actualQualityId => _qualityId;

  @override
  void initialize() {}

  @override
  Future<void> dispose() async {}
}
