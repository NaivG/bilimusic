import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/up_profile.dart';
import 'package:bilimusic/features/artist/widgets/artist_header.dart';

/// 歌手页页头：头像（认证徽标）+ 昵称 / 投稿数 / 描述 + 操作按钮。
///
/// 用例全部用空 face，避免 widget 测试里去拉网络图。
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  const up = UpProfile(
    mid: 14082,
    name: '山新',
    sign: '都说了是天依爹地',
    verifyDesc: '配音演员、声优',
  );

  testWidgets('渲染昵称、描述、投稿数和两个按钮', (tester) async {
    await tester.pumpWidget(
      wrap(
        ArtistHeader(
          up: up,
          submissionCount: 218,
          onPlayAll: () {},
          onShufflePlay: () {},
        ),
      ),
    );

    expect(find.text('山新'), findsOneWidget);
    expect(find.text('都说了是天依爹地'), findsOneWidget);
    expect(find.text('218 个投稿'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('随机播放'), findsOneWidget);
  });

  testWidgets('未认证时不挂徽标；认证时徽标压在头像上', (tester) async {
    await tester.pumpWidget(
      wrap(const ArtistHeader(up: UpProfile(mid: 1, name: 'A'))),
    );
    expect(find.byIcon(Icons.verified), findsNothing);

    await tester.pumpWidget(wrap(const ArtistHeader(up: up)));
    expect(find.byIcon(Icons.verified), findsOneWidget);

    // 徽标落在圆形头像（ClipOval）框内的右下角
    final avatar = tester.getRect(find.byType(ClipOval));
    final badge = tester.getRect(find.byIcon(Icons.verified));
    expect(avatar.contains(badge.center), isTrue);
    expect(badge.center.dx, greaterThan(avatar.center.dx));
    expect(badge.center.dy, greaterThan(avatar.center.dy));
  });

  testWidgets('投稿数未知（0）时不显示数量行', (tester) async {
    await tester.pumpWidget(wrap(const ArtistHeader(up: up)));

    expect(find.textContaining('个投稿'), findsNothing);
  });

  testWidgets('两个按钮分别回调', (tester) async {
    var played = 0;
    var shuffled = 0;
    await tester.pumpWidget(
      wrap(
        ArtistHeader(
          up: up,
          onPlayAll: () => played++,
          onShufflePlay: () => shuffled++,
        ),
      ),
    );

    await tester.tap(find.text('播放全部'));
    await tester.tap(find.text('随机播放'));

    expect(played, 1);
    expect(shuffled, 1);
  });

  testWidgets('攒队列期间按钮不可点', (tester) async {
    var played = 0;
    await tester.pumpWidget(
      wrap(ArtistHeader(up: up, isBusy: true, onPlayAll: () => played++)),
    );

    await tester.tap(find.text('播放全部'), warnIfMissed: false);

    expect(played, 0);
  });

  testWidgets('窄屏（360dp）不溢出：按钮换行，头像与文字都还在', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(
        ArtistHeader(
          up: up,
          submissionCount: 218,
          onPlayAll: () {},
          onShufflePlay: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ClipOval), findsOneWidget);
    expect(find.text('山新'), findsOneWidget);
    expect(find.text('播放全部'), findsOneWidget);
    expect(find.text('随机播放'), findsOneWidget);
  });
}
