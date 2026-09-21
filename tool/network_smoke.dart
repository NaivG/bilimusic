// 网络层自检：设备自举（buvid3/4 · b_nut · bili_ticket）+ WBI 口令与签名。
//
// 用内存 jar（不注入 loader/saver），所以**既不读也不写**任何登录态：
// 拿到的票据属于一个临时匿名设备，跑完即丢。输出只有布尔值与长度，
// 不打印任何 Cookie 值（见 CLAUDE.md 硬性规则 7）。
//
//   dart run tool/network_smoke.dart
//
// 用途：B 站调整风控 / 换 WBI 口令接口时，先跑这个确认自举链路还通，
// 再去查上层业务（搜索拿不到结果、收藏夹 -403 之类的锅通常在这条链路上）。
import 'dart:io';

import 'package:bilimusic/core/network/network_config.dart';

Future<void> main() async {
  // 只要网络自举，不等本地读盘（这里也没有 loader）
  await NetworkConfig.init(waitForBootstrap: true);

  final jar = NetworkConfig.cookieJar;
  final bootstrap = NetworkConfig.bootstrap;

  stdout.writeln('bootstrap.lastError = ${bootstrap.lastError ?? '（无）'}');
  stdout.writeln(
    'buvid3 / buvid4      = '
    '${jar.contains('buvid3')} / ${jar.contains('buvid4')}',
  );
  stdout.writeln(
    '_uuid / b_lsid / b_nut = ${jar.contains('_uuid')} / '
    '${jar.contains('b_lsid')} / ${jar.contains('b_nut')}',
  );
  stdout.writeln('bili_ticket 有效     = ${bootstrap.hasTicket}');

  // 口令优先来自 GenWebTicket 顺带返回的那份；拿不到会退回 nav。
  final keys = await NetworkConfig.wbiSigner.keys();
  stdout.writeln(
    'wbi imgKey/subKey    = ${keys.imgKey.length} / ${keys.subKey.length} 字符',
  );
  stdout.writeln('wbi mixinKey 长度    = ${keys.mixinKey.length}（应为 32）');

  final signed = await NetworkConfig.wbiSigner.signQuery({'mid': '2'});
  stdout.writeln(
    '签名 query           = '
    '${signed.split('&').map((e) => e.split('=').first).join(' & ')}',
  );

  final ok =
      bootstrap.hasDeviceIdentity &&
      bootstrap.hasTicket &&
      bootstrap.lastError == null &&
      keys.mixinKey.length == 32 &&
      signed.contains('w_rid=');
  stdout.writeln(ok ? '[✓] 自举与 WBI 链路可用' : '[✗] 自举或 WBI 链路异常，看上面逐项输出');
}
