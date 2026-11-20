import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/shared/ui/cards/bm_media_card.dart';

void main() {
  testWidgets('方形封面按布局宽度选桶并生成 _1c URL', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: BmArtImage(url: 'https://i0.hdslb.com/bfs/archive/a.jpg'),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.imageUrl, 'https://i0.hdslb.com/bfs/archive/a.jpg@96w_96h_1c');
    expect(image.memCacheWidth, 96);
  });

  testWidgets('16:9 封面按宽度算高度', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 90,
              child: BmArtImage(
                url: 'https://i2.hdslb.com/bfs/archive/b.jpg',
                aspectRatio: 16 / 9,
              ),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      image.imageUrl,
      'https://i2.hdslb.com/bfs/archive/b.jpg@176w_99h_1c',
    );
    expect(image.memCacheWidth, 176);
  });
}
