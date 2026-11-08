import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// P0/M0 防回归：直接扫源码文本，拦下写死的视觉 / 动效字面量。
void main() {
  final root = _projectRoot();

  test('gallery 不得出现裸色值、字号、圆角、时长字面量', () {
    final dir = Directory(_join(root.path, 'lib/shared/ui/gallery'));
    expect(dir.existsSync(), isTrue, reason: '目录不存在：${dir.path}');
    final files = _dartFiles(dir);
    expect(files, isNotEmpty, reason: 'gallery 目录下没有 .dart 文件');

    const patterns = <String, Pattern>{
      'Colors.': 'Colors.',
      'fontSize:': 'fontSize:',
      'BorderRadius.circular(': 'BorderRadius.circular(',
      'Duration(milliseconds:': 'Duration(milliseconds:',
    };
    final violations = <String>[];
    for (final file in files) {
      final relative = _relative(root, file);
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        for (final entry in patterns.entries) {
          if (line.contains(entry.value)) {
            violations.add(
              '$relative:${index + 1} 命中 `${entry.key}`：${line.trim()}',
            );
          }
        }
      }
    }
    if (violations.isNotEmpty) {
      fail(
        'gallery 只允许从 Lucent token 取值，以下位置出现写死字面量：\n'
        '${violations.join('\n')}',
      );
    }
  });

  test('app_tokens 只保留几何 / 模糊常量（不含 Duration / Curve）', () {
    final file = File(_join(root.path, 'lib/shared/theme/app_tokens.dart'));
    expect(file.existsSync(), isTrue, reason: '文件不存在：${file.path}');
    final violations = <String>[];
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.contains('Duration')) {
        violations.add(
          '${_relative(root, file)}:${index + 1} 出现 Duration：'
          '${line.trim()}',
        );
      }
      if (line.contains('Curve')) {
        violations.add(
          '${_relative(root, file)}:${index + 1} 出现 Curve：'
          '${line.trim()}',
        );
      }
    }
    if (violations.isNotEmpty) {
      fail(
        '动效常量属于 BmMotion，不应留在 AppTokens：\n'
        '${violations.join('\n')}',
      );
    }
  });

  test('motion 目录里 Duration(milliseconds:) 只允许出现在 motion_tokens.dart', () {
    final dir = Directory(_join(root.path, 'lib/shared/motion'));
    expect(dir.existsSync(), isTrue, reason: '目录不存在：${dir.path}');
    final files = _dartFiles(dir);
    expect(files, isNotEmpty, reason: 'motion 目录下没有 .dart 文件');

    final violations = <String>[];
    for (final file in files) {
      if (file.uri.pathSegments.last == 'motion_tokens.dart') continue;
      final relative = _relative(root, file);
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (lines[index].contains('Duration(milliseconds:')) {
          violations.add('$relative:${index + 1}：${lines[index].trim()}');
        }
      }
    }
    if (violations.isNotEmpty) {
      fail(
        '时长字面量只允许在 motion_tokens.dart 定义，其它文件请用 BmMotion：\n'
        '${violations.join('\n')}',
      );
    }
  });
}

/// 从当前目录向上找 pubspec.yaml，定位仓库根。
Directory _projectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(_join(dir.path, 'pubspec.yaml')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('从 ${Directory.current.path} 向上找不到 pubspec.yaml');
    }
    dir = parent;
  }
}

List<File> _dartFiles(Directory dir) {
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _join(String base, String relative) {
  final normalized = relative.replaceAll('/', Platform.pathSeparator);
  return '$base${Platform.pathSeparator}$normalized';
}

String _relative(Directory root, File file) {
  final prefix = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  final path = file.path.startsWith(prefix)
      ? file.path.substring(prefix.length)
      : file.path;
  return path.replaceAll(Platform.pathSeparator, '/');
}
