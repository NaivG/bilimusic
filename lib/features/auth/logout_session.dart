import 'package:flutter/foundation.dart';

import 'package:bilimusic/core/network/cookie_jar.dart';
import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/core/network/passport_store.dart';
import 'package:bilimusic/features/auth/user_manager.dart';

/// 仅在本地清除登录态：摘会话 Cookie、清 refresh_token 与用户缓存。
///
/// 服务端注销不可用（网络不通 / 登录态已过期被拒）时的兜底，设备标识
/// （buvid3 / b_nut / bili_ticket 等）保留。落盘由 [CookieJar] 的 saver 钩子
/// 自动完成。
Future<void> clearLocalLoginState({
  required PassportStore passportStore,
  required UserManager userManager,
  CookieJar? cookieJar,
}) async {
  // 先让登录态消失：后面两步只是清理可再生凭据，失败也不该把用户卡在登录页。
  (cookieJar ?? NetworkConfig.cookieJar).clearSession();

  try {
    await passportStore.clear();
  } catch (e) {
    debugPrint('refresh_token 清理失败: $e');
  }

  try {
    await userManager.clear();
  } catch (e) {
    debugPrint('用户缓存清理失败: $e');
  }
}
