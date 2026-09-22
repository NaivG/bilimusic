import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/diagnostics/diagnostics_providers.dart';
import 'package:bilimusic/features/diagnostics/logic/audio_backend_probe.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/playback_providers.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音频后端测试页（设置 → 诊断）。
class AudioBackendPage extends ConsumerStatefulWidget {
  const AudioBackendPage({super.key});

  @override
  ConsumerState<AudioBackendPage> createState() => _AudioBackendPageState();
}

class _AudioBackendPageState extends ConsumerState<AudioBackendPage> {
  /// 采集间隔：比 mpv 的状态流（~30Hz）慢得多，但足够看清状态变化。
  static const Duration _refreshInterval = Duration(milliseconds: 500);

  late final AudioBackendProbe _probe;
  Timer? _timer;
  AudioBackendSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(audioBackendProbeProvider);
    _snapshot = _probe.capture();
    _timer = Timer.periodic(_refreshInterval, (_) {
      if (!mounted) return;
      setState(() => _snapshot = _probe.capture());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '音频后端'),
      body: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                _buildSelfCheck(snapshot),
                const SizedBox(height: 12),
                _buildActions(),
                const SizedBox(height: 12),
                _buildEngineHeader(snapshot),
                for (final player in snapshot.players) ...[
                  const SizedBox(height: 12),
                  _buildPlayerCard(player),
                ],
                const SizedBox(height: 12),
                _buildSection(
                  '应用状态机',
                  icon: Icons.memory,
                  rows: snapshot.appRows,
                ),
                const SizedBox(height: 12),
                _buildSection(
                  '媒体会话',
                  icon: Icons.cast_connected,
                  rows: snapshot.sessionRows,
                ),
                const SizedBox(height: 12),
                _buildSection(
                  '音频焦点',
                  icon: Icons.hearing,
                  rows: snapshot.focusRows,
                ),
              ],
            ),
    );
  }

  // ==================== 自检 ====================

  Widget _buildSelfCheck(AudioBackendSnapshot snapshot) {
    final scheme = Theme.of(context).colorScheme;
    final anomalies = snapshot.anomalyCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  anomalies == 0 ? Icons.check_circle : Icons.error,
                  color: anomalies == 0 ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  anomalies == 0 ? '后端自检：全部正常' : '后端自检：$anomalies 项异常',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: anomalies == 0 ? null : scheme.error),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in snapshot.selfCheck)
              _row(
                DiagnosticRow(
                  // ok == null 是中性行（例如"还没开始播"），不当异常报。
                  '${row.ok == true
                      ? '✓'
                      : row.ok == false
                      ? '✗'
                      : '·'} ${row.label}',
                  row.value,
                  warn: row.ok == false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==================== 操作 ====================

  /// 直接在页面上驱动播放链路：省得为了复现"按键没反应"而在页面与耳机之间
  /// 来回切换（桌面端也能顺手点两下）。
  Widget _buildActions() {
    final commands = ref.read(playbackCommandsProvider.notifier);
    final focus = ref.read(audioFocusServiceProvider);
    final playing = commands.isPlaying;

    Widget button(IconData icon, String label, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Wrap(
          children: [
            button(
              playing ? Icons.pause : Icons.play_arrow,
              playing ? '暂停' : '播放',
              () {
                if (playing) {
                  commands.pause();
                } else {
                  commands.resume();
                }
              },
            ),
            button(Icons.skip_previous, '上一首', () => commands.playPrevious()),
            button(Icons.skip_next, '下一首', () => commands.playNext()),
            button(Icons.replay_10, '退 10s', () {
              final target =
                  commands.currentPosition - const Duration(seconds: 10);
              commands.seek(target.isNegative ? Duration.zero : target);
            }),
            button(Icons.forward_10, '进 10s', () {
              commands.seek(
                commands.currentPosition + const Duration(seconds: 10),
              );
            }),
            button(Icons.hearing, '申请焦点', () => focus.activate()),
          ],
        ),
      ),
    );
  }

  // ==================== 引擎 ====================

  Widget _buildEngineHeader(AudioBackendSnapshot snapshot) {
    return Text(
      '引擎：${snapshot.engineVersion} · 500ms 刷新',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _buildPlayerCard(PlayerEngineSnapshot player) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = player.info.role == PlayerRole.active;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isActive ? Icons.volume_up : Icons.hourglass_empty,
                  size: 18,
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '播放器 ${player.label} · ${player.roleLabel}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in player.rows) _row(row),
          ],
        ),
      ),
    );
  }

  // ==================== 通用区块 ====================

  Widget _buildSection(
    String title, {
    required IconData icon,
    required List<DiagnosticRow> rows,
    String? footer,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title, icon),
            const SizedBox(height: 8),
            for (final row in rows) _row(row),
            if (footer != null) ...[
              const SizedBox(height: 8),
              Text(footer, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }

  Widget _row(DiagnosticRow row) {
    final scheme = Theme.of(context).colorScheme;
    final valueColor = row.warn ? scheme.error : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Text(
              row.label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              row.value,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
