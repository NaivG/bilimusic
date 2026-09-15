import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/player/logic/sleep_timer_service.dart';

/// 详情页「更多」菜单 → 定时关闭底部弹层。
///
/// - 预设时长一键启动 / 重启；
/// - 自定义分钟数步进（5 ~ 240，步长 5）；
/// - 「播完当前歌曲后停止」开关：默认到点立即暂停，开启后等当前歌曲
///   播放完毕再暂停；
/// - 运行中显示剩余时间，支持延长 5 分钟与取消。
void showSleepTimerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.grey[900],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => const SleepTimerSheet(),
  );
}

/// 定时关闭弹层内容。直接订阅 [SleepTimerService.state] 渲染。
class SleepTimerSheet extends ConsumerStatefulWidget {
  const SleepTimerSheet({super.key});

  @override
  ConsumerState<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<SleepTimerSheet> {
  /// 自定义时长（分钟）。
  int _customMinutes = 30;

  static const int _customMin = 5;
  static const int _customMax = 240;
  static const int _customStep = 5;

  static const List<int> _presetMinutes = [15, 30, 45, 60, 90];

  SleepTimerService get _service => ref.read(sleepTimerServiceProvider);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ValueListenableBuilder<SleepTimerUiState>(
        valueListenable: _service.state,
        builder: (context, timer, _) {
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 拖动条（与 showOptionsSheet 一致）
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildHeader(timer),
                const SizedBox(height: 16),
                _buildPresets(timer),
                const SizedBox(height: 12),
                _buildCustomRow(timer),
                const SizedBox(height: 8),
                _buildFinishToggle(timer),
                if (timer.phase == SleepTimerPhase.counting) ...[
                  const SizedBox(height: 12),
                  _buildActiveActions(),
                ] else if (timer.phase == SleepTimerPhase.waitingTrackEnd) ...[
                  const SizedBox(height: 12),
                  _buildWaitingActions(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 标题 + 状态（剩余时间 / 播完本曲后停止）。
  Widget _buildHeader(SleepTimerUiState timer) {
    String? status;
    switch (timer.phase) {
      case SleepTimerPhase.idle:
        status = null;
        break;
      case SleepTimerPhase.counting:
        status = '剩余 ${formatSleepRemaining(timer.remainingMs)}';
        break;
      case SleepTimerPhase.waitingTrackEnd:
        status = '播完本曲后暂停';
        break;
    }

    return Row(
      children: [
        const Icon(Icons.timer_outlined, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        const Text(
          '定时关闭',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (status != null)
          Text(
            status,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  /// 预设时长 chips —— 点击即以该时长启动 / 重启。
  Widget _buildPresets(SleepTimerUiState timer) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _presetMinutes
          .map((minutes) => _presetChip(minutes, timer))
          .toList(),
    );
  }

  Widget _presetChip(int minutes, SleepTimerUiState timer) {
    final active =
        timer.phase == SleepTimerPhase.counting &&
        timer.totalMs == Duration(minutes: minutes).inMilliseconds;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _service.start(
        Duration(minutes: minutes),
        finishCurrentTrack: timer.finishCurrentTrack,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: active
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.7 : 0.15),
          ),
        ),
        child: Text(
          '$minutes 分钟',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  /// 自定义分钟数步进 + 开始按钮。
  Widget _buildCustomRow(SleepTimerUiState timer) {
    return Row(
      children: [
        _stepButton(
          icon: Icons.remove,
          onTap: () => setState(() {
            _customMinutes = (_customMinutes - _customStep).clamp(
              _customMin,
              _customMax,
            );
          }),
        ),
        Expanded(
          child: Text(
            '自定义 · $_customMinutes 分钟',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        _stepButton(
          icon: Icons.add,
          onTap: () => setState(() {
            _customMinutes = (_customMinutes + _customStep).clamp(
              _customMin,
              _customMax,
            );
          }),
        ),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _service.start(
            Duration(minutes: _customMinutes),
            finishCurrentTrack: timer.finishCurrentTrack,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white,
            ),
            child: const Text(
              '开始',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  /// 「播完当前歌曲后停止」开关行。
  Widget _buildFinishToggle(SleepTimerUiState timer) {
    return Row(
      children: [
        Icon(
          Icons.music_note_outlined,
          color: Colors.white.withValues(alpha: 0.7),
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '播完当前歌曲后停止',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                '关闭时到达设定时间立即暂停',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: timer.finishCurrentTrack,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.white.withValues(alpha: 0.5),
          inactiveThumbColor: Colors.white.withValues(alpha: 0.8),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
          onChanged: _service.setFinishCurrentTrack,
        ),
      ],
    );
  }

  /// 倒计时中：延长 / 取消。
  Widget _buildActiveActions() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: '延长 5 分钟',
            onTap: () => _service.extend(const Duration(minutes: 5)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: '取消定时',
            onTap: _service.cancel,
            filled: true,
          ),
        ),
      ],
    );
  }

  /// 等待本曲播完：提示 + 取消。
  Widget _buildWaitingActions() {
    return Row(
      children: [
        Expanded(
          child: Text(
            '正在等待当前歌曲播放完毕…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: '取消定时',
            onTap: _service.cancel,
            filled: true,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: filled
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
