import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/app/shells/landscape/landscape_content_stage.dart';
import 'package:bilimusic/shared/theme/theme_registry.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';

/// [LandscapeContentStage] 的裁切：滑出舞台的抽屉 / 队列不许画到图标轨上。
///
/// 抽屉与队列用 `AnimatedSlide`（绘制期位移），`Stack.clipBehavior` 只裁布局
/// 溢出；两者都装得下时 Stack 不会插裁切层，位移出去的那截会直接画到两侧的
/// 图标轨上。这里用像素断言锁住舞台自己的 `ClipRect`。
void main() {
  testWidgets('关闭态：抽屉与队列停在舞台之外，两翼图标轨保持原色', (tester) async {
    final shot = await _pumpStage(tester);

    expect(shot.pixel(38, 100), _railColor, reason: '左轨');
    expect(shot.pixel(476, 100), _pageColor, reason: '舞台内部');
    expect(shot.pixel(914, 100), _railColor, reason: '右轨');
  });

  testWidgets('资料库展开：抽屉从舞台左缘滑入，左轨不被覆盖', (tester) async {
    final shot = await _pumpStage(tester, libraryOpen: true);

    expect(shot.pixel(38, 100), _railColor);
    expect(shot.pixel(100, 100), _drawerColor);
  });

  testWidgets('队列展开：队列从舞台右缘滑入，右轨不被覆盖', (tester) async {
    final shot = await _pumpStage(tester, queueOpen: true);

    expect(shot.pixel(914, 100), _railColor);
    expect(shot.pixel(800, 100), _queueColor);
  });

  testWidgets('裁剪层与舞台同尺寸，关闭态抽屉整幅停在舞台左缘之外', (tester) async {
    await _pumpStage(tester);

    final stage = find.byType(LandscapeContentStage);
    final clip = find
        .ancestor(
          of: find.byKey(const Key('stage-page')),
          matching: find.byType(ClipRect),
        )
        .first;

    final stageRect = tester.getRect(stage);
    expect(tester.getRect(clip), stageRect);
    expect(stageRect.left, _railWidth);
    expect(
      tester.getRect(find.byKey(const Key('stage-drawer'))).right,
      lessThanOrEqualTo(_railWidth + 0.01),
    );
  });
}

const Color _railColor = Color(0xFF12A150);
const Color _pageColor = Color(0xFF1D4ED8);
const Color _drawerColor = Color(0xFFDC2626);
const Color _queueColor = Color(0xFFCA8A04);

const double _railWidth = 76;
const double _stageWidth = 800;
const double _surfaceWidth = _railWidth * 2 + _stageWidth;
const double _surfaceHeight = 200;

/// 左轨 + 舞台 + 右轨：舞台两侧各放一条 76 宽的「图标轨」当探针。
///
/// 轨先画、舞台后画，抽屉 / 队列一旦漏出舞台就会盖住轨上的取样点。
Future<_Shot> _pumpStage(
  WidgetTester tester, {
  bool libraryOpen = false,
  bool queueOpen = false,
}) async {
  final boundaryKey = GlobalKey();

  // 默认测试画布只有 800 宽，装不下「轨 + 舞台 + 轨」；这里按真实横屏铺开。
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(_surfaceWidth, _surfaceHeight);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeRegistry.defaultTheme.light(),
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _surfaceWidth,
          height: _surfaceHeight,
          child: RepaintBoundary(
            key: boundaryKey,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: const [
                      SizedBox(
                        width: _railWidth,
                        height: _surfaceHeight,
                        child: ColoredBox(color: _railColor),
                      ),
                      Expanded(child: SizedBox.expand()),
                      SizedBox(
                        width: _railWidth,
                        height: _surfaceHeight,
                        child: ColoredBox(color: _railColor),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: _railWidth,
                  right: _railWidth,
                  top: 0,
                  bottom: 0,
                  child: LandscapeContentStage(
                    libraryOpen: libraryOpen,
                    queueOpen: queueOpen,
                    onCloseDrawers: () {},
                    page: const ColoredBox(
                      key: Key('stage-page'),
                      color: _pageColor,
                    ),
                    libraryDrawer: const SizedBox(
                      key: Key('stage-drawer'),
                      width: BmTokens.libraryDrawerWidth,
                      child: ColoredBox(color: _drawerColor),
                    ),
                    queuePanel: const SizedBox(
                      key: Key('stage-queue'),
                      width: BmTokens.queuePanelWidth,
                      child: ColoredBox(color: _queueColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final image = await tester.runAsync(boundary.toImage);
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return _Shot(image!, data!.buffer.asUint8List());
}

/// 一帧截图；[pixel] 用逻辑坐标取色（`toImage` 默认 pixelRatio 1）。
class _Shot {
  _Shot(this.image, this.bytes);

  final ui.Image image;
  final Uint8List bytes;

  Color pixel(int x, int y) {
    final offset = (y * image.width + x) * 4;
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }
}
