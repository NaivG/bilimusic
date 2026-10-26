import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/domain/artist.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/playlist/playlist_entries_io.dart';

void main() {
  Music music(String id, String cid) => Music(
    id: id,
    cid: cid,
    title: '标题 $id',
    artist: const Artist(mid: 42, name: 'UP 主'),
    album: '专辑',
    coverUrl: 'https://example.com/$id.jpg',
    duration: const Duration(minutes: 3, seconds: 12),
    audioUrl: 'https://example.com/$id.m4a',
    isFavorite: true,
  );

  group('PlaylistEntriesIo', () {
    test('导出的文件只包含条目，不包含歌单元信息', () {
      final json = jsonDecode(PlaylistEntriesIo.encode([music('BV1', '11')]));

      expect(json['format'], PlaylistEntriesIo.format);
      expect(json['version'], PlaylistEntriesIo.formatVersion);
      expect(json.keys, isNot(contains('name')));
      expect(json.keys, isNot(contains('coverUrl')));
      expect(json['songs'], hasLength(1));
    });

    test('编码后解码能还原条目', () {
      final source = [music('BV1', '11'), music('BV2', '22')];
      final decoded = PlaylistEntriesIo.decode(
        PlaylistEntriesIo.encode(source),
      );

      expect(decoded, hasLength(2));
      expect(decoded[0].id, 'BV1');
      expect(decoded[0].cid, '11');
      expect(decoded[0].title, '标题 BV1');
      expect(decoded[0].artist.name, 'UP 主');
      expect(decoded[0].duration, const Duration(minutes: 3, seconds: 12));
      expect(decoded[0].isFavorite, isTrue);
      expect(decoded[1].id, 'BV2');
    });

    test('兼容根节点直接是数组的文件', () {
      final decoded = PlaylistEntriesIo.decode(
        jsonEncode([music('BV1', '11').toJson()]),
      );

      expect(decoded.single.id, 'BV1');
    });

    test('兼容带 UTF-8 BOM 的文件', () {
      final decoded = PlaylistEntriesIo.decode(
        '\uFEFF${jsonEncode([music('BV1', '11').toJson()])}',
      );

      expect(decoded.single.id, 'BV1');
    });

    test('兼容数字形式的 duration', () {
      final entry = music('BV1', '11').toJson()..['duration'] = 125;
      final decoded = PlaylistEntriesIo.decode(jsonEncode([entry]));

      expect(decoded.single.duration, const Duration(seconds: 125));
    });

    test('跳过缺少 id 的单条坏数据', () {
      final valid = music('BV1', '11').toJson();
      final invalid = music('', '22').toJson();
      final decoded = PlaylistEntriesIo.decode(jsonEncode([invalid, valid]));

      expect(decoded.single.id, 'BV1');
    });

    test('不是 JSON 时抛出格式异常', () {
      expect(
        () => PlaylistEntriesIo.decode('not json'),
        throwsA(isA<PlaylistEntriesFormatException>()),
      );
    });

    test('没有可用条目时抛出格式异常', () {
      expect(
        () => PlaylistEntriesIo.decode('{"songs":[]}'),
        throwsA(isA<PlaylistEntriesFormatException>()),
      );
    });

    test('拒绝其它格式的文件', () {
      expect(
        () =>
            PlaylistEntriesIo.decode('{"format":"something_else","songs":[]}'),
        throwsA(isA<PlaylistEntriesFormatException>()),
      );
    });
  });
}
