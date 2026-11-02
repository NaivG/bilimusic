import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';

/// 歌单条目的导入 / 导出。
///
/// 文件里只包含歌曲条目本身，不带歌单名称、封面、标签等元信息。
class PlaylistEntriesIo {
  static const String format = 'bilimusic_playlist_entries';
  static const int formatVersion = 1;

  /// 把条目编码成便于阅读的 JSON 文本。
  static String encode(List<Music> songs) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': formatVersion,
      'songs': songs.map((music) => music.toJson()).toList(),
    });
  }

  /// 解析导入文件。
  ///
  /// 兼容三种写法：
  /// - 本类 [encode] 产出的对象（`songs` 数组）；
  /// - 根节点直接是歌曲数组；
  /// - 其它工具导出的 `entries` / `items` 数组。
  static List<Music> decode(String source) {
    // Windows 记事本等工具写出的 UTF-8 BOM 会让 jsonDecode 直接失败。
    final normalized = source.startsWith('\uFEFF')
        ? source.substring(1)
        : source;
    final Object? raw;
    try {
      raw = jsonDecode(normalized);
    } on FormatException {
      throw const PlaylistEntriesFormatException('文件不是合法的 JSON');
    }

    Object? entries;
    if (raw is List) {
      entries = raw;
    } else if (raw is Map) {
      final formatName = raw['format'];
      if (formatName != null && formatName != format) {
        throw const PlaylistEntriesFormatException('不是歌单条目文件');
      }
      entries = raw['songs'] ?? raw['entries'] ?? raw['items'];
    }
    if (entries is! List) {
      throw const PlaylistEntriesFormatException('文件里没有条目列表');
    }

    final songs = <Music>[];
    for (final entry in entries) {
      if (entry is! Map) continue;
      final json = entry.cast<String, dynamic>();
      // Music.fromJson 只接受字符串形式的时长；顺手兼容手写 / 第三方文件。
      final duration = json['duration'];
      if (duration is num) {
        json['duration'] = duration.toInt().toString();
      }
      try {
        final music = Music.fromJson(json);
        if (music.id.trim().isEmpty) continue;
        songs.add(music);
      } catch (_) {
        // 单条坏数据不影响其它条目。
      }
    }
    if (songs.isEmpty) {
      throw const PlaylistEntriesFormatException('没有可导入的条目');
    }
    return songs;
  }

  /// 让用户选择保存位置并写入文件。取消时返回 null。
  static Future<String?> exportToFile({
    required List<Music> songs,
    required String playlistName,
  }) async {
    final bytes = utf8.encode(encode(songs));
    final fileName = _buildFileName(playlistName);

    if (PlatformHelper.isMobile) {
      return FilePicker.platform.saveFile(
        dialogTitle: '导出歌单条目',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(bytes),
      );
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出歌单条目',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return null;
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// 让用户选择条目文件并解析。取消时返回 null。
  static Future<List<Music>?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入歌单条目',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: PlatformHelper.isMobile,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes != null) return decode(utf8.decode(bytes));

    final path = file.path;
    if (path == null) {
      throw const PlaylistEntriesFormatException('无法读取所选文件');
    }
    return decode(await File(path).readAsString());
  }

  static String _buildFileName(String playlistName) {
    final safeName = playlistName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final name = safeName.isEmpty ? '播放列表' : safeName;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    return '${name}_条目_$timestamp.json';
  }
}

/// 导入文件不是合法的条目文件。
class PlaylistEntriesFormatException implements Exception {
  const PlaylistEntriesFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
