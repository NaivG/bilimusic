import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';

/// 假分词器：按空白切分。测试语料里词条之间用空格隔开即可，
/// 让「加权/过滤/排序」逻辑与 snownlp 模型完全解耦。
List<String> fakeSegment(String text) =>
    text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

Future<List<String>> fakeSegmenter(String text) async => fakeSegment(text);

/// 恒等停用词过滤（测试不背停用词表）。
List<String> identityStopFilter(List<String> tokens) => tokens;

TasteProfileBuilder fakeBuilder() => TasteProfileBuilder(
  segmenter: fakeSegmenter,
  stopFilter: identityStopFilter,
);

/// 造一首歌：id 决定 key，title 就是语料。
///
/// artist/album 默认值刻意选会被清洗管线抹掉的（单字英文 / 未知专辑），
/// 避免它们的词条混进以 title 为主的断言里。
Music music(
  String id,
  String title, {
  String artist = 'x',
  String album = '未知专辑',
}) => Music(
  id: id,
  title: title,
  artist: artist,
  album: album,
  coverUrl: '',
  audioUrl: '',
);
