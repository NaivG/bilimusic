import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/player/effects_providers.dart';
import 'package:bilimusic/features/player/logic/equalizer_bands.dart';
import 'package:bilimusic/features/settings/ui/widgets/equalizer_curve.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音效与均衡器（设置 → 音频）。
///
/// 当前承载 8 段**可调频段**可视化均衡器（lavfi `anequalizer`，
/// 见 [EqualizerBandModel]）；后续音效模块（压限、声场等）在此页扩展。
///
/// 提交节奏：拖动中的修改落在本地草稿 [_draft]，松手 / 双击复位才
/// 整包提交。**不要改成逐帧提交**——效果包不可变，高频写入既有落盘
/// 噪音，更要命的是 anequalizer 的 `params` 不在 mpv_audio_kit 的
/// 可热更选项里（`AnequalizerSettings._runtimeDiff` 对任何参数改动都
/// 返回 null），每次提交都会重建整条 af 链，逐帧提交就是逐帧断音。
class AudioDspPage extends ConsumerStatefulWidget {
  const AudioDspPage({super.key});

  @override
  ConsumerState<AudioDspPage> createState() => _AudioDspPageState();
}

class _AudioDspPageState extends ConsumerState<AudioDspPage> {
  /// 拖动中的本地草稿模型；null 表示当前没有未提交的编辑。
  EqualizerBandModel? _draft;

  /// 当前效果包里 anequalizer 槽位的启用状态（草稿只改曲线，不动它）。
  bool _enabledOf(mpv.AudioEffects effects) =>
      effects.anequalizer?.enabled ?? false;

  void _onBandChanged(int band, {double? frequency, double? gainDb}) {
    final model = _currentModel();
    setState(() {
      _draft = model.withBand(band, frequency: frequency, gainDb: gainDb);
    });
  }

  /// 提交草稿到效果包（松手时调用）。
  void _commitDraft() {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            anequalizer: draft.toAnequalizerSettings(
              enabled: _enabledOf(effects),
            ),
          ),
        );
  }

  /// 开关均衡器（立即提交；若有未提交草稿，以草稿曲线为准一起提交）。
  void _toggleEnabled(bool value) {
    final model = _currentModel();
    setState(() => _draft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            anequalizer: model.toAnequalizerSettings(enabled: value),
          ),
        );
  }

  /// 整体复位：默认频点 + 全部增益归零（立即提交）。
  void _resetAll() {
    setState(() => _draft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            anequalizer: EqualizerBandModel.flat().toAnequalizerSettings(
              enabled: _enabledOf(effects),
            ),
          ),
        );
  }

  EqualizerBandModel _currentModel() {
    final effects = ref.read(audioEffectsProvider);
    return _draft ??
        EqualizerBandModel.fromAnequalizerSettings(effects.anequalizer);
  }

  @override
  Widget build(BuildContext context) {
    final effects = ref.watch(audioEffectsProvider);
    final model =
        _draft ??
        EqualizerBandModel.fromAnequalizerSettings(effects.anequalizer);
    final enabled = _enabledOf(effects);
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '音效与均衡器'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          SwitchListTile(
            secondary: Icon(Icons.equalizer, color: primary),
            title: const Text('启用均衡器'),
            subtitle: const Text('8 段可调频段均衡器（实时）'),
            value: enabled,
            onChanged: _toggleEnabled,
          ),
          const SizedBox(height: 4),
          EqualizerCurve(
            model: model,
            enabled: enabled,
            onBandChanged: _onBandChanged,
            onDragEnd: _commitDraft,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: _resetAll,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('重置'),
              ),
              const Spacer(),
              Text(
                '8 段 · ±12 dB',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            '横向拖动节点调整频段中心频率，纵向拖动调整增益，双击节点将增益归零。'
            '各频段按几何中点切分、互不重叠，并在边界处平滑衔接。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
