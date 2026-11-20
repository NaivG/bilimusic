import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/offline/models/offline_track.dart';
import 'package:bilimusic/features/offline/offline_providers.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

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
    final colors = context.bmColors;
    final type = context.bmType;
    final title = _running
        ? '正在离线缓存'
        : _fatalError != null
        ? '离线缓存失败'
        : _result?.cancelled == true
        ? '已停止离线缓存'
        : '离线缓存完成';

    return PopScope(
      canPop: !_running,
      child: BmDialog(
        title: title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.playlistName != null &&
                widget.playlistName!.isNotEmpty) ...[
              Text(
                widget.playlistName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.label.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: BmTokens.s4),
            ],
            if (_running) _buildRunning() else _buildResult(),
          ],
        ),
        actions: [
          if (_running)
            BmDialogAction(
              label: _cancelRequested ? '正在取消…' : '取消',
              enabled: !_cancelRequested,
              onPressed: _requestCancel,
            )
          else
            BmDialogAction(
              label: '完成',
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildRunning() {
    final colors = context.bmColors;
    final type = context.bmType;
    final base = (_current - 1).clamp(0, _total);
    final value = _total > 0 ? (base / _total).clamp(0.0, 1.0) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: value,
          minHeight: BmTokens.s1,
          borderRadius: BmTokens.r4All,
          color: colors.accent,
          backgroundColor: colors.fillMuted,
        ),
        const SizedBox(height: BmTokens.s4),
        Row(
          children: [
            SizedBox(
              width: BmTokens.iconInline,
              height: BmTokens.iconInline,
              child: CircularProgressIndicator(
                strokeWidth: BmTokens.s1 / 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: BmTokens.s2),
            Expanded(
              child: Text(
                '正在缓存 $_current / $_total',
                style: BmTypography.numeric(type.label).copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: BmTokens.s1),
        Text(
          _currentMusic?.title ?? '准备中…',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: type.label.copyWith(color: colors.textSecondary),
        ),
        if (_cancelRequested) ...[
          const SizedBox(height: BmTokens.s3),
          Text(
            '将在当前曲目下载完成后停止',
            style: type.caption.copyWith(color: colors.warning),
          ),
        ],
      ],
    );
  }

  Widget _buildResult() {
    final colors = context.bmColors;
    final type = context.bmType;
    final result = _result;
    if (_fatalError != null) {
      return Text(
        '批量缓存失败：$_fatalError',
        style: type.label.copyWith(color: colors.danger),
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
        LinearProgressIndicator(
          value: 1,
          minHeight: BmTokens.s1,
          borderRadius: BmTokens.r4All,
          color: colors.accent,
          backgroundColor: colors.fillMuted,
        ),
        const SizedBox(height: BmTokens.s4),
        Text(
          parts.join(' · '),
          style: BmTypography.numeric(type.label)
              .copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
        ),
        if (result.cancelled) ...[
          const SizedBox(height: BmTokens.s1),
          Text(
            '已取消，剩余 ${widget.songs.length - result.processed} 首未处理',
            style: type.caption.copyWith(color: colors.warning),
          ),
        ],
        if (result.errors.isNotEmpty) ...[
          const SizedBox(height: BmTokens.s3),
          for (final error in result.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: BmTokens.s1),
              child: Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.danger),
              ),
            ),
        ],
      ],
    );
  }
}
