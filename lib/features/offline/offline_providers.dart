import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/models/offline_track.dart';

/// 当前进行中的下载进度（key → 进度）。
///
/// 服务内部是 ChangeNotifier + 进度流，这里桥接成 Provider 供 UI watch。
final offlineProgressProvider = StreamProvider<Map<String, DownloadProgress>>((
  ref,
) {
  return ref.watch(offlineCacheServiceProvider).progressStream;
});

/// 已下载曲目列表。
///
/// 订阅服务变更（新增/删除/目录切换）后重新查表，UI 只需 watch 这一个 Provider。
final offlineTracksProvider =
    AsyncNotifierProvider<OfflineTracksNotifier, List<OfflineTrack>>(
      OfflineTracksNotifier.new,
    );

class OfflineTracksNotifier extends AsyncNotifier<List<OfflineTrack>> {
  @override
  Future<List<OfflineTrack>> build() async {
    final svc = ref.watch(offlineCacheServiceProvider);
    void listener() => ref.invalidateSelf();
    svc.addListener(listener);
    ref.onDispose(() => svc.removeListener(listener));
    return svc.listAll();
  }

  /// 下载一首曲子到离线目录（**永久**保存，用户显式触发）。
  ///
  /// 取流复用 `ApiService.getAudioUrl`（离线表 → 临时缓存 → 联网），它只负责
  /// 给一个能播的本地路径、不碰永久目录；"落进离线目录 + 登记"由这里做。
  /// 因此刚播过（已在临时缓存里）的歌再点下载是瞬间完成的改名，不会重新联网。
  ///
  /// 失败抛异常由 UI 提示。
  Future<OfflineTrack> download(Music music) async {
    final svc = ref.read(offlineCacheServiceProvider);
    await svc.initialize();
    final qualityId = ref.read(settingsManagerProvider).audioQuality;

    // 已有且音质够用：不重复下载。
    final existingTrack = await svc.find(music.id, svc.effectiveCid(music));
    if (existingTrack != null &&
        svc.isQualitySufficient(existingTrack, qualityId)) {
      return existingTrack;
    }

    // cid 缺失时先补齐：离线记录按 (bvid, cid) 建索引，且补详情能拿到
    // 真实的分 P 标题，让离线文件名有意义。
    var target = music;
    if (target.cid.isEmpty) {
      final detailed = await ref
          .read(apiServiceProvider)
          .getVideoDetails(target.id);
      if (detailed.cid.isNotEmpty) target = detailed;
    }

    final audio = await ref
        .read(apiServiceProvider)
        .getAudioUrl(target, qualityId: qualityId);
    if (audio.path.isEmpty) {
      throw StateError('无法获取音频流，请检查网络或稍后重试');
    }

    final cid = svc.effectiveCid(target);
    final actualQuality = audio.qualityId.isEmpty ? qualityId : audio.qualityId;

    // 落盘：临时缓存命中时是同盘改名（瞬间），否则刚下好的那份就是源文件。
    final saved = await svc.persistFromFile(
      music: target,
      sourcePath: audio.path,
      qualityId: actualQuality,
    );
    ref.invalidateSelf();
    if (saved != null) return saved;

    // persistFromFile 返回 null 只说明"源文件不在了"（比如取流后被缓存回收/
    // 改名走）；先复查一次表，别把已经成功的落盘报成失败。
    final fallback = await svc.find(target.id, cid);
    if (fallback != null) return fallback;
    throw StateError('落盘失败，请检查离线目录是否可写');
  }

  /// 删除单条离线记录及其文件。
  Future<void> remove(OfflineTrack track) async {
    await ref.read(offlineCacheServiceProvider).remove(track.bvid, track.cid);
    ref.invalidateSelf();
  }

  /// 清空全部离线内容（文件 + 记录）。
  Future<void> clearAll() async {
    await ref.read(offlineCacheServiceProvider).clearAll();
    ref.invalidateSelf();
  }

  /// 清理记录了但文件已不在的悬挂条目。
  Future<int> purgeMissing() async {
    final removed = await ref.read(offlineCacheServiceProvider).purgeMissing();
    if (removed > 0) ref.invalidateSelf();
    return removed;
  }
}

/// 已下载曲目的 key 集合（`bvid_cid`），供列表项判断"是否已下载"。
///
/// 派生自 [offlineTracksProvider]，下载/删除后自动重算。
final offlineKeysProvider = Provider<Set<String>>((ref) {
  final tracks = ref.watch(offlineTracksProvider).value ?? const [];
  return {for (final t in tracks) t.key};
});

/// 下载一首曲子到离线目录（UI 入口，含用户提示）。
///
/// 复用 [offlineTracksProvider] 的下载链路；成功/失败都就地弹 SnackBar，
/// 调用方只需要在菜单或按钮回调里 `await` 一次。
Future<void> performOfflineDownload({
  required WidgetRef ref,
  required Music music,
  required BuildContext context,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text('开始下载「${music.title}」'),
      duration: const Duration(seconds: 2),
    ),
  );
  try {
    final track = await ref
        .read(offlineTracksProvider.notifier)
        .download(music);
    messenger.showSnackBar(
      SnackBar(
        content: Text('「${music.title}」已离线缓存到 ${track.filePath}'),
        duration: const Duration(seconds: 4),
      ),
    );
  } catch (e) {
    final message = e is StateError ? e.message : '$e';
    messenger.showSnackBar(SnackBar(content: Text('离线下载失败：$message')));
  }
}
