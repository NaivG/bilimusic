import 'package:flutter_lyric/core/lyric_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lyrics/lyric_model_padding.dart';

void main() {
  test('空歌词不补空白行', () {
    final model = LyricModel(lines: const <LyricLine>[]);

    expect(padLeadingBlankLines(model), same(model));
  });

  test('开头补两行空白，首句与标签原样保留', () {
    final first = LyricLine(
      start: const Duration(seconds: 5),
      end: const Duration(seconds: 9),
      text: '第一句',
      translation: 'first line',
    );
    final model = LyricModel(
      tags: const {'ti': '歌名'},
      lines: [
        first,
        LyricLine(start: const Duration(seconds: 9), text: '第二句'),
      ],
    );

    final padded = padLeadingBlankLines(model);

    expect(padded.lines.length, model.lines.length + 2);
    expect(padded.lines[0].text.trim(), isEmpty);
    expect(padded.lines[1].text.trim(), isEmpty);
    expect(padded.lines[0].start, Duration.zero);
    expect(padded.lines[0].end, const Duration(seconds: 5));
    expect(padded.lines[2], same(first));
    expect(padded.lines[2].start, const Duration(seconds: 5));
    expect(padded.idTags, same(model.idTags));
    // 原模型不被修改。
    expect(model.lines.length, 2);
  });

  test('count 可覆盖，0 不补', () {
    final model = LyricModel(
      lines: [LyricLine(start: Duration.zero, text: '句')],
    );

    expect(padLeadingBlankLines(model, count: 0), same(model));
    expect(padLeadingBlankLines(model, count: 1).lines.length, 2);
  });
}
