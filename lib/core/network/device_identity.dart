import 'dart:math';

/// 设备标识相关的本地生成逻辑。
///
/// B 站 Web 端匹配的"设备指纹"Cookie。
///
/// `_uuid` / `b_lsid` 属于 Web 端自己生成、随请求带上的标识，
/// 这里按公开实现里常见的形态生成（16 进制 UUID + 5 位随机 + `infoc` 后缀）。
/// 它们缺失不影响主流程，因此只作尽力对齐，不作正确性保证。
class DeviceIdentity {
  const DeviceIdentity._();

  static final Random _random = Random.secure();

  /// `_uuid`：8-4-4-4-12 的大写十六进制 + 5 位随机数 + `infoc`。
  ///
  /// 形态与接口下发的 buvid3（如 `D9656DA8-9BEF-F464-5B72-C4849AFD336379044infoc`）一致。
  static String uuid() {
    final buffer = StringBuffer(_hex(8))
      ..write('-')
      ..write(_hex(4))
      ..write('-')
      ..write('4')
      ..write(_hex(3))
      ..write('-')
      // variant 位固定为 8/9/a/b 之一
      ..write('89ab'[_random.nextInt(4)])
      ..write(_hex(3))
      ..write('-')
      ..write(_hex(12));
    final suffix = _random.nextInt(90000) + 10000; // 5 位随机数
    return '${buffer.toString().toUpperCase()}$suffix'
        'infoc';
  }

  /// `b_lsid`：16 位大写十六进制，前 8 位取自毫秒时间戳（模拟 Web 端实现）。
  static String bLsid({DateTime? now}) {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final head = (stamp & 0xFFFFFFFF)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(8, '0');
    return '$head${_hex(8).toUpperCase()}';
  }

  /// `b_nut`：UNIX 秒级时间戳。
  static int unixSeconds({DateTime? now}) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

  /// 一组可以不依赖服务端就写进 Cookie 的标识。
  static Map<String, String> localIdentityCookies({DateTime? now}) {
    final stamp = now ?? DateTime.now();
    return {
      '_uuid': uuid(),
      'b_lsid': bLsid(now: stamp),
      'b_nut': '${unixSeconds(now: stamp)}',
    };
  }

  static String _hex(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
