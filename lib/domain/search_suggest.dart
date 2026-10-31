/// 搜索联想词。
class SearchSuggest {
  /// 提交搜索时使用的关键词（部分条目的 value 会带空格/运算符，以它为准）。
  final String value;

  /// 展示文本：已剥掉高亮标签并还原常见 HTML 实体。
  final String name;

  const SearchSuggest({required this.value, required this.name});

  /// 从接口的单个 tag 对象解析；字段缺失或无效时返回 null。
  static SearchSuggest? fromTag(Object? raw) {
    if (raw is! Map) return null;
    final value = raw['value']?.toString().trim() ?? '';
    final term = raw['term']?.toString().trim() ?? '';
    final name = raw['name']?.toString() ?? '';
    final display = stripSuggestMarkup(name).trim();
    final keyword = value.isNotEmpty
        ? value
        : (term.isNotEmpty ? term : display);
    if (keyword.isEmpty) return null;
    // 与搜索无关的操作类条目（深链 / 网页跳转）不作为联想词。
    if (keyword.startsWith('bilibili://') || keyword.startsWith('http')) {
      return null;
    }
    return SearchSuggest(
      value: keyword,
      name: display.isNotEmpty ? display : keyword,
    );
  }

  /// 解析整个 suggest 响应里的 `result.tag[]`，按返回顺序去重。
  static List<SearchSuggest> listFromResponse(Map<String, dynamic> json) {
    final result = json['result'];
    if (result is! Map) return const [];
    final tags = result['tag'];
    if (tags is! List) return const [];

    final items = <SearchSuggest>[];
    final seen = <String>{};
    for (final tag in tags) {
      final item = fromTag(tag);
      if (item == null || !seen.add(item.value)) continue;
      items.add(item);
    }
    return items;
  }
}

final RegExp _tagPattern = RegExp(r'<[^>]*>');
final RegExp _entityPattern = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);');

/// 剥掉联想词 `name` 里的高亮标签，并还原常见 HTML 实体。
String stripSuggestMarkup(String raw) {
  if (raw.isEmpty) return raw;
  if (!raw.contains('<') && !raw.contains('&')) return raw;

  final withoutTags = raw.replaceAll(_tagPattern, '');
  return withoutTags.replaceAllMapped(_entityPattern, (match) {
    final entity = match.group(1)!;
    switch (entity) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      case 'nbsp':
        return ' ';
    }
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      final code = int.tryParse(entity.substring(2), radix: 16);
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    if (entity.startsWith('#')) {
      final code = int.tryParse(entity.substring(1));
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    return match.group(0)!;
  });
}
