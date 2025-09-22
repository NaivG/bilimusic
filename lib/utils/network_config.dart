// 统一网络请求配置
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:http/http.dart' as http;

class NetworkConfig {
  static Map<String, String> _biliHeaders = {};
  static Map<String, String> _cookies = {};

  static Map<String, String> get biliHeaders {
    // 创建 headers 副本
    final headers = Map<String, String>.from(_biliHeaders);
    
    // 将 cookies 转换为标准的字符串格式
    if (_cookies.isNotEmpty) {
      final cookieString = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      headers['Cookie'] = cookieString;
    }
    
    return headers;
  }

  static void setBiliHeaders(Map<String, String> headers) {
    _biliHeaders = Map<String, String>.from(headers);
  }

  static void updateBiliHeaders(Map<String, String> headers) {
    _biliHeaders.addAll(headers);
  }

  static Map<String, String> get cookies {
    return Map<String, String>.from(_cookies);
  }

  static void setCookies(Map<String, String> cookies) {
    _cookies = Map<String, String>.from(cookies);
    // 同时更新 SharedPreferences
    _saveCookiesToPrefs();
  }

  static void updateCookies(Map<String, String> cookies) {
    _cookies.addAll(cookies);
    // 同时更新 SharedPreferences
    _saveCookiesToPrefs();
  }

  static Future<void> _saveCookiesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_cookies.isNotEmpty) {
      final jsonString = json.encode(_cookies);
      await prefs.setString('cookies', jsonString);
    }
  }

  static Future<void> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 配置默认headers
    _biliHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:141.0) Gecko/20100101 Firefox/141.0',
      'Referer': 'https://www.bilibili.com',
      'access-control-allow-origin': 'https://www.bilibili.com',
    };

    // 读取并解析 cookies
    var cookiesJson = prefs.getString('cookies');
    if (cookiesJson != null && cookiesJson.isNotEmpty) {
      try {
        // 尝试解析 JSON 格式的 cookies
        final cookiesMap = json.decode(cookiesJson);
        if (cookiesMap is Map) {
          _cookies = Map<String, String>.from(cookiesMap.map((key, value) => MapEntry(key.toString(), value.toString())));
        } else {
          // 如果不是 JSON 格式，按照字符串处理
          _parseCookiesString(cookiesJson);
        }
      } catch (e) {
        // JSON 解析失败，按照字符串处理
        _parseCookiesString(cookiesJson);
      }
    }

    // 如果 cookies 为空，则获取 buvid3 和 buvid4
    if (_cookies.isEmpty) {
      final buvids = await _fetchBuvids();
      _cookies['buvid3'] = buvids['b_3'] ?? '';
      _cookies['buvid4'] = buvids['b_4'] ?? '';
      await _saveCookiesToPrefs();
    }
  }

  static void _parseCookiesString(String cookiesString) {
    final cookies = <String, String>{};
    final pairs = cookiesString.split(';');
    
    for (var pair in pairs) {
      final trimmed = pair.trim();
      if (trimmed.isNotEmpty) {
        final parts = trimmed.split('=');
        if (parts.length == 2) {
          cookies[parts[0].trim()] = parts[1].trim();
        }
      }
    }
    
    _cookies = cookies;
  }

  static Future<Map<String, String>> _fetchBuvids() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:141.0) Gecko/20100101 Firefox/141.0',
          'Referer': 'https://www.bilibili.com'
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json.containsKey('data') &&
            json['data'] is Map &&
            json['data'].containsKey('b_3') &&
            json['data'].containsKey('b_4')) {
          final buvid3 = json['data']['b_3'] as String?;
          final buvid4 = json['data']['b_4'] as String?;
          return {
            'b_3': buvid3 ?? '',
            'b_4': buvid4 ?? '',
          };
        } else {
          throw const FormatException('Invalid response format: missing data, b_3 or b_4 field');
        }
      } else if (response.statusCode == 429) {
        // 处理速率限制并返回重试的Future
        return Future.delayed(const Duration(seconds: 5), _fetchBuvids);
      } else {
        throw HttpException('Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      // 添加错误日志
      if (kDebugMode) {
        print('Failed to fetch buvids: $e');
      }
      return {'b_3': '', 'b_4': ''};
    }
  }
}