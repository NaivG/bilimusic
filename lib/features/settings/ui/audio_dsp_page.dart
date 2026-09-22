import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/player/effects_providers.dart';
import 'package:bilimusic/features/player/logic/compressor_settings.dart';
import 'package:bilimusic/features/player/logic/crossfeed_settings.dart';
import 'package:bilimusic/features/player/logic/echo_settings.dart';
import 'package:bilimusic/features/player/logic/equalizer_bands.dart';
import 'package:bilimusic/features/player/logic/equalizer_presets.dart';
import 'package:bilimusic/features/settings/ui/widgets/compressor_curve.dart';
import 'package:bilimusic/features/settings/ui/widgets/crossfeed_diagram.dart';
import 'package:bilimusic/features/settings/ui/widgets/equalizer_curve.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音效与均衡器（设置 → 音频）。
///
/// 当前承载 5 个模块：
///
/// 1. **均衡器** —— 8 段可调频段图示均衡（lavfi `anequalizer`），
///    见 [EqualizerBandModel]；
/// 2. **交叉回馈** —— 模拟音箱听音的自然声场体验，lavfi `crossfeed`，
///    见 [CrossfeedSettingsModel]；
/// 3. **动态范围压缩器** —— 古典 / 现场录音压动态，lavfi `acompressor`，
///    见 [CompressorSettingsModel]；
/// 4. **音效增强**（可折叠组）—— 低频激励 `asubboost` / 高频谐波激励
///    `aexciter` / 回声 `aecho` / 砖墙限幅 `alimiter`；
/// 5. **立体声增强**（可折叠组）—— 立体声宽度 `extrastereo` / 环绕上混
///    `surround`。
///
/// 后两组是**组级折叠**：6 个效果每个都带 3~5 条滑块，逐卡再折一层会让
/// 页面多出 6 个只有一行的标题，点开点关全是噪音；而全部平铺会把页面拉到
/// 6 屏以上，所以折叠粒度取在「特性」这一层。
///
/// ## 提交节奏（沿用既有约定）
///
/// 拖动中的修改落在本地草稿，松手 / 双击复位 / 切换开关才整包提交。
/// **不要改成逐帧提交**——
/// 效果包不可变，高频写入既有落盘噪音，anequalizer 的 `params` 不在
/// mpv_audio_kit 的可热更选项里（`AnequalizerSettings._runtimeDiff` 对任何
/// 参数改动都返回 null），每次提交都会重建整条 af 链，逐帧提交就是逐帧
/// 断音。crossfeed / acompressor 的参数虽可热更，同样**节流为松手提交**——
/// 写盘噪音和重绘压力都不值得为热更付出代价。
///
/// 草稿分两套：上面三个模块各持一个**类型化**草稿（`_draft` /
/// `_crossfeedDraft` / `_compressorDraft`），因为它们的模型层要垫换算
/// （频段切分 / dB↔振幅）；音效增强 + 立体声增强 6 个槽位共用**一个整包
/// 草稿** `_fxDraft`，因为它们都是 lavfi 参数直通、`AudioEffects` 自带
/// `copyWith`，整包草稿就是最小实现。两套的提交时机完全一致。
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

  /// 音效增强 + 立体声增强 6 个槽位共用的**整包**草稿；
  /// null 表示当前没有未提交的编辑。
  ///
  /// 与上面三个模块的类型化草稿并存、互不干扰：它们的提交都走
  /// `setEffects`，写入的是「已提交包 + 本次改动」，同一时刻只有一个手势
  /// 在改，不会互相覆盖。
  mpv.AudioEffects? _fxDraft;

  // ── 音效增强 / 立体声增强：整包草稿 ────────────────────────────────

  /// 在草稿上 patch 一个槽位（无草稿时以已提交包为底）。滑动条 `onChanged`
  /// 走这里——只写本地，不下发、不落盘。
  void _patchFx(mpv.AudioEffects Function(mpv.AudioEffects) patch) {
    setState(() {
      _fxDraft = patch(_fxDraft ?? ref.read(audioEffectsProvider));
    });
  }

  /// 草稿整包提交。滑动条 `onChangeEnd` 走这里；没有草稿时直接返回，
  /// 重复提交同一份配置由服务层的相等判断短路。
  void _commitFx() {
    final draft = _fxDraft;
    if (draft == null) return;
    setState(() => _fxDraft = null);
    ref.read(audioEffectsCommandsProvider.notifier).setEffects(draft);
  }

  /// 离散动作（切换开关 / 重置）：在草稿基础上改完立刻提交，不留给下一次。
  void _applyFx(mpv.AudioEffects Function(mpv.AudioEffects) patch) {
    _patchFx(patch);
    _commitFx();
  }

  /// 以下 6 个 helper 把「null 槽位补默认实例 → copyWith → 写回槽位」三步
  /// 收口成一处，页面里每个滑块 / 开关就只剩「改哪个字段」这一件事。
  /// 返回值是整包 patch，喂给 [_patchFx]（拖动中）或 [_applyFx]（离散）。

  mpv.AudioEffects Function(mpv.AudioEffects) _editSubboost(
    mpv.AsubboostSettings Function(mpv.AsubboostSettings) p,
  ) =>
      (e) => e.copyWith(
        asubboost: p(e.asubboost ?? const mpv.AsubboostSettings()),
      );

  mpv.AudioEffects Function(mpv.AudioEffects) _editExciter(
    mpv.AexciterSettings Function(mpv.AexciterSettings) p,
  ) =>
      (e) =>
          e.copyWith(aexciter: p(e.aexciter ?? const mpv.AexciterSettings()));

  mpv.AudioEffects Function(mpv.AudioEffects) _editEcho(
    mpv.AechoSettings Function(mpv.AechoSettings) p,
  ) =>
      (e) => e.copyWith(aecho: p(e.aecho ?? const mpv.AechoSettings()));

  mpv.AudioEffects Function(mpv.AudioEffects) _editLimiter(
    mpv.AlimiterSettings Function(mpv.AlimiterSettings) p,
  ) =>
      (e) =>
          e.copyWith(alimiter: p(e.alimiter ?? const mpv.AlimiterSettings()));

  mpv.AudioEffects Function(mpv.AudioEffects) _editExtrastereo(
    mpv.ExtrastereoSettings Function(mpv.ExtrastereoSettings) p,
  ) =>
      (e) => e.copyWith(
        extrastereo: p(e.extrastereo ?? const mpv.ExtrastereoSettings()),
      );

  mpv.AudioEffects Function(mpv.AudioEffects) _editSurround(
    mpv.SurroundSettings Function(mpv.SurroundSettings) p,
  ) =>
      (e) =>
          e.copyWith(surround: p(e.surround ?? const mpv.SurroundSettings()));

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

    // 音效增强 / 立体声增强：草稿优先，否则就是已提交的包。
    final fx = _fxDraft ?? effects;

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
          const SizedBox(height: 16),
          _buildEnhancementGroup(primary: primary, scheme: scheme, fx: fx),
          const SizedBox(height: 8),
          _buildStereoGroup(primary: primary, scheme: scheme, fx: fx),
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

  // ── 音效增强 / 立体声增强 ─────────────────────────────────────────

  /// 可折叠的特性分组容器。
  ///
  /// 折叠粒度取在「特性」这一层：组内效果卡全部平铺（逐卡再折一层会多出
  /// 6 个只有一行的标题），组本身可以收起来（否则 6 张卡 × 3~5 条滑块
  /// 要把页面拉到 6 屏以上）。
  ///
  /// 副标题是**动态**的——收起时副标题是唯一还能看出「这组到底开没开」的
  /// 地方，所以列出已开启的效果名；一个都没开才回落到静态描述。
  Widget _buildFxGroup({
    required IconData icon,
    required String title,
    required String fallback,
    required List<(String, bool)> items,
    required List<Widget> children,
  }) {
    final on = [
      for (final (name, enabled) in items)
        if (enabled) name,
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(on.isEmpty ? fallback : '已开启：${on.join(' · ')}'),
      children: children,
    );
  }

  /// 一张效果卡：开关行 + 参数滑块 + 重置 + 一句说明。
  ///
  /// 结构与上面三个模块的 section 完全一致（SwitchListTile → 控件 →
  /// 右对齐重置 → bodySmall 说明），只是被 [_buildFxGroup] 包了一层。
  Widget _buildFxCard({
    required Color primary,
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggled,
    required VoidCallback onReset,
    required List<Widget> controls,
    required String note,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: Icon(icon, color: primary),
          title: Text(title),
          subtitle: Text(subtitle),
          value: enabled,
          onChanged: onToggled,
        ),
        ...controls,
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('重置'),
            ),
          ],
        ),
        Text(
          note,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 音效增强：低频激励 → 高频谐波 → 回声 → 限幅。
  ///
  /// **顺序是有意的**：先激励（把能量抬起来）→ 回声（造空间）→ 限幅
  /// （兜底防爆）。限幅压轴，前面调得多激进都不会把峰值顶爆。
  Widget _buildEnhancementGroup({
    required Color primary,
    required ColorScheme scheme,
    required mpv.AudioEffects fx,
  }) {
    final sub = fx.asubboost ?? const mpv.AsubboostSettings();
    final exc = fx.aexciter ?? const mpv.AexciterSettings();
    final echo = fx.aecho ?? const mpv.AechoSettings();
    final lim = fx.alimiter ?? const mpv.AlimiterSettings();

    return _buildFxGroup(
      icon: Icons.auto_awesome_rounded,
      title: '音效增强',
      fallback: '低频激励 · 高频谐波 · 回声 · 限幅',
      items: [
        ('低频激励', sub.enabled),
        ('高频谐波', exc.enabled),
        ('回声', echo.enabled),
        ('限幅', lim.enabled),
      ],
      children: [
        // ── 低频激励 asubboost ──
        _buildFxCard(
          primary: primary,
          scheme: scheme,
          icon: Icons.graphic_eq_rounded,
          title: '低频激励',
          subtitle: 'asubboost · 补回下潜不足的低频',
          enabled: sub.enabled,
          onToggled: (v) =>
              _applyFx(_editSubboost((s) => s.copyWith(enabled: v))),
          onReset: () => _applyFx(
            _editSubboost((s) => mpv.AsubboostSettings(enabled: s.enabled)),
          ),
          controls: [
            _SliderRow(
              label: '最大增益',
              value: sub.boost,
              min: mpv.AsubboostSettings.boostMin,
              max: mpv.AsubboostSettings.boostMax,
              format: (v) => '×${v.toStringAsFixed(1)}',
              onChanged: (v) =>
                  _patchFx(_editSubboost((s) => s.copyWith(boost: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '截频',
              value: sub.cutoff,
              min: mpv.AsubboostSettings.cutoffMin,
              max: mpv.AsubboostSettings.cutoffMax,
              format: (v) => '${v.round()} Hz',
              onChanged: (v) =>
                  _patchFx(_editSubboost((s) => s.copyWith(cutoff: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '干声',
              value: sub.dry,
              min: mpv.AsubboostSettings.dryMin,
              max: mpv.AsubboostSettings.dryMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editSubboost((s) => s.copyWith(dry: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '湿声',
              value: sub.wet,
              min: mpv.AsubboostSettings.wetMin,
              max: mpv.AsubboostSettings.wetMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editSubboost((s) => s.copyWith(wet: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '反馈',
              value: sub.feedback,
              min: mpv.AsubboostSettings.feedbackMin,
              max: mpv.AsubboostSettings.feedbackMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editSubboost((s) => s.copyWith(feedback: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
          ],
          note:
              '增益是最大提升倍数，截频决定抬哪一段以下，干/湿是原声与'
              '激励声的配比，反馈让提升带上延音。耳机低频发虚时效果明显，'
              '音箱上开大容易轰头。',
        ),
        const SizedBox(height: 8),

        // ── 高频谐波激励 aexciter ──
        _buildFxCard(
          primary: primary,
          scheme: scheme,
          icon: Icons.waves_rounded,
          title: '高频谐波激励',
          subtitle: 'aexciter · 生成谐波补回高频空气感',
          enabled: exc.enabled,
          onToggled: (v) =>
              _applyFx(_editExciter((s) => s.copyWith(enabled: v))),
          onReset: () => _applyFx(
            _editExciter((s) => mpv.AexciterSettings(enabled: s.enabled)),
          ),
          controls: [
            _SliderRow(
              label: '激励量',
              value: exc.amount,
              min: mpv.AexciterSettings.amountMin,
              max: mpv.AexciterSettings.amountMax,
              format: (v) => '×${v.toStringAsFixed(1)}',
              onChanged: (v) =>
                  _patchFx(_editExciter((s) => s.copyWith(amount: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '驱动',
              value: exc.drive,
              min: mpv.AexciterSettings.driveMin,
              max: mpv.AexciterSettings.driveMax,
              format: (v) => '×${v.toStringAsFixed(1)}',
              onChanged: (v) =>
                  _patchFx(_editExciter((s) => s.copyWith(drive: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '起振频率',
              value: exc.freq,
              min: mpv.AexciterSettings.freqMin,
              max: mpv.AexciterSettings.freqMax,
              format: (v) => '${v.round()} Hz',
              onChanged: (v) =>
                  _patchFx(_editExciter((s) => s.copyWith(freq: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
          ],
          note:
              '在起振频率以上生成谐波，给码率偏低、听着发闷的稿件补一点'
              '空气感。激励量是谐波强度，驱动决定谐波染色。开大了齿音会变重。',
        ),
        const SizedBox(height: 8),

        // ── 回声 aecho ──
        _buildFxCard(
          primary: primary,
          scheme: scheme,
          icon: Icons.repeat_rounded,
          title: '回声',
          subtitle: 'aecho · 单次反射拉开空间感',
          enabled: echo.enabled,
          onToggled: (v) => _applyFx(_editEcho((s) => s.copyWith(enabled: v))),
          onReset: () =>
              _applyFx(_editEcho((s) => mpv.AechoSettings(enabled: s.enabled))),
          controls: [
            _SliderRow(
              label: '延迟',
              // lavfi 上限 90000 ms，UI 卡在 5 s：音乐里超过几秒的回声
              // 已经不是「空间感」而是另一段歌词了，留着只会调出怪东西。
              value: AechoParams.delayOf(echo),
              min: 1,
              max: 5000,
              format: (v) => '${v.round()} ms',
              onChanged: (v) => _patchFx(
                _editEcho((s) => s.copyWith(delays: AechoParams.single(v))),
              ),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '衰减',
              value: AechoParams.decayOf(echo),
              // lavfi 声明的区间是 (0, 1.0]——0 不在区间内，下限取 0.01
              // 免得写进一个 ffmpeg 直接拒收的值把整条 af 链搞挂。
              min: 0.01,
              max: 1,
              format: _percent,
              onChanged: (v) => _patchFx(
                _editEcho((s) => s.copyWith(decays: AechoParams.single(v))),
              ),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '输入增益',
              value: echo.in_gain,
              min: mpv.AechoSettings.in_gainMin,
              max: mpv.AechoSettings.in_gainMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editEcho((s) => s.copyWith(in_gain: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '输出增益',
              value: echo.out_gain,
              min: mpv.AechoSettings.out_gainMin,
              max: mpv.AechoSettings.out_gainMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editEcho((s) => s.copyWith(out_gain: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
          ],
          note:
              '延迟是回声晚多少毫秒到，衰减是回声比原声响多少。输入/输出'
              '增益分别控制进、出滤镜的电平。轻微回声能拉开空间，长延迟大'
              '衰减就变成混响拖尾了。',
        ),
        const SizedBox(height: 8),

        // ── 砖墙限幅 alimiter ──
        _buildFxCard(
          primary: primary,
          scheme: scheme,
          icon: Icons.speed_rounded,
          title: '砖墙限幅',
          subtitle: 'alimiter · 输出不超过天花板，防爆音',
          enabled: lim.enabled,
          onToggled: (v) =>
              _applyFx(_editLimiter((s) => s.copyWith(enabled: v))),
          onReset: () => _applyFx(
            _editLimiter((s) => mpv.AlimiterSettings(enabled: s.enabled)),
          ),
          controls: [
            _SliderRow(
              label: '限幅',
              // lavfi 的 limit 是线性振幅（0.0625..1.0），UI 一律用 dB——
              // 换算复用 CompressorSettingsModel 的公开静态方法。
              value: CompressorSettingsModel.amplitudeToDb(lim.limit),
              min: CompressorSettingsModel.amplitudeToDb(
                mpv.AlimiterSettings.limitMin,
              ),
              max: CompressorSettingsModel.amplitudeToDb(
                mpv.AlimiterSettings.limitMax,
              ),
              format: (v) => '${v.round()} dB',
              onChanged: (v) => _patchFx(
                _editLimiter(
                  (s) => s.copyWith(
                    limit: CompressorSettingsModel.dbToAmplitude(v).clamp(
                      mpv.AlimiterSettings.limitMin,
                      mpv.AlimiterSettings.limitMax,
                    ),
                  ),
                ),
              ),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '启动时间',
              value: lim.attack,
              min: mpv.AlimiterSettings.attackMin,
              max: mpv.AlimiterSettings.attackMax,
              format: (v) => '${v.toStringAsFixed(1)} ms',
              onChanged: (v) =>
                  _patchFx(_editLimiter((s) => s.copyWith(attack: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '释放时间',
              value: lim.release,
              min: mpv.AlimiterSettings.releaseMin,
              max: mpv.AlimiterSettings.releaseMax,
              format: (v) => '${v.round()} ms',
              onChanged: (v) =>
                  _patchFx(_editLimiter((s) => s.copyWith(release: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
          ],
          note:
              '输出永远不会越过设定的天花板，防止前面几级激励把峰值顶爆。'
              '启动/释放决定它压下去和松开的快慢。作为链尾保险，前面调得'
              '激进时尤其值得开着。',
        ),
      ],
    );
  }

  /// 立体声增强：立体声宽度 → 环绕上混。
  Widget _buildStereoGroup({
    required Color primary,
    required ColorScheme scheme,
    required mpv.AudioEffects fx,
  }) {
    final st = fx.extrastereo ?? const mpv.ExtrastereoSettings();
    final su = fx.surround ?? const mpv.SurroundSettings();

    return _buildFxGroup(
      icon: Icons.center_focus_weak_rounded,
      title: '立体声增强',
      fallback: '立体声宽度 · 环绕上混',
      items: [('立体声宽度', st.enabled), ('环绕上混', su.enabled)],
      children: [
        // ── 立体声宽度 extrastereo ──
        _buildFxCard(
          primary: primary,
          scheme: scheme,
          icon: Icons.unfold_more_rounded,
          title: '立体声宽度',
          subtitle: 'extrastereo · 放大左右差信号拉宽声场',
          enabled: st.enabled,
          onToggled: (v) =>
              _applyFx(_editExtrastereo((s) => s.copyWith(enabled: v))),
          onReset: () => _applyFx(
            _editExtrastereo(
              (s) => mpv.ExtrastereoSettings(enabled: s.enabled),
            ),
          ),
          controls: [
            _SliderRow(
              label: '差分系数',
              value: st.m,
              min: mpv.ExtrastereoSettings.mMin,
              max: mpv.ExtrastereoSettings.mMax,
              format: (v) => v.toStringAsFixed(1),
              onChanged: (v) =>
                  _patchFx(_editExtrastereo((s) => s.copyWith(m: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
          ],
          note:
              '把左右声道的差信号放大后叠回两声道，直接拉宽声场：系数为正'
              '是增宽，为负会反相收窄。单声道或假立体声录音加宽只会更糊。',
        ),
        const SizedBox(height: 8),

        // ── 环绕上混 surround ──
        _buildFxCard(
          primary: primary,
          scheme: scheme,
          icon: Icons.surround_sound_rounded,
          title: '环绕上混',
          subtitle: 'surround · 立体声上混 5.1 再交回输出端',
          enabled: su.enabled,
          onToggled: (v) =>
              _applyFx(_editSurround((s) => s.copyWith(enabled: v))),
          onReset: () => _applyFx(
            _editSurround((s) => mpv.SurroundSettings(enabled: s.enabled)),
          ),
          controls: [
            _SliderRow(
              label: '角度',
              value: su.angle,
              min: mpv.SurroundSettings.angleMin,
              max: mpv.SurroundSettings.angleMax,
              format: (v) => '${v.round()}°',
              onChanged: (v) =>
                  _patchFx(_editSurround((s) => s.copyWith(angle: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '聚焦',
              value: su.focus,
              min: mpv.SurroundSettings.focusMin,
              max: mpv.SurroundSettings.focusMax,
              format: (v) => v > 0.005
                  ? '前 ${v.toStringAsFixed(2)}'
                  : v < -0.005
                  ? '后 ${(-v).toStringAsFixed(2)}'
                  : '居中',
              onChanged: (v) =>
                  _patchFx(_editSurround((s) => s.copyWith(focus: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '窗重叠',
              value: su.overlap,
              min: mpv.SurroundSettings.overlapMin,
              max: mpv.SurroundSettings.overlapMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editSurround((s) => s.copyWith(overlap: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
            _SliderRow(
              label: '平滑',
              value: su.smooth,
              min: mpv.SurroundSettings.smoothMin,
              max: mpv.SurroundSettings.smoothMax,
              format: _percent,
              onChanged: (v) =>
                  _patchFx(_editSurround((s) => s.copyWith(smooth: v))),
              onChangeEnd: (_) => _commitFx(),
              primary: primary,
            ),
          ],
          note:
              '把立体声上混到 5.1 再交回输出端（非 5.1 设备由 mpv 下混），'
              '用空间位置而不是电平差造声场：角度是声场旋转方向，聚焦在前后'
              '声像之间取舍，窗重叠与平滑控制变换的连续性。相位会被改写，'
              '耳机上听感变化最大，且会多吃一份 CPU。',
        ),
      ],
    );
  }

  /// 0..1 → 百分比读数，几个效果的干湿 / 衰减 / 比例共用。
  static String _percent(double v) => '${(v * 100).round()}%';
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
