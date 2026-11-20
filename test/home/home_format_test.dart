import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/home/widgets/greeting_card.dart';
import 'package:bilimusic/features/home/widgets/home_format.dart';

/// 首页文案：时段问候、页头日期、曲目时长。
void main() {
  group('问候', () {
    test('按时段分档', () {
      expect(greetingText(3), '夜深了');
      expect(greetingText(8), '早上好');
      expect(greetingText(10), '上午好');
      expect(greetingText(13), '中午好');
      expect(greetingText(16), '下午好');
      expect(greetingText(20), '晚上好');
      expect(greetingText(23), '夜深了');
    });

    test('带上用户名；空名不留标点', () {
      expect(greetingText(20, 'Akarin'), '晚上好，Akarin');
      expect(greetingText(20, '   '), '晚上好');
      expect(greetingText(20, null), '晚上好');
    });

    test('页头日期是 M月D日 · 星期X', () {
      expect(greetingDateLabel(DateTime(2024, 1, 1)), '1月1日 · 星期一');
      expect(greetingDateLabel(DateTime(2024, 1, 7)), '1月7日 · 星期日');
    });
  });

  group('时长', () {
    test('分:秒，秒补两位', () {
      expect(formatTrackTime(const Duration(minutes: 4, seconds: 21)), '4:21');
      expect(formatTrackTime(const Duration(seconds: 9)), '0:09');
    });

    test('超过一小时补小时段', () {
      expect(
        formatTrackTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('缺时长不猜', () {
      expect(formatTrackTime(null), '--:--');
      expect(formatTrackTime(Duration.zero), '--:--');
    });
  });

  group('舞台卡副标题', () {
    test('UP 主 · 专辑', () {
      final music = Music(
        id: 'BV1',
        title: '夜に駆ける',
        artist: const Artist(name: 'YOASOBI'),
        album: 'THE BOOK 3',
        coverUrl: '',
        audioUrl: '',
      );
      expect(heroSubtitle(music), 'YOASOBI · THE BOOK 3');
    });

    test('没有专辑时只留 UP 主', () {
      final music = Music(
        id: 'BV1',
        title: 't',
        artist: const Artist(name: 'Aimer'),
        album: '  ',
        coverUrl: '',
        audioUrl: '',
      );
      expect(heroSubtitle(music), 'Aimer');
    });
  });
}
