/// 统一的存储路径解析管理。
///
/// 应用里凡是「把文件落到某个用户可以改的目录」的地方（离线缓存，以及以后
/// 可能出现的导出目录、自定义缓存目录），路径来源都只有两种：用户在设置页
/// 挑的目录，或平台默认目录。这两条来源各自的坑都不一样：
///
/// - **用户挑的目录**（Android 走 SAF，`file_picker.getDirectoryPath` 把
///   tree URI 反解成一条真实绝对路径交给我们）看上去永远是一个合法路径，
///   但**能不能真写进去只有试了才知道**：Android 11+ 不开
///   `MANAGE_EXTERNAL_STORAGE` 时，裸路径只对共享媒体目录（`Music/` 等）
///   里应用自己贡献的文件放行；存储卡卷、云盘 provider（Drive / OneDrive
///   之类 DocumentsUI 里的非本地 provider）反解出来的路径要么是错的，要么
///   一写就被拒。存储卡拔掉后路径还会**暂时不存在**。
/// - **平台默认目录**（应用私有目录）永远可写，但可能先要建出来。
///
/// 所以这里把「解析」定义成**带实测的解析**：先归一化，再实写一个探针文件
/// 确认真的能落盘，最后才把它当作生效的根。写不进去就明确回退到私有目录并
/// 带上原因，而不是把失败推迟到用户点了下载才炸。
///
/// 与本仓库 `features/offline/services/offline_cache_service.dart` 的分工：
/// 本类只认路径、不认业务；它不认识 bvid、下载记录或音质档位。
///
/// 设计上刻意不解析符号链接：这里唯一的「外部输入」是用户亲自选的根目录
/// 本身，目录内的相对路径全部由应用按净化后的歌名/歌手名生成，
/// [`resolveInRoot`] 的字符串范围检查已经足以证明不会越界。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 相对路径解析后逃出了存储根。
class PathTraversalException implements Exception {
  PathTraversalException(this.message);

  final String message;

  @override
  String toString() => 'PathTraversalException: $message';
}

/// 连兜底的私有目录都用不了 —— 调用方应视作「该功能整体不可用」。
class StorageRootUnavailableException implements Exception {
  StorageRootUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'StorageRootUnavailableException: $message';
}

/// 存储根的来源，决定 UI 怎么描述它、以及失败时值不值得重试。
enum StorageRootOrigin {
  /// 用户在设置页挑的目录（Android 走 SAF）。可能因为换设备、拔存储卡、
  /// 系统回收授权等原因在某次启动后失效。
  configured,

  /// 应用私有目录：不需要任何权限、卸载才清，是永远可用的兜底根。
  appPrivate,
}

/// 一个目录的可用性探测结果。
class StorageRootProbe {
  const StorageRootProbe({
    required this.path,
    required this.exists,
    required this.isDirectory,
    required this.writable,
    this.error,
  });

  /// 归一化之后的绝对路径。
  final String path;

  /// 探测时目录是否已存在（[StorageRootProbe] 由 `create: true` 建出来的也算）。
  final bool exists;

  final bool isDirectory;

  /// 是否真的写进去过 —— 只有实写探针成功才为 true。
  final bool writable;

  /// 探测过程里捕获到的底层异常文本（没有则为 null）。
  final String? error;

  bool get usable => exists && isDirectory && writable;

  /// 不可用时的一句话原因；可用时为 null。直接可以拿去给用户看。
  String? get reason {
    if (usable) return null;
    if (error != null) return error;
    if (!exists) return '目录不存在';
    if (!isDirectory) return '不是目录';
    return '目录不可写';
  }
}

/// 最终选定的存储根。
class StorageRootDecision {
  const StorageRootDecision({
    required this.path,
    required this.origin,
    this.fallbackReason,
  });

  final String path;
  final StorageRootOrigin origin;

  /// 非空表示「配置的目录不可用，本次已回退到私有目录」，内容为原因。
  final String? fallbackReason;

  bool get isFallback => fallbackReason != null;
}

/// 路径归一化 + 根内安全解析 + 可用性实测。
///
/// 无状态、可直接 `const` 构造，测试里注入替身也只需要传另一个实例。
class StoragePathResolver {
  const StoragePathResolver();

  /// 探针文件名。写完立刻删掉；万一进程在探测中途被杀，会留在目录里，
  /// 由离线缓存的 `purgeTempFiles()` 顺手清理。
  static const String probeFileName = '.bilimusic_write_probe';

  /// 归一化：去首尾空白、折叠 `.` / `..`、统一分隔符、去掉末尾多余的分隔符。
  ///
  /// 空串原样返回（调用方据此判断「没配置」）。根目录（`/`、`C:\`）不会被
  /// 削成空串或裸盘符。
  String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final normalized = p.normalize(trimmed);
    final rootPrefix = p.rootPrefix(normalized);
    // 只在「比根还长」时才削尾分隔符，`C:\` 才不会被削成 `C:`。
    if (normalized.length > rootPrefix.length &&
        normalized.endsWith(p.separator)) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 把 [relative] 安全地接到 [root] 上，返回绝对路径。
  ///
  /// 逃出根目录时抛 [PathTraversalException]。**不要求目标已存在** ——
  /// 下载中的 `.part` 文件、还没建的子目录都属于正常输入。
  ///
  /// [relative] 若是绝对路径，会当作「相对根」处理（剥掉前导分隔符/盘符），
  /// 而不是直接采纳：调用方该传的永远是我们自己生成的相对路径。
  String resolveInRoot({required String root, required String relative}) {
    final rootPath = normalize(root);
    if (rootPath.isEmpty) {
      throw PathTraversalException('存储根为空，无法解析相对路径 "$relative"');
    }

    var rel = relative.trim();
    if (p.isAbsolute(rel)) {
      rel = rel.replaceFirst(RegExp(r'^[/\\]+'), '');
      final drive = p.rootPrefix(rel);
      if (drive.isNotEmpty &&
          !drive.startsWith('/') &&
          !drive.startsWith(r'\')) {
        rel = rel.substring(drive.length);
      }
    }

    final joined = p.normalize(p.join(rootPath, rel));
    if (!p.equals(joined, rootPath) && !p.isWithin(rootPath, joined)) {
      throw PathTraversalException('相对路径 "$relative" 逃出了存储根 "$root"');
    }
    return joined;
  }

  /// 绝对路径 → 相对根的 POSIX 路径（分隔符统一成 `/`，便于入库/跨端比较）。
  ///
  /// 等于根时返回 `.`；不在根内时返回归一化后的原始路径。
  String relativeFrom({required String root, required String absolute}) {
    final rootPath = normalize(root);
    final target = normalize(absolute);
    if (p.equals(target, rootPath)) return '.';
    if (p.isWithin(rootPath, target)) {
      return p.relative(target, from: rootPath).replaceAll(p.separator, '/');
    }
    return target.replaceAll(p.separator, '/');
  }

  /// 探测 [path] 能否真正用来落盘。
  ///
  /// [create] 为 true 时目录不存在就先建（应用私有目录用得上）；
  /// 用户挑的目录**必须传 false** —— 存储卡被拔掉时那条件路径只是暂时
  /// 不存在，这时 `create(recursive: true)` 会在内置存储上凭空造一个同名
  /// 目录，用户的下载就悄悄落到错的地方去了。
  Future<StorageRootProbe> probe(String path, {bool create = false}) async {
    final target = normalize(path);
    if (target.isEmpty) {
      return const StorageRootProbe(
        path: '',
        exists: false,
        isDirectory: false,
        writable: false,
        error: '路径为空',
      );
    }

    try {
      // 先看类型再决定要不要建：`Directory(path).exists()` 对"同名文件"返回
      // false，若先 create 就会在「路径是个文件」这种输入上抛 PathExists，
      // 把「不是目录」这个真正有用的结论淹没在底层异常里。
      var type = await FileSystemEntity.type(target);
      if (type == FileSystemEntityType.link) {
        type = await FileSystemEntity.type(target, followLinks: true);
      }

      if (type == FileSystemEntityType.notFound) {
        if (!create) {
          return StorageRootProbe(
            path: target,
            exists: false,
            isDirectory: false,
            writable: false,
          );
        }
        try {
          await Directory(target).create(recursive: true);
          type = FileSystemEntityType.directory;
        } catch (e) {
          return StorageRootProbe(
            path: target,
            exists: false,
            isDirectory: false,
            writable: false,
            error: '$e',
          );
        }
      }

      if (type != FileSystemEntityType.directory) {
        return StorageRootProbe(
          path: target,
          exists: true,
          isDirectory: false,
          writable: false,
        );
      }

      // 实写探针：Android 上 SAF 反解出来的绝对路径可能「看着像路径、
      // 写下去被拒」，只有真的写一次才能定论，不能靠权限状态推断。
      try {
        final probeFile = File(p.join(target, probeFileName));
        await probeFile.writeAsString('probe', flush: true);
        await probeFile.delete();
      } catch (e) {
        return StorageRootProbe(
          path: target,
          exists: true,
          isDirectory: true,
          writable: false,
          error: '目录不可写（$e）',
        );
      }

      return StorageRootProbe(
        path: target,
        exists: true,
        isDirectory: true,
        writable: true,
      );
    } catch (e) {
      return StorageRootProbe(
        path: target,
        exists: false,
        isDirectory: false,
        writable: false,
        error: '$e',
      );
    }
  }

  /// 在「用户配置的路径」与「平台默认目录」之间挑一个真正可用的根。
  ///
  /// - 配了且实测可写 → 用配置的；
  /// - 配了但不可用（被删/拔卡/写不进）→ 回退到默认目录，并在
  ///   [StorageRootDecision.fallbackReason] 里说明原因（**不抛异常**：
  ///   回退成功时离线功能仍然可用，只是换了地方）；
  /// - 没配 → 用默认目录（不存在就建出来）。
  ///
  /// 只有连默认目录都用不了才抛 [StorageRootUnavailableException]。
  ///
  /// [defaultPath] 是回调而不是字符串：配置的目录可用时就不必再去问
  /// `path_provider` 要默认目录了。
  Future<StorageRootDecision> resolve({
    required String? configuredPath,
    required Future<String> Function() defaultPath,
  }) async {
    final configured = configuredPath?.trim() ?? '';
    if (configured.isNotEmpty) {
      // create: false —— 见 probe 的注释，不给拔掉的存储卡「造」一个目录。
      final configuredProbe = await probe(configured);
      if (configuredProbe.usable) {
        return StorageRootDecision(
          path: configuredProbe.path,
          origin: StorageRootOrigin.configured,
        );
      }
      final fallback = await probe(await defaultPath(), create: true);
      if (!fallback.usable) {
        throw StorageRootUnavailableException(
          '配置的离线目录不可用（${configuredProbe.reason}），'
          '回退到应用私有目录也失败（${fallback.reason}）',
        );
      }
      return StorageRootDecision(
        path: fallback.path,
        origin: StorageRootOrigin.appPrivate,
        fallbackReason: '已配置的离线目录不可用（${configuredProbe.reason}），本次回退到应用私有目录',
      );
    }

    final fallback = await probe(await defaultPath(), create: true);
    if (!fallback.usable) {
      throw StorageRootUnavailableException('离线目录不可用（${fallback.reason}）');
    }
    return StorageRootDecision(
      path: fallback.path,
      origin: StorageRootOrigin.appPrivate,
    );
  }
}
