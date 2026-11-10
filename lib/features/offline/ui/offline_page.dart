import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/domain/offline_track.dart';
import 'package:bilimusic/features/offline/logic/offline_track_music.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 离线缓存页：列出已下载到本地的曲目，支持播放、删除与清空。
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(offlineTracksProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AutoAppBar.generateAppBar(
        context: context,
        title: '离线缓存',
        actions: [
          IconButton(
            tooltip: '刷新并清理失效记录',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(context, ref),
          ),
        ],
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _buildError(context, ref, error),
        data: (tracks) {
          if (tracks.isEmpty) return _buildEmpty(context, ref);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context, ref, tracks)),
              SliverToBoxAdapter(child: _buildListHeader(context, tracks)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      _buildTrackRow(context, ref, tracks[index], index),
                  childCount: tracks.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
              // 给竖屏浮动的迷你播放器 / Dock 让位；横屏该值即底部安全区。
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.paddingOf(context).bottom),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = ref.watch(offlineCacheServiceProvider);
    final rootError = service.rootError;

    return Center(
      child: SingleChildScrollView(
        // 给竖屏浮动的迷你播放器 / Dock 让位；横屏该值即底部安全区。
        padding: EdgeInsets.fromLTRB(
          32,
          32,
          32,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_outlined,
              size: 80,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              '还没有离线音乐',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在歌曲菜单选择「离线缓存」，或在歌单「更多」菜单中选择'
              '「离线缓存全部」，下载完成后会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (rootError != null) ...[
              const SizedBox(height: 12),
              Text(
                rootError,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _refresh(context, ref),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              '加载离线缓存失败',
              style: TextStyle(fontSize: 18, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => ref.invalidate(offlineTracksProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    List<OfflineTrack> tracks,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = ref.watch(offlineCacheServiceProvider);
    final totalBytes = tracks.fold<int>(
      0,
      (sum, track) => sum + track.fileSize,
    );
    final directory = service.baseDirectory;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primary,
                      colorScheme.tertiary.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Icon(
                  Icons.download_done_rounded,
                  size: 36,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本地已缓存 ${tracks.length} 首',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '共占用 ${_formatBytes(totalBytes)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (directory != null && directory.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: directory,
                        child: Text(
                          '存放于 $directory',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _playAll(context, ref, tracks),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('播放全部'),
              ),
              OutlinedButton.icon(
                onPressed: () => _playAll(context, ref, tracks, shuffle: true),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('随机播放'),
              ),
              OutlinedButton.icon(
                onPressed: () => _clearAll(context, ref, tracks),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('清空缓存'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(
                    color: colorScheme.error.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader(BuildContext context, List<OfflineTrack> tracks) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Text(
            '已缓存曲目',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            '${tracks.length} 首',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(
    BuildContext context,
    WidgetRef ref,
    OfflineTrack track,
    int index,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isPlaying = _isTrackPlaying(track, ref.watch(currentMusicProvider));
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final qualityLabel = offlineQualityLabel(track.qualityId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playTrack(context, ref, track),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: isPlaying
                    ? Icon(
                        Icons.graphic_eq,
                        size: 18,
                        color: colorScheme.primary,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isPlaying
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist.trim().isEmpty ? '未知艺术家' : track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isWide) ...[
                const SizedBox(width: 12),
                Text(
                  _formatDate(track.downloadedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (qualityLabel != null) ...[
                const SizedBox(width: 12),
                _QualityBadge(label: qualityLabel),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: isWide ? 68 : 58,
                child: Text(
                  _formatBytes(track.fileSize),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '删除缓存',
                onPressed: () => _deleteTrack(context, ref, track),
                icon: const Icon(Icons.delete_outline, size: 20),
                color: colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isTrackPlaying(OfflineTrack track, Music? current) {
    if (current == null || current.id != track.bvid) return false;
    if (current.cid.isEmpty || track.cid.isEmpty) return true;
    return current.cid == track.cid;
  }

  Future<void> _playTrack(
    BuildContext context,
    WidgetRef ref,
    OfflineTrack track,
  ) async {
    final music = musicFromOfflineTrack(track);
    try {
      await ref.read(playlistCommandsProvider.notifier).addToPlaylist(music);
      await ref.read(playbackCommandsProvider.notifier).playMusic(music);
    } catch (e) {
      if (context.mounted) _showMessage(context, '播放失败：$e');
    }
  }

  Future<void> _playAll(
    BuildContext context,
    WidgetRef ref,
    List<OfflineTrack> tracks, {
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    final musics = tracks.map(musicFromOfflineTrack).toList();
    if (shuffle) musics.shuffle(Random());

    try {
      await ref.read(playbackCommandsProvider.notifier).clearPlaylist();
      await ref
          .read(playlistCommandsProvider.notifier)
          .addAllToPlaylist(musics);
      await ref.read(playbackCommandsProvider.notifier).playMusic(musics.first);
    } catch (e) {
      if (context.mounted) _showMessage(context, '播放失败：$e');
    }
  }

  Future<void> _deleteTrack(
    BuildContext context,
    WidgetRef ref,
    OfflineTrack track,
  ) async {
    final isCurrent = _isTrackPlaying(track, ref.read(currentMusicProvider));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除离线缓存'),
        content: Text(
          isCurrent
              ? '「${track.title}」正在播放，删除后将从本地移除并停止播放。'
              : '将从本地删除「${track.title}」及其音频文件，该操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      if (isCurrent) {
        await ref.read(playbackCommandsProvider.notifier).stop();
      }
      await ref.read(offlineTracksProvider.notifier).remove(track);
      if (context.mounted) _showMessage(context, '已删除「${track.title}」');
    } catch (e) {
      if (context.mounted) _showMessage(context, '删除失败：$e');
    }
  }

  Future<void> _clearAll(
    BuildContext context,
    WidgetRef ref,
    List<OfflineTrack> tracks,
  ) async {
    final totalBytes = tracks.fold<int>(
      0,
      (sum, track) => sum + track.fileSize,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空离线缓存'),
        content: Text(
          '将删除本地已缓存的 ${tracks.length} 首音乐'
          '（${_formatBytes(totalBytes)}）及其记录，该操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(playbackCommandsProvider.notifier).stop();
      await ref.read(offlineTracksProvider.notifier).clearAll();
      if (context.mounted) _showMessage(context, '离线缓存已清空');
    } catch (e) {
      if (context.mounted) _showMessage(context, '清空失败：$e');
    }
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      final removed = await ref
          .read(offlineTracksProvider.notifier)
          .purgeMissing();
      ref.invalidate(offlineTracksProvider);
      if (context.mounted) {
        _showMessage(context, removed > 0 ? '已清理 $removed 条失效记录' : '已刷新离线缓存');
      }
    } catch (e) {
      if (context.mounted) _showMessage(context, '刷新失败：$e');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  static String _formatDate(DateTime time) {
    if (time.millisecondsSinceEpoch <= 0) return '--';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 || value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
