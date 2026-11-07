import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/models/offline_track.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';

/// 批量离线缓存进度对话框。
///
/// 打开后立即开始串行下载 [songs]，已缓存且音质足够的曲目会自动跳过。
/// 运行期间不可直接关闭，点「取消」会在当前曲目下载完成后停止。
class OfflineBatchDownloadDialog extends ConsumerStatefulWidget {
  final List<Music> songs;
  final String? playlistName;

  const OfflineBatchDownloadDialog({
    super.key,
    required this.songs,
    this.playlistName,
  });

  @override
  ConsumerState<OfflineBatchDownloadDialog> createState() =>
      _OfflineBatchDownloadDialogState();
}

class _OfflineBatchDownloadDialogState
    extends ConsumerState<OfflineBatchDownloadDialog> {
  int _current = 0;
  int _total = 0;
  Music? _currentMusic;
  bool _cancelRequested = false;
  bool _running = true;
  OfflineBatchResult? _result;
  String? _fatalError;

  @override
  void initState() {
    super.initState();
    _total = widget.songs.length;
    _start();
  }

  Future<void> _start() async {
    try {
      final result = await ref
          .read(offlineTracksProvider.notifier)
          .downloadMany(
            widget.songs,
            onProgress: (current, total, music) {
              if (!mounted) return;
              setState(() {
                _current = current;
                _total = total;
                _currentMusic = music;
              });
            },
            shouldCancel: () => _cancelRequested,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
        _currentMusic = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fatalError = e is StateError ? e.message : '$e';
        _running = false;
        _currentMusic = null;
      });
    }
  }

  void _requestCancel() {
    if (!_running || _cancelRequested) return;
    setState(() => _cancelRequested = true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _running
        ? '正在离线缓存'
        : _fatalError != null
        ? '离线缓存失败'
        : _result?.cancelled == true
        ? '已停止离线缓存'
        : '离线缓存完成';

    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              _running
                  ? Icons.downloading
                  : _fatalError != null
                  ? Icons.error_outline
                  : Icons.download_done,
              color: _running
                  ? colorScheme.primary
                  : _fatalError != null
                  ? colorScheme.error
                  : colorScheme.tertiary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.playlistName != null &&
                  widget.playlistName!.isNotEmpty) ...[
                Text(
                  widget.playlistName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_running) _buildRunning(colorScheme),
              if (!_running) _buildResult(colorScheme),
            ],
          ),
        ),
        actions: [
          if (_running)
            TextButton(
              onPressed: _cancelRequested ? null : _requestCancel,
              child: Text(_cancelRequested ? '正在取消…' : '取消'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
        ],
      ),
    );
  }

  Widget _buildRunning(ColorScheme colorScheme) {
    final base = (_current - 1).clamp(0, _total);
    final value = _total > 0 ? (base / _total).clamp(0.0, 1.0) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: value, minHeight: 6),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '正在缓存 $_current / $_total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _currentMusic?.title ?? '准备中…',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        if (_cancelRequested) ...[
          const SizedBox(height: 12),
          Text(
            '将在当前曲目下载完成后停止',
            style: TextStyle(fontSize: 12, color: colorScheme.tertiary),
          ),
        ],
      ],
    );
  }

  Widget _buildResult(ColorScheme colorScheme) {
    final result = _result;
    if (_fatalError != null) {
      return Text(
        '批量缓存失败：$_fatalError',
        style: TextStyle(fontSize: 13, color: colorScheme.error),
      );
    }
    if (result == null) return const SizedBox.shrink();

    final parts = <String>[
      '新增 ${result.downloaded} 首',
      '跳过 ${result.skipped} 首',
      if (result.failed > 0) '失败 ${result.failed} 首',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: 1, minHeight: 6),
        ),
        const SizedBox(height: 14),
        Text(
          parts.join(' · '),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        if (result.cancelled) ...[
          const SizedBox(height: 6),
          Text(
            '已取消，剩余 ${widget.songs.length - result.processed} 首未处理',
            style: TextStyle(fontSize: 12, color: colorScheme.tertiary),
          ),
        ],
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final error in result.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colorScheme.error),
              ),
            ),
        ],
      ],
    );
  }
}
