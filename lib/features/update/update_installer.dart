import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_app_update/azhon_app_update.dart';
import 'package:flutter_app_update/result_model.dart';
import 'package:flutter_app_update/update_model.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:bilimusic/core/network/network_config.dart';
import 'package:bilimusic/features/update/release_resolver.dart';

/// 更新安装阶段
enum UpdatePhase { resolving, downloading, verifying, extracting, restarting }

/// 更新安装进度。[totalBytes] 为 null 时表示总量未知（进度条走不确定态）
class UpdateProgress {
  final UpdatePhase phase;
  final int receivedBytes;
  final int? totalBytes;

  const UpdateProgress(this.phase, {this.receivedBytes = 0, this.totalBytes});
}

typedef UpdateProgressCallback = void Function(UpdateProgress progress);

/// 应用内更新执行器。
///
/// - Android：委托 flutter_app_update，由系统 DownloadManager 下载并自动
///   拉起安装页，进度通过插件广播流回传；
/// - Windows/Linux：下载 zip → sha256 校验 → 解压到
///   `<app目录>/_tmpXXXXXX` → Windows 释放脚本等进程退出后换血重启，
///   Linux 直接原子覆盖后重启。
class UpdateInstaller {
  UpdateInstaller._();

  static final UpdateInstaller instance = UpdateInstaller._();

  final ReleaseResolver _resolver = ReleaseResolver();

  /// 当前平台是否支持应用内更新
  bool get isSupported =>
      Platform.isAndroid || Platform.isWindows || Platform.isLinux;

  /// 解析当前平台应下载的资产（按 CI 产物命名规则匹配）
  Future<ReleaseAsset> resolveCurrentPlatformAsset() async {
    final assets = await _resolver.fetchLatestAssets();
    ReleaseAsset? asset;
    if (Platform.isWindows) {
      asset = ReleaseResolver.pick(
        assets,
        extension: '.zip',
        nameIncludes: ['win32_x64'],
      );
    } else if (Platform.isLinux) {
      asset = ReleaseResolver.pick(
        assets,
        extension: '.zip',
        nameIncludes: ['linux-x64'],
      );
    } else if (Platform.isAndroid) {
      asset = ReleaseResolver.pick(
        assets,
        extension: '.apk',
        nameIncludes: ['android-${await _preferredAbi()}'],
      );
    }
    if (asset == null) {
      throw StateError('最新 Release 中没有当前平台的安装包');
    }
    return asset;
  }

  /// 执行完整更新流程。
  ///
  /// Android 下载在系统侧后台进行，本方法返回后由插件自动拉起安装页；
  /// Windows/Linux 成功后进程会被替换重启，本方法不会正常返回。
  /// [onError] 用于 Android 下载过程中的异步错误（此时已无法抛出）。
  Future<void> install({
    UpdateProgressCallback? onProgress,
    void Function(String message)? onError,
  }) async {
    _notify(onProgress, const UpdateProgress(UpdatePhase.resolving));
    final asset = await resolveCurrentPlatformAsset();
    if (Platform.isAndroid) {
      await _installAndroid(asset, onProgress, onError);
    } else if (Platform.isWindows) {
      await _installWindows(asset, onProgress);
    } else if (Platform.isLinux) {
      await _installLinux(asset, onProgress);
    } else {
      throw UnsupportedError('当前平台不支持应用内更新');
    }
  }

  void _notify(UpdateProgressCallback? onProgress, UpdateProgress progress) {
    onProgress?.call(progress);
  }

  // ---------------- Android ----------------

  Future<void> _installAndroid(
    ReleaseAsset asset,
    UpdateProgressCallback? onProgress,
    void Function(String message)? onError,
  ) async {
    // 下载进度与错误通过插件的广播流回传（下载在系统 DownloadManager 中进行）
    AzhonAppUpdate.dispose();
    AzhonAppUpdate.listener((result) {
      switch (result.type) {
        case ResultType.downloading:
          _notify(
            onProgress,
            UpdateProgress(
              UpdatePhase.downloading,
              receivedBytes: result.progress ?? 0,
              totalBytes: result.max,
            ),
          );
          break;
        case ResultType.done:
          _notify(onProgress, const UpdateProgress(UpdatePhase.restarting));
          AzhonAppUpdate.dispose();
          break;
        case ResultType.error:
        case ResultType.cancel:
          onError?.call(result.exception ?? '下载已取消');
          AzhonAppUpdate.dispose();
          break;
        default:
          break;
      }
    });

    final started = await AzhonAppUpdate.update(
      UpdateModel(asset.url, asset.name, 'ic_launcher', ''),
    );
    if (!started) {
      AzhonAppUpdate.dispose();
      throw StateError('无法开始下载更新');
    }
  }

  /// 按 64 位 > 32 位 > x86_64 的优先级挑选设备支持的 ABI
  Future<String> _preferredAbi() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    const priority = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
    for (final abi in priority) {
      if (androidInfo.supportedAbis.contains(abi)) return abi;
    }
    return androidInfo.supportedAbis.isNotEmpty
        ? androidInfo.supportedAbis.first
        : 'arm64-v8a';
  }

  // ---------------- 桌面端公共 ----------------

  /// 流式下载到 [file]，按约 1% 步进上报进度
  Future<void> _downloadTo(
    File file,
    ReleaseAsset asset,
    UpdateProgressCallback? onProgress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(asset.url))
        ..headers['User-Agent'] = NetworkConfig.userAgent;
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('下载更新失败: HTTP ${response.statusCode}');
      }
      final total =
          response.contentLength ?? (asset.size > 0 ? asset.size : null);
      final sink = file.openWrite();
      var received = 0;
      var lastNotified = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total == null ||
              received - lastNotified >= (total / 100).ceil()) {
            lastNotified = received;
            _notify(
              onProgress,
              UpdateProgress(
                UpdatePhase.downloading,
                receivedBytes: received,
                totalBytes: total,
              ),
            );
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  /// sha256 校验（GitHub API 未提供摘要时跳过）
  Future<void> _verifySha256(File file, ReleaseAsset asset) async {
    final expected = asset.sha256;
    if (expected == null || expected.isEmpty) return;
    final actual = sha256.convert(await file.readAsBytes()).toString();
    if (actual != expected.toLowerCase()) {
      try {
        await file.delete();
      } catch (_) {}
      throw StateError('更新包校验失败（sha256 不匹配）');
    }
  }

  /// 解压 zip 到 [targetDir]，返回真正的载荷根目录。
  ///
  /// CI 打包时 zip 内可能带有单一根目录前缀（Windows 为 `Release/`，
  /// Linux 为 `build/linux/x64/release/bundle/`），通过"仅包含单个子目录
  /// 且无文件则下钻"自动定位到包含可执行文件的那一层。
  Future<Directory> _extractPayload(File zipFile, Directory targetDir) async {
    await targetDir.create(recursive: true);
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final executablePaths = <String>[];
    for (final entry in archive) {
      if (!entry.isFile || entry.isSymbolicLink) continue;
      final segments = entry.name
          .replaceAll('\\', '/')
          .split('/')
          .where((s) => s.isNotEmpty && s != '.')
          .toList();
      if (segments.isEmpty || segments.contains('..')) continue; // 防路径穿越
      final outFile = File(p.joinAll([targetDir.path, ...segments]));
      await outFile.parent.create(recursive: true);
      final bytes = entry.readBytes();
      if (bytes == null) continue;
      await outFile.writeAsBytes(bytes, flush: true);
      // 恢复 zip 内标记了属主可执行位的文件（仅 Unix 权限体系有意义）
      if (!Platform.isWindows && entry.unixPermissions & 0x40 != 0) {
        executablePaths.add(outFile.path);
      }
    }
    if (executablePaths.isNotEmpty) {
      await Process.run('chmod', ['+x', ...executablePaths]);
    }
    return _findPayloadRoot(targetDir);
  }

  Directory _findPayloadRoot(Directory dir) {
    var current = dir;
    while (true) {
      final children = current.listSync();
      final dirs = children.whereType<Directory>().toList();
      if (children.whereType<File>().isEmpty && dirs.length == 1) {
        current = dirs.first;
      } else {
        return current;
      }
    }
  }

  /// 应用安装目录（可执行文件所在目录）
  Directory get _appDir => File(Platform.resolvedExecutable).parent;

  String _newTempDirName() {
    final rand = Random.secure().nextInt(0xFFFFFF);
    return '_tmp'
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${rand.toRadixString(36)}';
  }

  /// 清理上次更新失败遗留的临时目录
  Future<void> _cleanupStaleTempDirs(Directory appDir) async {
    try {
      for (final child in appDir.listSync()) {
        if (child is Directory && p.basename(child.path).startsWith('_tmp')) {
          try {
            await child.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 下载 → 校验 → 解压到 `<app目录>/_tmpXXXXXX`。
  /// 返回 (载荷根目录, _tmp 根目录)：CI 打包的 zip 自带单一根目录前缀，
  /// 载荷根目录是下钻到包含可执行文件的那一层，与 _tmp 根目录可能不同。
  Future<(Directory, Directory)> _downloadExtractToAppDir(
    ReleaseAsset asset,
    UpdateProgressCallback? onProgress,
  ) async {
    final appDir = _appDir;
    await _cleanupStaleTempDirs(appDir);
    final zipFile = File(
      p.join(
        Directory.systemTemp.path,
        'bilimusic_update_${DateTime.now().millisecondsSinceEpoch}.zip',
      ),
    );
    try {
      await _downloadTo(zipFile, asset, onProgress);
      _notify(onProgress, const UpdateProgress(UpdatePhase.verifying));
      await _verifySha256(zipFile, asset);
      _notify(onProgress, const UpdateProgress(UpdatePhase.extracting));
      final tempRoot = Directory(p.join(appDir.path, _newTempDirName()));
      final payload = await _extractPayload(zipFile, tempRoot);
      return (payload, tempRoot);
    } finally {
      try {
        if (await zipFile.exists()) await zipFile.delete();
      } catch (_) {}
    }
  }

  // ---------------- Windows ----------------

  Future<void> _installWindows(
    ReleaseAsset asset,
    UpdateProgressCallback? onProgress,
  ) async {
    final appDir = _appDir;
    final (payload, tempRoot) = await _downloadExtractToAppDir(
      asset,
      onProgress,
    );
    final exeName = p.basename(Platform.resolvedExecutable);

    // 释放自动更新脚本：杀掉进程 → 等待句柄释放 → 换血 → 清理临时目录 →
    // 拉起新版本 → 自删除。
    // 参数: %1=载荷目录 %2=应用目录 %3=exe 文件名 %4=_tmp 根目录。
    // 脚本内容保持纯 ASCII，路径经命令行参数传入，避免批处理编码问题；
    // 末行 (goto) 2>nul & del 使脚本自删除后干净退出（exit 0）。
    final script = File(
      p.join(
        Directory.systemTemp.path,
        'bilimusic_update_${DateTime.now().millisecondsSinceEpoch}.cmd',
      ),
    );
    await script.writeAsString('''
@echo off
taskkill /f /im "%~3" >nul 2>&1
timeout /T 3 /NOBREAK >nul
robocopy "%~1" "%~2" /E /MOVE /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
if exist "%~4" rd /s /q "%~4"
cd /d "%~2"
start "" "%~3"
(goto) 2>nul & del "%~f0"
''', flush: true);

    _notify(onProgress, const UpdateProgress(UpdatePhase.restarting));
    await Process.start('cmd.exe', [
      '/c',
      script.path,
      payload.path,
      appDir.path,
      exeName,
      tempRoot.path,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  // ---------------- Linux ----------------

  Future<void> _installLinux(
    ReleaseAsset asset,
    UpdateProgressCallback? onProgress,
  ) async {
    final appDir = _appDir;
    final (payload, _) = await _downloadExtractToAppDir(asset, onProgress);

    // Linux 允许替换运行中的文件：rename 为原子覆盖，旧 inode 由运行中的
    // 进程继续持有，进程退出后自动释放
    final files = payload.listSync(recursive: true).whereType<File>().toList();
    for (final file in files) {
      final target = p.join(
        appDir.path,
        p.relative(file.path, from: payload.path),
      );
      await Directory(p.dirname(target)).create(recursive: true);
      await file.rename(target);
    }
    try {
      await payload.delete(recursive: true);
    } catch (_) {}

    _notify(onProgress, const UpdateProgress(UpdatePhase.restarting));
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      workingDirectory: appDir.path,
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
