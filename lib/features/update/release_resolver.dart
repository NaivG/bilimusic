import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:bilimusic/core/network/network_config.dart';

/// GitHub Release 中的一个可下载资产
class ReleaseAsset {
  /// 资产文件名，如 bilimusic_win32_x64-1.8.0.116.zip
  final String name;

  /// 浏览器下载地址（会重定向到对象存储）
  final String url;

  /// 文件大小（字节），用于下载进度显示
  final int size;

  /// GitHub 提供的 sha256 摘要（十六进制，来自 API 的 digest 字段），可能为空
  final String? sha256;

  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
}

/// 通过 GitHub Releases API 解析最新 Release 的资产信息（下载地址、
/// sha256 摘要、大小）。
///
/// 检测更新与下载更新是两套独立操作：version.json 只负责判断"有没有新版本"，
/// 真正的下载目标与校验和在点击"立即更新"时从这里实时获取，
/// 避免 CI 发布时需要回填校验和的先后依赖问题。
class ReleaseResolver {
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/NaivG/bilimusic/releases/latest';

  /// 拉取最新 Release 的全部资产
  Future<List<ReleaseAsset>> fetchLatestAssets() async {
    final response = await http
        .get(
          Uri.parse(_latestReleaseUrl),
          headers: {
            'User-Agent': NetworkConfig.userAgent,
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 403) {
      // 未认证请求的 GitHub API 限流（60 次/小时/IP）
      throw const HttpException('GitHub API 请求受限，请稍后重试');
    }
    if (response.statusCode != 200) {
      throw HttpException('获取 Release 信息失败: HTTP ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final assets = (data['assets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    return [for (final asset in assets) _fromApiJson(asset)];
  }

  /// 从资产列表中按名称特征挑选安装包
  static ReleaseAsset? pick(
    List<ReleaseAsset> assets, {
    required String extension,
    required List<String> nameIncludes,
  }) {
    for (final asset in assets) {
      if (!asset.name.endsWith(extension)) continue;
      if (nameIncludes.every((key) => asset.name.contains(key))) {
        return asset;
      }
    }
    return null;
  }

  static ReleaseAsset _fromApiJson(Map<String, dynamic> json) {
    final digest = json['digest'] as String?;
    return ReleaseAsset(
      name: json['name'] as String? ?? '',
      url: json['browser_download_url'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      sha256: digest != null && digest.startsWith('sha256:')
          ? digest.substring('sha256:'.length)
          : null,
    );
  }
}
