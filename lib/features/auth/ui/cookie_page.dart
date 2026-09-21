import 'package:bilimusic/shared/widgets/auto_appbar.dart';
import 'package:flutter/material.dart';
import 'package:bilimusic/core/network/network_config.dart';

/// Cookie 信息页。
///
/// 展示的是 [NetworkConfig.cookieJar] 里的完整 Cookie（不再是扁平 name→value）：
/// 每条都带自己生效的域名 / 路径与过期时间，登出只摘会话 Cookie、设备标识留在盘上。
class CookiePage extends StatelessWidget {
  const CookiePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cookies = NetworkConfig.cookieJar.all;

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: 'Cookie 信息'),
      backgroundColor: Colors.transparent,
      bottomSheet: Container(
        alignment: Alignment.bottomCenter,
        margin: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.1,
        child: Text(
          'Cookie 信息只在本地保存，不会上传到服务器，除非你知道你在做什么，否则请勿分享给任何人。',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ),
      body: cookies.isEmpty
          ? const Center(
              child: Text(
                '暂无 Cookie 信息',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: cookies.length,
              itemBuilder: (context, index) {
                final cookie = cookies[index];
                return ListTile(
                  title: Text(cookie.name),
                  subtitle: Text(
                    '${cookie.value}\n'
                    '${cookie.domain}${cookie.path} · '
                    '${cookie.expiresAt == null ? '会话' : '至 ${cookie.expiresAt!.toLocal()}'}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}
