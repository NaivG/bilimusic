/// 标题元信息过滤器（实验性）。
///
/// 把 B 站投稿标题按「括号 + 分隔符」解析成一棵小 AST，再在树上做
/// 节点级清理，让「【 作者 / MV 】」这类糊在一起的内容也能精确拆开：
///
/// ```text
/// 【 作者 / MV 】Starlight【中字】
///   ├─ Bracket【】── Text(" 作者 ")  Sep("/")  Text(" MV ")
///   ├─ Text("Starlight")
///   └─ Bracket【】── Text("中字")
///
/// 求值：Text(" MV ") 命中视频关键词 → 删；Bracket(中字) 清空 → 整块删
/// 结果：【作者】Starlight
/// ```
///
/// 关键词与白名单的判定一律不区分大小写，并先把全角折成半角再比
/// （`【ＭＶ】` 视同 `【MV】`、`Ｈｉ－Ｒｅｓ` 视同 `Hi-Res`）——折叠只参与
/// 判定，输出始终保留原文写法。
///
/// 规则（宁可漏删、不可错删）：
/// 1. **括号内（任意深度、任意位置）**：先自底向上清子括号；再按分隔符
///    （`/ · |` 等）切段——命中音质白名单（Hi-Res / 杜比 / 声道…）的段
///    整段保留；否则删掉段内命中视频信息关键词的文本块。删空的段与
///    因此孤立的分隔符一并收拢；整个括号被清空时整块移除。
/// 2. **括号外（顶层正文）**：正文文本永不按关键词删除（避免误伤
///    「Video Games」这类歌名）。只做两件事：移除被清空的噪音括号
///    （任意位置）；以及标题首尾恰好等于关键词的孤立文本段
///    （如「MV / 曲名」里的 `MV`）。
/// 3. **分隔符刻意不含 `-`**：`Hi-Res`、艺人名里的连字符太常见，按
///    分隔符切开会把「Hi-Res MV」拆成两段误删（`-` 只在首尾残留
///    清理时作为边角垃圾被裁掉）。
/// 4. **兜底**：全部剥空或结果与原文相同 → 返回原标题；未修改的
///    部分逐字保留（括号内未动时连空白都原样）。
///
/// 本文件是纯 Dart（不依赖 Flutter）。是否启用由设置项「标题元数据过滤
/// （实验性）」控制：SettingsManager 在启动恢复与开关变更时把值同步到
/// [TitleMetaFilter.enabled]（domain 层的 API 解析入口读不到 Riverpod /
/// SettingsManager，只能读这个静态标志，模式同 `AppDatabase.directoryResolver`
/// 的宿主注入钩子）。启用后，API 拉取的标题在解析入口统一过
/// [TitleMetaFilter.maybeClean]：`Music.fromArchiveJson`（推荐/相关/漫游）、
/// `BiliItem.fromViewApi`（视频详情）、`SearchResult.fromJson`（仅视频类型）、
/// `FavResource.fromJson`（收藏夹资源）。只影响新拉取的数据，已入库的
/// 歌单 / 历史不回溯改写；设置页另有示例预览。
library;

/// 单个标题的过滤结果。
class TitleFilterResult {
  const TitleFilterResult({
    required this.original,
    required this.cleaned,
    this.removed = const [],
  });

  /// 原标题
  final String original;

  /// 清理后的标题（未发生变化时与 [original] 相同）
  final String cleaned;

  /// 被移除的内容片段（括号按原文、文本块去空白），用于预览展示
  final List<String> removed;

  bool get changed => cleaned != original;
}

/// 标题 AST 节点。
abstract class TitleAstNode {
  const TitleAstNode();

  /// 还原为标题文本；未修改的子树与原文逐字一致。
  String render();
}

/// 连续普通文本（可含空白；不含括号与分隔符字符）。
class TitleAstText extends TitleAstNode {
  const TitleAstText(this.text);

  final String text;

  bool get isBlank => text.trim().isEmpty;

  @override
  String render() => text;
}

/// 分隔符（`/ · |` 等，见 [TitleMetaFilter.separatorChars]）。
class TitleAstSeparator extends TitleAstNode {
  const TitleAstSeparator(this.symbol);

  final String symbol;

  @override
  String render() => symbol;
}

/// 括号组：`open + children + close`，children 递归。
class TitleAstBracket extends TitleAstNode {
  const TitleAstBracket(
    this.open,
    this.close,
    this.children, {
    this.renderedOverride,
  });

  final String open;
  final String close;
  final List<TitleAstNode> children;

  /// 重建括号时缓存的内文（已裁掉首尾空白与残留符号）。
  /// 未重建的括号为 null，按 [children] 逐字拼接（与原文一致）。
  final String? renderedOverride;

  @override
  String render() {
    final inner = renderedOverride ?? children.map((n) => n.render()).join();
    return '$open$inner$close';
  }
}

/// 求值结果：清理后的节点列表 + 是否有改动 + 被移除的片段。
typedef _EvalResult = ({
  List<TitleAstNode> nodes,
  bool changed,
  List<String> removed,
});

class TitleMetaFilter {
  TitleMetaFilter._();

  /// 全局开关：是否对 API 拉取的标题做过滤。
  ///
  /// 由设置层（`SettingsManager`）在启动恢复与开关变更时写入；默认
  /// `false`（实验性功能，opt-in）。TUI / 测试等未接设置层的宿主保持
  /// 默认关闭，行为与开启前完全一致。写入方只有 SettingsManager。
  static bool enabled = false;

  /// 带开关的过滤入口：API 响应解析时对标题统一调用这里。
  ///
  /// 未启用（或空串）时原样返回，不做任何解析——保证关闭状态下
  /// 各解析入口零开销、行为逐字不变。启用时等价于 `clean(title).cleaned`。
  static String maybeClean(String title) {
    if (!enabled || title.isEmpty) return title;
    return clean(title).cleaned;
  }

  /// 参与解析的括号对。
  /// 必须命中关键词才删，普通「歌名」不会受影响。
  static const List<(String, String)> bracketPairs = [
    ('【', '】'),
    ('[', ']'),
    ('［', '］'),
    ('{', '}'),
    ('〖', '〗'),
    ('（', '）'),
    ('(', ')'),
    ('「', '」'),
    ('『', '』'),
    ('《', '》'),
    ('〈', '〉'),
    ('〔', '〕'),
    ('〘', '〙'),
    ('<', '>'),
  ];

  /// 分隔符：括号内用来切段、顶层用来切孤立文本段。
  /// 刻意不含 `-`（见文件头注释第 3 条）。
  static const String separatorChars = r'/／·・|｜，、；：:';

  /// 视频信息关键词（匹配不区分大小写，`PV` 已覆盖「PV付」）。
  /// 既要子串匹配，又要「整段恰好等于关键词」的精确判定（见 [_evalRoot]
  /// 的首尾扫除），所以是 [Set] 而不是 List。
  /// 按需增删这里即可。
  static const Set<String> videoMetaKeywords = {
    '字幕',
    '中字',
    '中译',
    'pv',
    '官方mv',
    'mv',
    '本家投稿',
    '原创曲',
    '熟肉',
    '生肉',
    'video',
    '自用',
    '自翻',
    '自译',
    '自制',
    '翻唱',
    '代发',
    '转载',
    '搬运',
  };

  /// 音质白名单：命中的段整段保留（Hi-Res / 杜比 / 声道等听音频
  /// 真正关心的信息），即使同段还含视频关键词。
  static const List<String> audioMetaWhitelist = [
    'hi-res',
    'hires',
    '杜比',
    'dolby',
    'atmos',
    '全景声',
    '声道',
    '无损',
    'flac',
    '母带',
    '音质',
    '空间音频',
    'dsd',
    'lossless',
  ];

  /// 被修改文本首尾允许顺手裁掉的残留符号（只裁首尾，不动正文中间）。
  static final RegExp _edgeJunk = RegExp(
    r'^[\s&+\-–—~〜|｜·・/／•－]+|[\s&+\-–—~〜|｜·・/／•－]+$',
  );

  /// 清理一个标题。
  static TitleFilterResult clean(String title) {
    final eval = _evalRoot(parse(title));
    if (!eval.changed) {
      return TitleFilterResult(original: title, cleaned: title);
    }
    final joined = eval.nodes.map((n) => n.render()).join();
    final cleaned = joined.replaceAll(_edgeJunk, '');
    if (cleaned.trim().isEmpty || cleaned == title) {
      // 全部剥空 / 只是原地踏步 → 放弃，返回原标题
      return TitleFilterResult(original: title, cleaned: title);
    }
    return TitleFilterResult(
      original: title,
      cleaned: cleaned,
      removed: List.unmodifiable(eval.removed),
    );
  }

  /// 把标题解析成 AST（暴露给测试与调试）。
  static List<TitleAstNode> parse(String title) =>
      _parseRange(title, 0, title.length);

  // ---------- 解析 ----------

  static List<TitleAstNode> _parseRange(String s, int start, int end) {
    final nodes = <TitleAstNode>[];
    final buf = StringBuffer();
    var i = start;
    while (i < end) {
      final ch = s[i];
      final pair = _openPairOf(ch);
      if (pair != null) {
        // 找同类闭合（支持同类嵌套）；找不到就当普通文本
        var depth = 1;
        var j = i + 1;
        while (j < end && depth > 0) {
          final c = s[j];
          if (c == pair.$1) depth++;
          if (c == pair.$2) depth--;
          j++;
        }
        if (depth == 0) {
          if (buf.isNotEmpty) {
            nodes.add(TitleAstText(buf.toString()));
            buf.clear();
          }
          nodes.add(
            TitleAstBracket(
              pair.$1,
              pair.$2,
              _parseRange(s, i + pair.$1.length, j - pair.$2.length),
            ),
          );
          i = j;
          continue;
        }
      }
      if (separatorChars.contains(ch)) {
        if (buf.isNotEmpty) {
          nodes.add(TitleAstText(buf.toString()));
          buf.clear();
        }
        nodes.add(TitleAstSeparator(ch));
        i++;
        continue;
      }
      buf.write(ch);
      i++;
    }
    if (buf.isNotEmpty) nodes.add(TitleAstText(buf.toString()));
    return nodes;
  }

  static (String, String)? _openPairOf(String ch) {
    for (final pair in bracketPairs) {
      if (ch == pair.$1) return pair;
    }
    return null;
  }

  // ---------- 求值 ----------

  /// 顶层：清括号 + 首尾扫除。正文文本不按关键词删（见文件头第 2 条）。
  static _EvalResult _evalRoot(List<TitleAstNode> nodes) {
    final removed = <String>[];
    var changed = false;
    final out = <TitleAstNode>[];

    // 括号整块删除后留下的「接缝」：下一段文本并入时收拢两侧空白，
    // 避免「曲名【MV】Live」变成「曲名  Live」。
    var pendingStitch = false;

    for (final node in nodes) {
      if (node is TitleAstBracket) {
        final inner = _evalInner(node.children);
        if (inner.changed) changed = true;
        if (_isBlankChildren(inner.nodes)) {
          // 整块剥掉：内层已记录的片段被整个括号原文涵盖，不重复上报
          changed = true;
          removed.add(node.render());
          pendingStitch = true;
          continue;
        }
        removed.addAll(inner.removed);
        if (inner.changed) {
          final rebuilt = _rebuildBracket(node, inner.nodes);
          if (rebuilt == null) {
            changed = true;
            removed.add(node.render());
            pendingStitch = true;
            continue;
          }
          out.add(rebuilt);
        } else {
          out.add(node);
        }
        pendingStitch = false;
        continue;
      }

      if (pendingStitch &&
          node is TitleAstText &&
          out.isNotEmpty &&
          out.last is TitleAstText) {
        final left = (out.last as TitleAstText).text.trimRight();
        final right = node.text.trimLeft();
        out[out.length - 1] = TitleAstText('$left $right');
      } else {
        out.add(node);
      }
      pendingStitch = false;
    }

    // 首尾扫除：分隔符 / 纯空白文本 / 恰好等于关键词的孤立文本
    bool edgeNoise(TitleAstNode n) {
      if (n is TitleAstSeparator) return true;
      if (n is TitleAstText) {
        final t = _normalize(n.text.trim());
        return t.isEmpty || videoMetaKeywords.contains(t);
      }
      return false;
    }

    while (out.isNotEmpty && edgeNoise(out.first)) {
      final n = out.removeAt(0);
      if (n is TitleAstText && n.text.trim().isNotEmpty) {
        removed.add(n.text.trim());
      }
      changed = true;
    }
    while (out.isNotEmpty && edgeNoise(out.last)) {
      final n = out.removeLast();
      if (n is TitleAstText && n.text.trim().isNotEmpty) {
        removed.add(n.text.trim());
      }
      changed = true;
    }

    if (!changed) {
      return (nodes: nodes, changed: false, removed: const <String>[]);
    }
    return (nodes: _compactSeparators(out), changed: true, removed: removed);
  }

  /// 括号内部：自底向上清子括号 + 按分隔符切段删关键词文本块。
  static _EvalResult _evalInner(List<TitleAstNode> children) {
    final removed = <String>[];
    var changed = false;

    // 1) 自底向上：先清子括号
    final cleaned = <TitleAstNode>[];
    for (final node in children) {
      if (node is TitleAstBracket) {
        final inner = _evalInner(node.children);
        if (inner.changed) changed = true;
        if (_isBlankChildren(inner.nodes)) {
          // 整块剥掉：内层已记录的片段被整个括号原文涵盖，不重复上报
          changed = true;
          removed.add(node.render());
          continue;
        }
        removed.addAll(inner.removed);
        if (inner.changed) {
          final rebuilt = _rebuildBracket(node, inner.nodes);
          if (rebuilt == null) {
            changed = true;
            removed.add(node.render());
            continue;
          }
          cleaned.add(rebuilt);
        } else {
          cleaned.add(node);
        }
        continue;
      }
      cleaned.add(node);
    }

    // 2) 按分隔符切段（子括号没变也要做——本层文本块可能命中关键词）
    //    分隔符归属前一段的尾巴：sepsAfter[i] 夹在 segs[i] 与 segs[i + 1]
    //    之间，所以它比 segs 少一个（首段之前根本没有分隔符）。
    final segs = <List<TitleAstNode>>[[]];
    final sepsAfter = <TitleAstSeparator>[];
    for (final n in cleaned) {
      if (n is TitleAstSeparator) {
        sepsAfter.add(n);
        segs.add([]);
      } else {
        segs.last.add(n);
      }
    }

    final keep = List<bool>.filled(segs.length, true);
    for (var i = 0; i < segs.length; i++) {
      final seg = segs[i];
      if (seg.isEmpty) {
        keep[i] = false; // 连续分隔符产生的空段
        continue;
      }
      final segText = seg.map((n) => n.render()).join();
      if (_isAudioMeta(segText)) {
        continue; // 白名单整段保留
      }

      // 删掉段内命中关键词的文本块
      final keptNodes = <TitleAstNode>[];
      var segChanged = false;
      for (final n in seg) {
        if (n is TitleAstText && _isVideoMeta(n.text)) {
          segChanged = true;
          final t = n.text.trim();
          if (t.isNotEmpty) removed.add(t);
          continue;
        }
        keptNodes.add(n);
      }
      if (!segChanged) continue; // 段里没有命中任何关键词，原样保留

      changed = true;
      // 残留只剩括号、又没有白名单 → 是挂在噪音文本上的注解，一并去掉
      // （例如「【中字（简体）】」里的「（简体）」应跟着「中字」一起走）
      final hasText = keptNodes.any((n) => n is TitleAstText && !n.isBlank);
      final hasWhitelist = _isAudioMeta(
        keptNodes.map((n) => n.render()).join(),
      );
      if (!hasText && !hasWhitelist) {
        keep[i] = false;
        for (final n in keptNodes) {
          removed.add(n.render());
        }
        continue;
      }
      segs[i] = keptNodes;
    }

    if (!changed) {
      return (nodes: children, changed: false, removed: removed);
    }

    // 3) 重组：被丢弃段两侧的分隔符收拢成相邻两段之间的一个
    //    （取 segs[i - 1] 尾巴上那个；连续分隔符时两个里补回靠后的那个，
    //    与原实现一致）。保留下来的段一定非空（空段在上面就被丢掉了），
    //    所以「out 非空」⟺「i 不是首个存活段」⟹ i ≥ 1：下标不会越界，
    //    首段之前也不会凭空补出一个分隔符。
    final out = <TitleAstNode>[];
    for (var i = 0; i < segs.length; i++) {
      if (!keep[i]) continue;
      if (out.isNotEmpty) out.add(sepsAfter[i - 1]);
      out.addAll(segs[i]);
    }
    return (nodes: out, changed: true, removed: removed);
  }

  /// 重建一个内容有改动的括号：内文裁掉首尾残留后缓存进 renderedOverride。
  /// 裁完为空 → 返回 null，调用方按整块删除处理。
  static TitleAstBracket? _rebuildBracket(
    TitleAstBracket node,
    List<TitleAstNode> newChildren,
  ) {
    final inner = newChildren.map((n) => n.render()).join();
    final trimmed = inner.replaceAll(_edgeJunk, '');
    if (trimmed.isEmpty) return null;
    return TitleAstBracket(
      node.open,
      node.close,
      newChildren,
      renderedOverride: trimmed,
    );
  }

  /// 括号是否已无实质内容（无正文文本、无存留子括号；纯分隔符也算空）。
  static bool _isBlankChildren(List<TitleAstNode> nodes) => !nodes.any(
    (n) => (n is TitleAstText && !n.isBlank) || n is TitleAstBracket,
  );

  /// 收拢相邻分隔符并丢弃首尾分隔符。
  static List<TitleAstNode> _compactSeparators(List<TitleAstNode> nodes) {
    final out = <TitleAstNode>[];
    var lastWasSep = true; // 头部分隔符直接丢弃
    for (final n in nodes) {
      if (n is TitleAstSeparator) {
        if (lastWasSep) continue;
        lastWasSep = true;
        out.add(n);
        continue;
      }
      lastWasSep = false;
      out.add(n);
    }
    while (out.isNotEmpty && out.last is TitleAstSeparator) {
      out.removeLast();
    }
    return out;
  }

  // ---------- 关键词匹配 ----------

  /// 词表编译结果：整张表压成一条 alternation，一个文本块只扫一遍
  /// （而不是对 N 个关键词各扫一遍）。字面量之间没有量词，
  /// 不存在回溯放大的问题。
  ///
  /// 刻意保持大小写敏感：正则的大小写折叠与 `String.toLowerCase()`
  /// 在个别字符上并不等价（如 `İ`），这里沿用「先归一化再匹配」的老语义，
  /// 宁可漏删也不动判定结果（见文件头的纲领）。
  static final RegExp _videoMetaPattern = _compileKeywords(videoMetaKeywords);
  static final RegExp _audioMetaPattern = _compileKeywords(audioMetaWhitelist);

  /// 词表为空时编译成永不匹配的模式：`RegExp('')` 会匹配一切，
  /// 拿它当「没有关键词」用会把每个文本块都判成命中。
  static RegExp _compileKeywords(Iterable<String> keywords) {
    if (keywords.isEmpty) return RegExp(r'[^\s\S]');
    return RegExp(keywords.map(RegExp.escape).join('|'));
  }

  /// 需要折叠的全角字符：全角 ASCII（U+FF01–U+FF5E）与全角空格（U+3000）。
  static final RegExp _fullWidthChars = RegExp('[\uFF01-\uFF5E\u3000]');

  /// 判定前的归一化：全角折半角 → 转小写。`ＭＶ`→`mv`、`Ｈｉ－Ｒｅｓ`→`hi-res`。
  ///
  /// **只用于判定，不参与渲染**：没改动的内容必须逐字保留原文写法，
  /// 所以折叠结果绝不回写 AST。
  static String _normalize(String text) {
    // 半角标题是绝大多数：先探一次，没命中就连字符串都不复制。
    final folded = _fullWidthChars.hasMatch(text)
        ? text.replaceAllMapped(_fullWidthChars, (m) {
            final c = m.group(0)!.codeUnitAt(0);
            return String.fromCharCode(c == 0x3000 ? 0x20 : c - 0xFEE0);
          })
        : text;
    return folded.toLowerCase();
  }

  /// 文本块是否含任一视频信息关键词（不区分大小写、全角折半角，子串匹配）。
  static bool _isVideoMeta(String text) =>
      _videoMetaPattern.hasMatch(_normalize(text));

  /// 文本块是否含任一音质白名单词（不区分大小写、全角折半角，子串匹配）。
  static bool _isAudioMeta(String text) =>
      _audioMetaPattern.hasMatch(_normalize(text));
}
