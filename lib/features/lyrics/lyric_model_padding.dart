import 'package:flutter_lyric/core/lyric_model.dart';

/// 在歌词模型开头补 [count] 行空白。
///
/// [LyricView] 在内容不足以滚动时会把首句贴到顶部，`FadeRange` 会把它吃掉；
/// 空白行只占位，不参与逐字填充。
LyricModel padLeadingBlankLines(LyricModel model, {int count = 2}) {
  if (model.lines.isEmpty || count <= 0) return model;
  final blankEnd = model.lines.first.start;
  return LyricModel(
    tags: model.idTags,
    lines: [
      for (var i = 0; i < count; i++)
        LyricLine(start: Duration.zero, end: blankEnd, text: ' '),
      ...model.lines,
    ],
  );
}
