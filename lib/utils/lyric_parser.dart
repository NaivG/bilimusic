/// 歌词解析工具类
class LyricParser {
  /// 歌词行信息
  final List<LyricLine> lines;

  LyricParser(this.lines);

  /// 解析歌词文本
  static LyricParser parse(String lyricText) {
    final lines = <LyricLine>[];

    // 匹配新格式 [mm:ss.SSS]歌词内容
    final newFormatRegex = RegExp(r'\[(\d{2}):(\d{2}\.\d{3})\](.*)');
    // 匹配旧格式 [mm:ss.SS]歌词内容
    final oldFormatRegex = RegExp(r'\[(\d{2}):(\d{2}\.\d{2})\](.*)');

    final lyricLines = lyricText.split('\n');

    // 尝试解析新格式
    for (final line in lyricLines) {
      final match = newFormatRegex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final content = match.group(3)!.trim();
        final time = minutes * 60 + seconds;
        lines.add(LyricLine(time: time, content: content));
      }
    }

    // 如果没有解析到任何内容，尝试旧格式
    if (lines.isEmpty) {
      for (final line in lyricLines) {
        final match = oldFormatRegex.firstMatch(line);
        if (match != null) {
          final minutes = int.parse(match.group(1)!);
          final seconds = double.parse(match.group(2)!);
          final content = match.group(3)!.trim();
          final time = minutes * 60 + seconds;
          lines.add(LyricLine(time: time, content: content));
        }
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.time.compareTo(b.time));

    return LyricParser(lines);
  }

  /// 根据时间获取当前歌词行
  LyricLine? getCurrentLine(double time) {
    if (lines.isEmpty) return null;

    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].time <= time) {
        return lines[i];
      }
    }

    return lines.first;
  }

  /// 获取下一行歌词
  LyricLine? getNextLine(double time) {
    if (lines.isEmpty) return null;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].time > time) {
        return lines[i];
      }
    }

    return null;
  }
}

/// 歌词行信息
class LyricLine {
  /// 时间（秒）
  final double time;

  /// 歌词内容
  final String content;

  LyricLine({required this.time, required this.content});

  @override
  String toString() {
    return '[$time] $content';
  }
}
