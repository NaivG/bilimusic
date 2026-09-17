import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:bilimusic/core/storage/storage_path_resolver.dart';

/// [StoragePathResolver] 的纯逻辑单测。
///
/// 这里是"离线缓存到底落在哪个目录"的唯一决策点，也是最容易静默出错的地方：
/// 相对路径越界、把拔掉的存储卡路径当成有效根、探测不彻底导致下载时才失败。
void main() {
  const resolver = StoragePathResolver();
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('storage_path_test');
  });

  tearDown(() async {
    if (temp.existsSync()) {
      await temp.delete(recursive: true);
    }
  });

  group('normalize', () {
    test('去掉末尾多余的分隔符，折叠 . 与 ..', () {
      expect(
        resolver.normalize(p.join(temp.path, 'a', 'b') + p.separator),
        p.join(temp.path, 'a', 'b'),
      );
      expect(
        resolver.normalize(p.join(temp.path, 'a', '..', 'b')),
        p.join(temp.path, 'b'),
      );
    });

    test('空串 / 纯空白返回空串（调用方据此判断"没配置"）', () {
      expect(resolver.normalize(''), '');
      expect(resolver.normalize('   '), '');
    });

    test('根目录不会被削成空串', () {
      expect(
        resolver.normalize(p.rootPrefix(temp.path)),
        p.rootPrefix(temp.path),
      );
    });
  });

  group('resolveInRoot', () {
    test('相对路径接到根上（子目录层层深入）', () {
      final out = resolver.resolveInRoot(
        root: temp.path,
        relative: p.join('周', '歌.m4a'),
      );
      expect(out, p.join(temp.path, '周', '歌.m4a'));
    });

    test('目标还不存在也不抛异常（下载中的 .part 就是这种）', () {
      expect(
        () => resolver.resolveInRoot(root: temp.path, relative: 'x.part'),
        returnsNormally,
      );
    });

    test('.. 逃出根时抛 PathTraversalException', () {
      expect(
        () => resolver.resolveInRoot(
          root: temp.path,
          relative: p.join('..', 'evil.m4a'),
        ),
        throwsA(isA<PathTraversalException>()),
      );
      expect(
        () => resolver.resolveInRoot(
          root: temp.path,
          relative: p.join('a', '..', '..', '..', 'evil.m4a'),
        ),
        throwsA(isA<PathTraversalException>()),
      );
    });

    test('绝对形式的 relative 被当作"相对根"而不是直接采纳', () {
      final escaped = p.join(p.rootPrefix(temp.path), 'etc', 'passwd');
      final out = resolver.resolveInRoot(root: temp.path, relative: escaped);
      expect(p.isWithin(temp.path, out), isTrue, reason: '必须仍被约束在根内');
    });

    test('根为空时抛 PathTraversalException', () {
      expect(
        () => resolver.resolveInRoot(root: '  ', relative: 'a.m4a'),
        throwsA(isA<PathTraversalException>()),
      );
    });
  });

  group('relativeFrom', () {
    test('根内路径转成 POSIX 相对路径', () {
      expect(
        resolver.relativeFrom(
          root: temp.path,
          absolute: p.join(temp.path, '周', '歌.m4a'),
        ),
        '周/歌.m4a',
      );
    });

    test('等于根时返回 "."', () {
      expect(resolver.relativeFrom(root: temp.path, absolute: temp.path), '.');
    });

    test('根之外的原样返回（归一化 + 统一分隔符）', () {
      final outside = p.join(p.dirname(temp.path), 'other', 'a.m4a');
      expect(
        resolver.relativeFrom(root: temp.path, absolute: outside),
        outside.replaceAll(p.separator, '/'),
      );
    });
  });

  group('probe', () {
    test('已存在的可写目录探测通过，且不留下探针文件', () async {
      final probe = await resolver.probe(temp.path);
      expect(probe.usable, isTrue);
      expect(probe.reason, isNull);
      expect(probe.isDirectory, isTrue);
      expect(temp.listSync(), isEmpty, reason: '探针文件写完必须删掉，不能污染用户的离线目录');
    });

    test('目录不存在且 create=false 时不建目录（存储卡拔掉的场景）', () async {
      final missing = p.join(temp.path, 'ejected-sd', 'Music');
      final probe = await resolver.probe(missing, create: false);
      expect(probe.usable, isFalse);
      expect(probe.reason, '目录不存在');
      expect(Directory(missing).existsSync(), isFalse, reason: '绝不能凭空造目录');
    });

    test('目录不存在且 create=true 时建出来并探测通过', () async {
      final missing = p.join(temp.path, 'private', 'Music');
      final probe = await resolver.probe(missing, create: true);
      expect(probe.usable, isTrue);
      expect(Directory(missing).existsSync(), isTrue);
    });

    test('路径是一个文件而不是目录时探测失败', () async {
      final file = File(p.join(temp.path, 'not-a-dir'));
      await file.writeAsString('x');
      final probe = await resolver.probe(file.path, create: true);
      expect(probe.usable, isFalse);
      expect(probe.reason, '不是目录');
    });

    test('空路径探测失败并给出可读原因', () async {
      final probe = await resolver.probe('   ');
      expect(probe.usable, isFalse);
      expect(probe.reason, '路径为空');
    });
  });

  group('resolve（配置根 vs 私有兜底）', () {
    test('配置的目录可写时直接采用，不碰默认目录', () async {
      var defaultAsked = false;
      final decision = await resolver.resolve(
        configuredPath: '${temp.path}${p.separator}',
        defaultPath: () async {
          defaultAsked = true;
          return p.join(temp.path, 'unused');
        },
      );
      expect(decision.origin, StorageRootOrigin.configured);
      expect(decision.path, temp.path, reason: '返回的应是归一化后的路径');
      expect(decision.isFallback, isFalse);
      expect(defaultAsked, isFalse, reason: '配置可用时不该白问一次默认目录');
    });

    test('配置的目录不可用时回退到私有目录，并带上原因', () async {
      final missing = p.join(temp.path, 'ejected-sd', 'Music');
      final fallbackDir = p.join(temp.path, 'private', 'Music');
      final decision = await resolver.resolve(
        configuredPath: missing,
        defaultPath: () async => fallbackDir,
      );
      expect(decision.origin, StorageRootOrigin.appPrivate);
      expect(decision.path, fallbackDir);
      expect(decision.isFallback, isTrue);
      expect(decision.fallbackReason, contains('目录不存在'));
      expect(Directory(fallbackDir).existsSync(), isTrue);
      expect(Directory(missing).existsSync(), isFalse);
    });

    test('没配置时用默认目录（不存在就建）', () async {
      final fallbackDir = p.join(temp.path, 'private', 'offline_music');
      for (final configured in <String?>[null, '', '   ']) {
        final decision = await resolver.resolve(
          configuredPath: configured,
          defaultPath: () async => fallbackDir,
        );
        expect(decision.origin, StorageRootOrigin.appPrivate);
        expect(decision.path, fallbackDir);
        expect(decision.fallbackReason, isNull);
      }
    });

    test('连默认目录都建不出来时抛 StorageRootUnavailableException', () async {
      // 把一个普通文件当成"父目录"，create(recursive: true) 必定失败。
      final blocker = File(p.join(temp.path, 'blocker'));
      await blocker.writeAsString('x');
      await expectLater(
        resolver.resolve(
          configuredPath: p.join(temp.path, 'nope'),
          defaultPath: () async => p.join(blocker.path, 'Music'),
        ),
        throwsA(isA<StorageRootUnavailableException>()),
      );
    });
  });
}
