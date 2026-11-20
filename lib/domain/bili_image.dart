// B 站图片 CDN 的尺寸 / 裁切变换。

/// 是否为 B 站图片域名（i0.hdslb.com、archive.biliimg.com 等）。
bool _isBiliImageHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'hdslb.com' ||
      normalized.endsWith('.hdslb.com') ||
      normalized == 'biliimg.com' ||
      normalized.endsWith('.biliimg.com');
}

/// 给 B 站图片 URL 追加尺寸 / 裁切参数。
///
/// - 空串、非 B 站域名、非绝对 URL 原样返回；
/// - 已经带 `@...` 变换的 URL 会先剥掉旧变换，保证幂等；
/// - [crop] 为 true 时追加 `_1c`，按 [width] × [height] 精确裁切；
/// - query / fragment 原样保留；
/// - 协议相对地址（`//i0.hdslb.com/...`）补成 https。
String biliImageUrl(
  String raw, {
  required int width,
  int? height,
  bool crop = true,
}) {
  final input = raw.trim();
  if (input.isEmpty || width <= 0) return input;

  var source = input;
  if (source.startsWith('//')) source = 'https:$source';

  final uri = Uri.tryParse(source);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return input;
  if (!_isBiliImageHost(uri.host)) return input;

  var path = uri.path;
  if (path.isEmpty) return input;

  // 旧 URL 可能已经带 `@672w_378h` / `@672w_672h_1c.webp`；
  // 只保留文件路径，尺寸交给本次调用重新生成。
  final transformIndex = path.lastIndexOf('@');
  if (transformIndex >= 0) path = path.substring(0, transformIndex);

  final targetHeight = height ?? width;
  final suffix = '@${width}w_${targetHeight}h${crop ? '_1c' : ''}';
  final query = uri.hasQuery ? '?${uri.query}' : '';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  return '${uri.scheme}://${uri.authority}$path$suffix$query$fragment';
}

/// 正方形封面 / 头像：宽高相同，并裁切。
String biliSquareUrl(String raw, int size) =>
    biliImageUrl(raw, width: size, height: size);

/// 16:9 横图（首页 hero、相关视频卡、舞台背景）。
String biliWideUrl(String raw, int width) =>
    biliImageUrl(raw, width: width, height: (width * 9 / 16).round());

/// UP 主 / 用户头像：头像也是图片 CDN 资源，按正方形裁切。
String biliFaceUrl(String raw, int size) => biliSquareUrl(raw, size);
