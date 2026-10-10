import 'package:flutter_test/flutter_test.dart';
import 'package:bilimusic/features/taste/logic/text_normalizer.dart';

import 'taste_test_helpers.dart';

void main() {
  group('tasteText', () {
    test('括号符号剥掉、内容保留，artist / 分区名拼入', () {
      final m = music('1', '【翻唱】Starlight【中字】', artist: '周杰伦', album: '翻唱');
      expect(tasteText(m), ' 翻唱 Starlight 中字  周杰伦 翻唱');
    });

    test('未知专辑不拼入', () {
      final m = music('1', '晴天', album: '未知专辑');
      expect(tasteText(m), '晴天 x');
    });

    test('artist 里的括号也剥掉（不只标题）', () {
      final m = music('1', '晴天', artist: '【Aimer】');
      expect(tasteText(m), '晴天  Aimer ');
    });
  });

  group('normalizeTokens', () {
    test('英文折叠小写、去纯数字纯标点', () {
      expect(normalizeTokens(['Jazz', '123', '！！', 'Piano', 'ok']), [
        'jazz',
        'piano',
        'ok',
      ]);
    });

    test('单字 CJK 丢弃，多字保留；「A股」这类混排单 token 保留', () {
      expect(normalizeTokens(['梦', '钢琴', 'A股']), ['钢琴', 'a股']);
    });

    test('视频噪音词丢弃，但内容类型标签保留', () {
      // 设计点：TitleMetaFilter 把【翻唱】当显示噪音删，
      // 画像层刻意保留它——那是风格信号，只有 mv/中字 这类纯视频信息才丢。
      expect(normalizeTokens(['翻唱', '原创曲', 'mv', '中字', '钢琴']), [
        '翻唱',
        '原创曲',
        '钢琴',
      ]);
    });

    test('短英文 token 丢弃', () {
      expect(normalizeTokens(['a', 'ok', 'id']), ['ok', 'id']);
    });

    test('粘在词条上的括号切开剥掉（分词器会粘，如【snow / MIMI】）', () {
      expect(normalizeTokens(['【snow', 'MIMI】']), ['snow', 'mimi']);
      // 中间粘连切开成两个词条，不是删括号缝成 snowmimi
      expect(normalizeTokens(['snow【mimi】']), ['snow', 'mimi']);
      // 纯括号 token 变空丢弃
      expect(normalizeTokens(['【】']), isEmpty);
    });

    test('括号包住的歌名剥成裸词条，能和无括号写法对上', () {
      expect(normalizeTokens(['《青花瓷》', '青花瓷']), ['青花瓷', '青花瓷']);
    });
  });
}
