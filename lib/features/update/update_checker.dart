import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/features/update/models/changelog_entry.dart';

class UpdateChecker {
  static const String _remoteUrl =
      'https://raw.githubusercontent.com/NaivG/bilimusic/refs/heads/main/assets/version.json';

  static final UpdateChecker _instance = UpdateChecker._internal();

  factory UpdateChecker() => _instance;

  UpdateChecker._internal();

  bool _checked = false;

  Future<VersionCompareResult?> compareVersions() async {
    if (_checked) return null;
    _checked = true;

    try {
      // Load local version from assets
      final localVersion = await _loadLocalVersion();
      final remoteVersion = await _fetchRemoteVersion();

      if (remoteVersion == null) return null;

      // Compare versions (semantic: major.minor.patch only)
      if (_compareVersion(remoteVersion, localVersion) > 0) {
        // Remote is newer, load changelog for display
        final changelog = await _loadChangelogEntries();
        final newEntries = changelog
            .where((entry) => _compareVersion(entry.version, localVersion) > 0)
            .toList();

        return VersionCompareResult(
          localVersion: localVersion,
          remoteVersion: remoteVersion,
          newEntries: newEntries,
        );
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }

    return null;
  }

  Future<String> _loadLocalVersion() async {
    final jsonString = await rootBundle.loadString('assets/version.json');
    final Map<String, dynamic> jsonData = json.decode(jsonString);
    return jsonData['version'] as String;
  }

  Map<String, dynamic>? _cachedRemoteData;

  /// 拉取远端 version.json（UA / 超时 / 缓存写入单点实现，避免对同一
  /// [_remoteUrl] 的 GET 写两遍）。
  Future<Map<String, dynamic>?> _fetchRemoteJson() async {
    try {
      final response = await http
          .get(
            Uri.parse(_remoteUrl),
            headers: {'User-Agent': NetworkConfig.userAgent},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        _cachedRemoteData = jsonData;
        return jsonData;
      }
    } catch (e) {
      debugPrint('Failed to fetch remote version: $e');
    }
    return null;
  }

  Future<String?> _fetchRemoteVersion() async {
    final jsonData = await _fetchRemoteJson();
    final version = jsonData?['version'];
    return version is String ? version : null;
  }

  Future<List<ChangelogEntry>> _loadChangelogEntries() async {
    // Use cached remote data if available, otherwise fetch from remote
    final jsonData = _cachedRemoteData ?? await _fetchRemoteJson();
    if (jsonData == null) return [];

    final List<dynamic> changelogList = jsonData['changelog'];
    return changelogList
        .map((item) => ChangelogEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  int _compareVersion(String version1, String version2) {
    // Parse version strings like "1.4.5" or "1.4.5+46"
    final v1Parts = version1.split('+')[0].split('.');
    final v2Parts = version2.split('+')[0].split('.');

    final v1Major = int.parse(v1Parts[0]);
    final v1Minor = int.parse(v1Parts[1]);
    final v1Patch = int.parse(v1Parts[2]);

    final v2Major = int.parse(v2Parts[0]);
    final v2Minor = int.parse(v2Parts[1]);
    final v2Patch = int.parse(v2Parts[2]);

    if (v1Major != v2Major) return v1Major - v2Major;
    if (v1Minor != v2Minor) return v1Minor - v2Minor;
    return v1Patch - v2Patch;
  }
}

class VersionCompareResult {
  final String localVersion;
  final String remoteVersion;
  final List<ChangelogEntry> newEntries;

  VersionCompareResult({
    required this.localVersion,
    required this.remoteVersion,
    required this.newEntries,
  });
}
