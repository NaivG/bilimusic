import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/player/effects_providers.dart';
import 'package:bilimusic/features/player/logic/compressor_settings.dart';
import 'package:bilimusic/features/player/logic/crossfeed_settings.dart';
import 'package:bilimusic/features/player/logic/equalizer_bands.dart';
import 'package:bilimusic/features/player/logic/equalizer_presets.dart';
import 'package:bilimusic/features/settings/ui/widgets/compressor_curve.dart';
import 'package:bilimusic/features/settings/ui/widgets/crossfeed_diagram.dart';
import 'package:bilimusic/features/settings/ui/widgets/equalizer_curve.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音效与均衡器（设置 → 音频）。
///
/// 当前承载 3 个可视化音效模块：
///
/// 1. **均衡器** —— 8 段可调频段图示均衡（lavfi `anequalizer`），
///    见 [EqualizerBandModel]；
/// 2. **交叉回馈** —— 模拟音箱听音的自然声场体验，lavfi `crossfeed`，
///    见 [CrossfeedSettingsModel]；
/// 3. **动态范围压缩器** —— 古典 / 现场录音压动态，lavfi `acompressor`，
///    见 [CompressorSettingsModel]。
///
/// ## 提交节奏（沿用既有约定）
///
/// 拖动中的修改落在每个模块各自的本地草稿（`_draft` /
/// `_crossfeedDraft` / `_compressorDraft`），松手 / 双击复位 / 切换开关才
/// 整包提交。**不要改成逐帧提交**——
/// 效果包不可变，高频写入既有落盘噪音，anequalizer 的 `params` 不在
/// mpv_audio_kit 的可热更选项里（`AnequalizerSettings._runtimeDiff` 对任何
/// 参数改动都返回 null），每次提交都会重建整条 af 链，逐帧提交就是逐帧
/// 断音。crossfeed / acompressor 的参数虽可热更，同样**节流为松手提交**——
/// 写盘噪音和重绘压力都不值得为热更付出代价。
class AudioDspPage extends ConsumerStatefulWidget {
  const AudioDspPage({super.key});

  @override
  ConsumerState<AudioDspPage> createState() => _AudioDspPageState();
}

class _AudioDspPageState extends ConsumerState<AudioDspPage> {
  /// 拖动中的均衡器本地草稿；null 表示当前没有未提交的编辑。
  EqualizerBandModel? _draft;

  /// Crossfeed 的本地草稿；null 表示当前没有未提交的编辑。
  CrossfeedSettingsModel? _crossfeedDraft;

  /// Compressor 的本地草稿；null 表示当前没有未提交的编辑。
  CompressorSettingsModel? _compressorDraft;

  // ── 通用辅助 ────────────────────────────────────────────────────────

  /// 当前效果包对应槽位的启用状态（草稿只改参数，不动它）。
  bool _aneqEnabled(mpv.AudioEffects e) => e.anequalizer?.enabled ?? false;
  bool _crossfeedEnabled(mpv.AudioEffects e) => e.crossfeed?.enabled ?? false;
  bool _acompressorEnabled(mpv.AudioEffects e) =>
      e.acompressor?.enabled ?? false;

  // ── 均衡器 ──────────────────────────────────────────────────────────

  EqualizerBandModel _currentEqModel() {
    final effects = ref.read(audioEffectsProvider);
    return _draft ??
        EqualizerBandModel.fromAnequalizerSettings(effects.anequalizer);
  }

  void _onEqBandChanged(int band, {double? frequency, double? gainDb}) {
    final model = _currentEqModel();
    setState(() {
      _draft = model.withBand(band, frequency: frequency, gainDb: gainDb);
    });
  }

  /// 提交均衡器草稿到效果包（松手时调用）。
  void _commitEqDraft() {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            anequalizer: draft.toAnequalizerSettings(
              enabled: _aneqEnabled(effects),
            ),
          ),
        );
  }

  void _toggleEqEnabled(bool value) {
    final model = _currentEqModel();
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

  void _resetEq() {
    setState(() => _draft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            anequalizer: EqualizerBandModel.flat().toAnequalizerSettings(
              enabled: _aneqEnabled(effects),
            ),
          ),
        );
  }

  void _applyEqPreset(EqualizerPreset preset) {
    setState(() => _draft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            anequalizer: preset.model.toAnequalizerSettings(
              enabled: _aneqEnabled(effects),
            ),
          ),
        );
  }

  // ── Crossfeed ───────────────────────────────────────────────────────

  CrossfeedSettingsModel _currentCrossfeed() {
    final effects = ref.read(audioEffectsProvider);
    return _crossfeedDraft ??
        CrossfeedSettingsModel.fromCrossfeedSettings(effects.crossfeed);
  }

  void _setCrossfeedDraft(CrossfeedSettingsModel m) =>
      setState(() => _crossfeedDraft = m);

  /// 提交 crossfeed 草稿（滑动条松手时调用）。
  void _commitCrossfeedDraft() {
    final draft = _crossfeedDraft;
    if (draft == null) return;
    setState(() => _crossfeedDraft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            crossfeed: draft.toCrossfeedSettings(
              enabled: _crossfeedEnabled(effects),
            ),
          ),
        );
  }

  void _toggleCrossfeed(bool value) {
    final model = _currentCrossfeed();
    setState(() => _crossfeedDraft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            crossfeed: model.toCrossfeedSettings(enabled: value),
          ),
        );
  }

  void _resetCrossfeed() {
    setState(() => _crossfeedDraft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            crossfeed: CrossfeedSettingsModel.flat().toCrossfeedSettings(
              enabled: _crossfeedEnabled(effects),
            ),
          ),
        );
  }

  // ── Compressor ──────────────────────────────────────────────────────

  CompressorSettingsModel _currentCompressor() {
    final effects = ref.read(audioEffectsProvider);
    return _compressorDraft ??
        CompressorSettingsModel.fromAcompressorSettings(effects.acompressor);
  }

  void _setCompressorDraft(CompressorSettingsModel m) =>
      setState(() => _compressorDraft = m);

  void _commitCompressorDraft() {
    final draft = _compressorDraft;
    if (draft == null) return;
    setState(() => _compressorDraft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            acompressor: draft.toAcompressorSettings(
              enabled: _acompressorEnabled(effects),
            ),
          ),
        );
  }

  void _toggleCompressor(bool value) {
    final model = _currentCompressor();
    setState(() => _compressorDraft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            acompressor: model.toAcompressorSettings(enabled: value),
          ),
        );
  }

  void _resetCompressor() {
    setState(() => _compressorDraft = null);
    final effects = ref.read(audioEffectsProvider);
    ref
        .read(audioEffectsCommandsProvider.notifier)
        .setEffects(
          effects.copyWith(
            acompressor: CompressorSettingsModel.flat().toAcompressorSettings(
              enabled: _acompressorEnabled(effects),
            ),
          ),
        );
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final effects = ref.watch(audioEffectsProvider);

    final eqModel =
        _draft ??
        EqualizerBandModel.fromAnequalizerSettings(effects.anequalizer);
    final eqEnabled = _aneqEnabled(effects);

    final cfModel =
        _crossfeedDraft ??
        CrossfeedSettingsModel.fromCrossfeedSettings(effects.crossfeed);
    final cfEnabled = _crossfeedEnabled(effects);

    final compModel =
        _compressorDraft ??
        CompressorSettingsModel.fromAcompressorSettings(effects.acompressor);
    final compEnabled = _acompressorEnabled(effects);

    final scheme = Theme.of(context).colorScheme;
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : scheme.primary;

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '音效与均衡器'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _buildEqualizerSection(
            primary: primary,
            scheme: scheme,
            model: eqModel,
            enabled: eqEnabled,
          ),
          const SizedBox(height: 24),
          _buildCrossfeedSection(
            primary: primary,
            scheme: scheme,
            model: cfModel,
            enabled: cfEnabled,
          ),
          const SizedBox(height: 24),
          _buildCompressorSection(
            primary: primary,
            scheme: scheme,
            model: compModel,
            enabled: compEnabled,
          ),
        ],
      ),
    );
  }

  // ── 均衡器段 ────────────────────────────────────────────────────────

  Widget _buildEqualizerSection({
    required Color primary,
    required ColorScheme scheme,
    required EqualizerBandModel model,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: Icon(Icons.equalizer, color: primary),
          title: const Text('启用均衡器'),
          subtitle: const Text('8 段可调频段均衡器（实时）'),
          value: enabled,
          onChanged: _toggleEqEnabled,
        ),
        const SizedBox(height: 4),
        EqualizerCurve(
          model: model,
          enabled: enabled,
          onBandChanged: _onEqBandChanged,
          onDragEnd: _commitEqDraft,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            PopupMenuButton<EqualizerPreset>(
              tooltip: '预设',
              onSelected: _applyEqPreset,
              padding: EdgeInsets.zero,
              position: PopupMenuPosition.under,
              itemBuilder: (context) => [
                for (final p in kBuiltInEqualizerPresets)
                  PopupMenuItem<EqualizerPreset>(
                    value: p,
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p.name,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              icon: const Icon(Icons.tune, size: 18),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _resetEq,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置'),
            ),
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
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── Crossfeed 段 ────────────────────────────────────────────────────

  Widget _buildCrossfeedSection({
    required Color primary,
    required ColorScheme scheme,
    required CrossfeedSettingsModel model,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: Icon(Icons.headphones_rounded, color: primary),
          title: const Text('启用交叉回馈'),
          subtitle: const Text('耳机左右声道串扰，模拟音箱的自然声场体验'),
          value: enabled,
          onChanged: _toggleCrossfeed,
        ),
        const SizedBox(height: 4),
        CrossfeedDiagram(
          strength: model.strength,
          range: model.range,
          enabled: enabled,
        ),
        const SizedBox(height: 4),
        _SliderRow(
          label: '强度',
          value: model.strength,
          min: 0,
          max: 1,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _setCrossfeedDraft(model.withStrength(v)),
          onChangeEnd: (_) => _commitCrossfeedDraft(),
          primary: primary,
        ),
        _SliderRow(
          label: '范围',
          value: model.range,
          min: 0,
          max: 1,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _setCrossfeedDraft(model.withRange(v)),
          onChangeEnd: (_) => _commitCrossfeedDraft(),
          primary: primary,
        ),
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: _resetCrossfeed,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置'),
            ),
          ],
        ),
        Text(
          '强度决定对侧混音量；范围决定低架截频对应的声场宽度。'
          '对室内音箱摆放的录音有提升，对单声道/假立体声录音慎用。'
          '打开后会产生一定延迟。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ── Compressor 段 ───────────────────────────────────────────────────

  Widget _buildCompressorSection({
    required Color primary,
    required ColorScheme scheme,
    required CompressorSettingsModel model,
    required bool enabled,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: Icon(Icons.compress_rounded, color: primary),
          title: const Text('启用压缩器'),
          subtitle: const Text('动态范围压缩（古典 / 现场录音首选）'),
          value: enabled,
          onChanged: _toggleCompressor,
        ),
        const SizedBox(height: 4),
        CompressorCurve(
          threshold: CompressorSettingsModel.dbToAmplitude(model.thresholdDb),
          ratio: model.ratio,
          makeup: CompressorSettingsModel.dbToAmplitude(model.makeupDb),
          enabled: enabled,
        ),
        const SizedBox(height: 4),
        _SliderRow(
          label: '阈值',
          value: model.thresholdDb,
          min: -60,
          max: 0,
          format: (v) => '${v.round()} dB',
          onChanged: (v) => _setCompressorDraft(model.withThresholdDb(v)),
          onChangeEnd: (_) => _commitCompressorDraft(),
          primary: primary,
        ),
        _SliderRow(
          label: '压缩比',
          value: model.ratio,
          min: 1,
          max: 20,
          format: (v) => '${v.toStringAsFixed(1)}:1',
          onChanged: (v) => _setCompressorDraft(model.withRatio(v)),
          onChangeEnd: (_) => _commitCompressorDraft(),
          primary: primary,
        ),
        _SliderRow(
          label: '启动时间',
          value: model.attackMs,
          min: 0.01,
          max: 2000,
          divisions: null,
          format: (v) => '${v.round()} ms',
          onChanged: (v) => _setCompressorDraft(model.withAttackMs(v)),
          onChangeEnd: (_) => _commitCompressorDraft(),
          primary: primary,
        ),
        _SliderRow(
          label: '释放时间',
          value: model.releaseMs,
          min: 0.01,
          max: 9000,
          divisions: null,
          format: (v) => '${v.round()} ms',
          onChanged: (v) => _setCompressorDraft(model.withReleaseMs(v)),
          onChangeEnd: (_) => _commitCompressorDraft(),
          primary: primary,
        ),
        _SliderRow(
          label: '补偿增益',
          value: model.makeupDb,
          min: 0,
          max: 24,
          format: (v) => '+${v.round()} dB',
          onChanged: (v) => _setCompressorDraft(model.withMakeupDb(v)),
          onChangeEnd: (_) => _commitCompressorDraft(),
          primary: primary,
        ),
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: _resetCompressor,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置'),
            ),
          ],
        ),
        Text(
          '阈值以上信号按压缩比折叠；补偿增益把压掉的响度补回来。'
          '古典 / 现场录音：低阈值 + 较高压缩比 + 中等启动/释放 '
          '+ 适当补偿增益，能让 ppp ↔ fff 整体可控。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 单条参数滑块：label / 当前值 / 进度条 / 右侧数字读数。
///
/// - `divisions` 为 null 时滑块连续；非 null 时按区间数取整。
/// - `onChanged` 仅刷新本地草稿；`onChangeEnd` 才触发效果包整包提交，
///   见 [AudioDspPage] 顶部"提交节奏"注释。
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double v) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Color primary;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    required this.onChangeEnd,
    required this.primary,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: primary,
              thumbColor: primary,
              overlayColor: primary.withValues(alpha: 0.10),
              // 让 attack / release 这种宽范围滑块看起来更精细：
              // track 高度 + thumb 半径走默认；不强行改形状以免与其他
              // 设置页 Slider 不一致。
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            format(value),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
