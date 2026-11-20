/// HTML 实体还原。
library;

/// 还原文本里的 HTML 实体；认不出 / 不合法的实体原样保留。
///
/// 支持：
/// - 命名实体：`&amp;` `&lt;` `&gt;` `&quot;` `&apos;` `&nbsp;`；
/// - 十进制数字实体：`&#39;`；
/// - 十六进制数字实体：`&#x27;` / `&#X27;`（大小写 X 均可）。
///
/// `&nbsp;` 还原成普通空格：这里只用于屏上展示，不还原成 `\u00A0` 以免
/// 依赖具体字体；与搜索联想词原有的处理保持一致。
String decodeHtmlEntities(String raw) {
  if (!raw.contains('&')) return raw;
  return raw.replaceAllMapped(_entityPattern, (match) {
    final body = match.group(1)!;
    if (!body.startsWith('#')) {
      return _namedEntities[body] ?? match.group(0)!;
    }
    return _decodeNumeric(body, match.group(0)!);
  });
}

/// 命名实体表。刻意只收 B 站接口实际会产出的 XML 五个 + `nbsp`：
/// 其余字符走数字实体（如 `&#x1F600;`），不维护一张永远不全的词表。
const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

/// `&` + 实体体 + `;`。数字实体区分大小写 X，命名实体只认 ASCII 字母。
final RegExp _entityPattern = RegExp(
  r'&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z][a-zA-Z0-9]*);',
);

String _decodeNumeric(String body, String fallback) {
  final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
  final digits = body.substring(hex ? 2 : 1);
  final code = int.tryParse(digits, radix: hex ? 16 : 10);
  if (code == null || code <= 0 || code > 0x10FFFF) return fallback;
  // 代理区（U+D800–U+DFFF）不能单独成字符，还原出来只会得到坏字符串。
  if (code >= 0xD800 && code <= 0xDFFF) return fallback;
  // 大于 U+FFFF 的码点由 String.fromCharCode 编码成代理对。
  return String.fromCharCode(code);
}
