import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/shared/utils/title_meta_filter.dart';

/// 标题元信息过滤器测试。
///
/// 覆盖三层：解析（AST 结构与原文还原）、清理（关键词/白名单/层级规则）、
/// 兜底（剥空保护、未闭合括号、正文保护）。
void main() {
  group('解析', () {
    test('括号与分隔符解析成节点树，render 与原文逐字一致', () {
      const title = '【 作者 / MV 】Star';
      final nodes = TitleMetaFilter.parse(title);

      expect(nodes, hasLength(2));
      final bracket = nodes[0] as TitleAstBracket;
      expect(bracket.open, '【');
      expect(bracket.close, '】');
      expect(bracket.children, hasLength(3));
      expect((bracket.children[0] as TitleAstText).text, ' 作者 ');
      expect(bracket.children[1], isA<TitleAstSeparator>());
      expect((bracket.children[2] as TitleAstText).text, ' MV ');
      expect(nodes[1], isA<TitleAstText>());

      expect(nodes.map((n) => n.render()).join(), title);
    });

    test('未闭合括号按普通文本处理', () {
      final nodes = TitleMetaFilter.parse('曲名【abc');
      expect(nodes, hasLength(1));
      expect((nodes[0] as TitleAstText).text, '曲名【abc');
    });

    test('同类括号支持嵌套', () {
      final nodes = TitleMetaFilter.parse('【a【b】c】');
      final bracket = nodes[0] as TitleAstBracket;
      expect(bracket.children, hasLength(3));
      expect(bracket.children[1], isA<TitleAstBracket>());
    });
  });

  group('清理：基础', () {
    test('剥掉尾部的【中字】', () {
      final r = TitleMetaFilter.clean('夜に駆ける【中字】');
      expect(r.cleaned, '夜に駆ける');
      expect(r.changed, isTrue);
      expect(r.removed, ['【中字】']);
    });

    test('连续的头部噪音括号全部剥掉', () {
      final r = TitleMetaFilter.clean('【字幕组】【中字】曲名');
      expect(r.cleaned, '曲名');
      expect(r.removed, containsAll(['【字幕组】', '【中字】']));
    });

    test('头尾组合：PV付 + MV', () {
      final r = TitleMetaFilter.clean('【PV付】Starlight【MV】');
      expect(r.cleaned, 'Starlight');
      expect(r.removed, ['【PV付】', '【MV】']);
    });

    test('ASCII 圆括号与小写关键词（不区分大小写）', () {
      expect(
        TitleMetaFilter.clean('Starlight (Official Video)').cleaned,
        'Starlight',
      );
      expect(TitleMetaFilter.clean('Starlight（video）').cleaned, 'Starlight');
    });

    test('〖〗 与 （） 同样生效', () {
      expect(TitleMetaFilter.clean('〖中字〗Starlight').cleaned, 'Starlight');
      expect(TitleMetaFilter.clean('曲名（自用备份）').cleaned, '曲名');
    });
  });

  group('清理：用户示例（括号内按分隔符精确拆分）', () {
    test('【 作者 / MV 】 只去掉 MV 段，作者保留', () {
      final r = TitleMetaFilter.clean('【 作者 / MV 】Starlight【中字】');
      expect(r.cleaned, '【作者】Starlight');
      expect(r.removed, ['MV', '【中字】']);
    });

    test('白名单段与噪音段混合时只删噪音段', () {
      expect(TitleMetaFilter.clean('【Hi-Res / MV】').cleaned, '【Hi-Res】');
      expect(TitleMetaFilter.clean('【杜比全景声 / MV】').cleaned, '【杜比全景声】');
      expect(TitleMetaFilter.clean('【MV / 中字 / Hi-Res】').cleaned, '【Hi-Res】');
    });

    test('中间段被删后两侧内容用原分隔符拼接', () {
      expect(
        TitleMetaFilter.clean('【作者 / MV / Hi-Res】').cleaned,
        '【作者 / Hi-Res】',
      );
    });

    test('首个存活段之前不补分隔符（删掉头段不会凭空多出一个 /）', () {
      expect(TitleMetaFilter.clean('【MV / 作者】').cleaned, '【作者】');
    });

    test('连续分隔符产生的空段被丢弃后，两段之间只补回一个分隔符', () {
      expect(
        TitleMetaFilter.clean('【作者 //MV / Hi-Res】').cleaned,
        '【作者 / Hi-Res】',
      );
    });
  });

  group('清理：白名单（音质信息永不误删）', () {
    test('Hi-Res / 杜比 / 声道 括号原样保留', () {
      expect(
        TitleMetaFilter.clean('Starlight【Hi-Res】').cleaned,
        'Starlight【Hi-Res】',
      );
      expect(
        TitleMetaFilter.clean('【杜比全景声】Starlight').cleaned,
        '【杜比全景声】Starlight',
      );
      expect(
        TitleMetaFilter.clean('Starlight（5.1声道）').cleaned,
        'Starlight（5.1声道）',
      );
    });

    test('同段同时含白名单与关键词时整段保留（宁漏勿错）', () {
      expect(TitleMetaFilter.clean('【Hi-Res MV】').cleaned, '【Hi-Res MV】');
    });
  });

  group('清理：全角折算（判定折半角，输出保留原文）', () {
    test('全角关键词与全角括号同样命中', () {
      expect(TitleMetaFilter.clean('曲名【ＭＶ】').cleaned, '曲名');
      expect(TitleMetaFilter.clean('【ＰＶ付】曲名').cleaned, '曲名');
      expect(TitleMetaFilter.clean('Starlight（ｖｉｄｅｏ）').cleaned, 'Starlight');
    });

    test('全角分隔符切段：白名单段按原写法保留，噪音段照删', () {
      final r = TitleMetaFilter.clean('【作者／ＭＶ／Ｈｉ－Ｒｅｓ】');
      // 折半角只参与判定，没改动的内容逐字保留（Ｈｉ－Ｒｅｓ 不会变成 Hi-Res）
      expect(r.cleaned, '【作者／Ｈｉ－Ｒｅｓ】');
      expect(r.removed, ['ＭＶ']);
    });

    test('顶层孤立的全角关键词段同样移除', () {
      expect(TitleMetaFilter.clean('ＭＶ ／ 曲名').cleaned, '曲名');
      expect(TitleMetaFilter.clean('曲名 ／ ＭＶ').cleaned, '曲名');
    });

    test('全角空格与全角正文不受影响', () {
      expect(TitleMetaFilter.clean('　曲名【ＭＶ】　').cleaned, '曲名');
      // 正文仍是逐字保护：全角写法不等于关键词本身
      expect(TitleMetaFilter.clean('ＭＶゲーム').cleaned, 'ＭＶゲーム');
      expect(TitleMetaFilter.clean('曲名【Ｌｉｖｅ】').cleaned, '曲名【Ｌｉｖｅ】');
    });
  });

  group('清理：正文保护（顶层文本不按关键词删）', () {
    test('普通括号注释不受影响', () {
      expect(TitleMetaFilter.clean('夜に駆ける（YOASOBI）').cleaned, '夜に駆ける（YOASOBI）');
    });

    test('「」里的歌名不受影响', () {
      expect(TitleMetaFilter.clean('「夜に駆ける」').cleaned, '「夜に駆ける」');
    });

    test('中间括号/文本段不动（只处理清空的噪音括号与首尾孤立关键词）', () {
      // 【Live】不在关键词表，保持原样
      expect(TitleMetaFilter.clean('曲名【Live】').cleaned, '曲名【Live】');
      // 中间的「中字」不是首尾孤立文本，保守保留
      expect(TitleMetaFilter.clean('曲名 / 中字 / 作者').cleaned, '曲名 / 中字 / 作者');
    });

    test('首尾孤立的关键词文本段会被移除', () {
      expect(TitleMetaFilter.clean('曲名 / MV').cleaned, '曲名');
      expect(TitleMetaFilter.clean('MV / 曲名').cleaned, '曲名');
    });

    test('`-` 不是分隔符：含连字符的写法不会被误拆', () {
      expect(TitleMetaFilter.clean('曲名 - MV').cleaned, '曲名 - MV');
    });
  });

  group('清理：接缝与残留清理', () {
    test('中间噪音括号删除后两侧文本用单空格拼接', () {
      expect(TitleMetaFilter.clean('曲名【MV】Live').cleaned, '曲名 Live');
      expect(TitleMetaFilter.clean('曲名【MV】 Live').cleaned, '曲名 Live');
    });

    test('删除后的首尾残留符号被裁掉', () {
      expect(TitleMetaFilter.clean('曲名 - 【MV】').cleaned, '曲名');
      expect(
        TitleMetaFilter.clean('Starlight (Live) / MV').cleaned,
        'Starlight (Live)',
      );
    });

    test('空括号整块移除', () {
      expect(TitleMetaFilter.clean('曲名【】').cleaned, '曲名');
    });

    test('挂在噪音文本上的注解括号一并移除', () {
      expect(TitleMetaFilter.clean('【中字（简体）】曲名').cleaned, '曲名');
    });
  });

  group('兜底', () {
    test('全部剥空时返回原标题', () {
      final r = TitleMetaFilter.clean('【中字】【MV】');
      expect(r.cleaned, '【中字】【MV】');
      expect(r.changed, isFalse);
    });

    test('未闭合括号不处理', () {
      final r = TitleMetaFilter.clean('曲名【MV');
      expect(r.changed, isFalse);
    });

    test('无噪音的标题原样返回', () {
      final r = TitleMetaFilter.clean('夜に駆ける');
      expect(r.changed, isFalse);
      expect(r.removed, isEmpty);
    });
  });

  group('白名单与关键词组合层级', () {
    test('头部白名单括号保留，尾部噪音括号移除', () {
      final r = TitleMetaFilter.clean('【字幕组】【Hi-Res】曲名【MV】');
      expect(r.cleaned, '【Hi-Res】曲名');
      expect(r.removed, ['【字幕组】', '【MV】']);
    });
  });

  group('maybeClean（设置开关门禁）', () {
    test('默认关闭：任何标题原样返回', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = false;
      expect(TitleMetaFilter.maybeClean('曲名【MV】'), '曲名【MV】');
      expect(TitleMetaFilter.maybeClean('夜に駆ける'), '夜に駆ける');
    });

    test('开启后等价于 clean().cleaned', () {
      final previous = TitleMetaFilter.enabled;
      addTearDown(() => TitleMetaFilter.enabled = previous);
      TitleMetaFilter.enabled = true;
      expect(TitleMetaFilter.maybeClean('曲名【MV】'), '曲名');
      expect(TitleMetaFilter.maybeClean('曲名【Live】'), '曲名【Live】');
      // 空串短路：不进解析器
      expect(TitleMetaFilter.maybeClean(''), '');
    });
  });
}
