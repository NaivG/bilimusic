/// 音乐画像的文本归一化：把 [Music] 拍成 NLP 语料、把分词产物洗成词条。
///
/// 与 `TitleMetaFilter`（显示用）的关键差别：**画像吃原始标题**。
/// 显示过滤把【翻唱】【原创曲】当视频元信息剥掉，但对口味画像来说
/// 这类括号恰恰是最值钱的风格标签；真正无信息量的视频噪音（MV/中字…）
/// 由 [videoNoiseTokens] 在词条层拦截，两套语义互不干扰。
library;

import 'package:bilimusic/domain/music.dart';

/// 纯视频信息噪音词（大小写不敏感，比较前先 lowercase）。
///
/// 取自 TitleMetaFilter.videoMetaKeywords 中「对口味毫无信息量」的子集；
/// 【翻唱】【原创曲】【自制】等内容类型标签**刻意不在此列**——它们是风格信号。
const Set<String> videoNoiseTokens = {
  'mv',
  'pv',
  'video',
  '官方mv',
  '本家投稿',
  '中字',
  '字幕',
  '中译',
  '熟肉',
  '生肉',
  '自用',
  '自翻',
  '自译',
};

/// 括号装饰字符。
final RegExp bracketChars = RegExp(r'[【】\[\]（）()<>《》「」『』]');

/// 把 Music 拍成画像语料文本：原始标题（括号保留为内容）+ 艺人 + 分区名。
///
/// - 标题用 [Music.title] 的**原文**（含【】风格标签），不做显示过滤。
/// - `artist` / `album`（B 站 tname 分区名，如「翻唱」「流行」）本身就是
///   流派线索，拼进去让分词一起吃。
/// - 括号符号统一换成空格，避免【翻唱】被分成带括号的怪词。
String tasteText(Music m) {
  final parts = <String>[
    m.title,
    if (m.artist.name.isNotEmpty) m.artist.name,
    if (m.album.isNotEmpty && m.album != '未知专辑') m.album,
  ];
  return parts.join(' ').replaceAll(bracketChars, ' ');
}

/// 把分词产物洗成画像词条：
///
/// - 每个 token 先按括号切开（分词器会把括号粘在词条上，
///   如【snow / MIMI】，切开后内容才是词条）
/// - 英文折叠为小写；去掉首尾空白与纯标点/纯数字 token
/// - 单字 CJK token 丢弃（「的」「梦」这类单字噪音远多于信号）
/// - 纯英文 token 长度 < 2 丢弃；命中 [videoNoiseTokens] 丢弃
List<String> normalizeTokens(Iterable<String> raw) {
  final out = <String>[];
  for (final chunk in raw) {
    for (var t in chunk.split(bracketChars)) {
      t = t.trim();
      if (t.isEmpty) continue;
      final lower = t.toLowerCase();
      if (videoNoiseTokens.contains(lower)) continue;
      if (_isPurePunctOrDigit(t)) continue;

      final hasCjk = t.codeUnits.any(_isCjkCodeUnit);
      if (hasCjk) {
        // 含 CJK：整 token 长度 1 且是 CJK 单字才丢，「A股」这类保留
        if (t.length == 1) continue;
      } else {
        if (t.length < 2) continue;
      }
      out.add(lower);
    }
  }
  return out;
}

bool _isCjkCodeUnit(int u) =>
    (u >= 0x4E00 && u <= 0x9FFF) || (u >= 0x3400 && u <= 0x4DBF);

bool _isPurePunctOrDigit(String t) {
  for (final u in t.codeUnits) {
    final isDigit = u >= 0x30 && u <= 0x39;
    final isPunct =
        !_isCjkCodeUnit(u) &&
        !(u >= 0x41 && u <= 0x5A) && // A-Z
        !(u >= 0x61 && u <= 0x7A) && // a-z
        u != 0x5F; // _
    if (!isDigit && !isPunct) return false;
  }
  return true;
}
