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
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音效与均衡器（设置 → 音频）。
///
/// 页面由 **9 个同构折叠模块** 组成，每个模块 = 一行头部 + 一块可折叠正文：
///
/// | 模块 | lavfi | 正文 |
/// | --- | --- | --- |
/// | 均衡器 | `anequalizer` | 响应曲线 + 预设菜单 |
/// | 交叉回馈 | `crossfeed` | 声场图 + 2 条滑块 |
/// | 压缩器 | `acompressor` | 压缩曲线 + 5 条滑块 |
/// | 低频激励 | `asubboost` | 5 条滑块 |
/// | 高频谐波激励 | `aexciter` | 3 条滑块 |
/// | 回声 | `aecho` | 4 条滑块 |
/// | 限幅器 | `alimiter` | 3 条滑块 |
/// | 立体声宽度 | `extrastereo` | 1 条滑块 |
/// | 环绕上混 | `surround` | 4 条滑块 |
///
/// 拖动中的修改落在本地草稿，松手 / 双击复位 / 切换开关才整包提交。
/// **不要改成逐帧提交**——
/// 效果包不可变，高频写入既有落盘噪音，anequalizer 的 `params` 不在
/// mpv_audio_kit 的可热更选项里（`AnequalizerSettings._runtimeDiff` 对任何
/// 参数改动都返回 null），每次提交都会重建整条 af 链，逐帧提交就是逐帧
/// 断音。crossfeed / acompressor 的参数虽可热更，同样**节流为松手提交**——
/// 写盘噪音和重绘压力都不值得为热更付出代价。
///
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

  /// 6 个 lavfi 效果共用的**整包**草稿；null 表示当前没有未提交的编辑。
  ///
  /// 与上面三个模块的类型化草稿并存、互不干扰：它们的提交都走
  /// `setEffects`，写入的是「已提交包 + 本次改动」，同一时刻只有一个手势
  /// 在改，不会互相覆盖。
  mpv.AudioEffects? _fxDraft;

  // ── 折叠状态 ────────────────────────────────────────────────────────

  /// 各模块展开态的**手动覆盖表**。
  final Map<_Module, bool> _open = {};

  /// 模块 [m] 此刻是否展开。
  ///
  /// 没被手动点过的模块回落到「这个效果开着吗」——打开的自动展开、
  /// 关掉的自动收起；点过之后 [_open] 里那一次手势就是唯一事实。
  bool _isOpen(_Module m, bool enabled) => _open[m] ?? enabled;

  /// 记录一次手动展开 / 收起（头部点击，或开关连带的展开）。
  void _setOpen(_Module m, bool value) => setState(() => _open[m] = value);

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
    // 开 → 顺手展开（正要调它）；关 → 收起。[_setOpen] 记下这次手势。
    _setOpen(_Module.eq, value);
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
    _setOpen(_Module.crossfeed, value);
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
    _setOpen(_Module.compressor, value);
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

  /// 6 个 lavfi 效果的开关：**改完立刻提交，并顺带同步展开态**
  /// （打开即展开，关掉即收起），与前三个模块的 `_*Enabled` 同语义。
  void _toggleFx(
    _Module m,
    bool value,
    mpv.AudioEffects Function(mpv.AudioEffects) patch,
  ) {
    _setOpen(m, value);
    _applyFx(patch);
  }

  // ── 参数快照（收起时头部第二行）────────────────────────────────────
  //
  // 开关本身已经表达了开 / 关，所以这一行**不再重复状态**，改成「当前
  // 调到哪儿了」：整页收起时扫一眼就能读出整条链的参数。取值一律走
  // 草稿优先的模型，拖动中头部实时跟着走。

  String _eqStatus(EqualizerBandModel m) {
    final tuned = m.gainsDb.where((g) => g.abs() > 1e-6).length;
    return tuned == 0 ? '8 段 · 平直' : '8 段 · 已调 $tuned 段';
  }

  String _crossfeedStatus(CrossfeedSettingsModel m) =>
      '强度 ${_percent(m.strength)} · 范围 ${_percent(m.range)}';

  String _compressorStatus(CompressorSettingsModel m) =>
      '${m.thresholdDb.round()} dB · ${m.ratio.toStringAsFixed(1)}:1';

  String _subboostStatus(mpv.AsubboostSettings s) =>
      '×${s.boost.toStringAsFixed(1)} · ${s.cutoff.round()} Hz';

  String _exciterStatus(mpv.AexciterSettings s) =>
      '×${s.amount.toStringAsFixed(1)} · ${s.freq.round()} Hz';

  String _echoStatus(mpv.AechoSettings s) =>
      '${AechoParams.delayOf(s).round()} ms · 衰减 '
      '${_percent(AechoParams.decayOf(s))}';

  String _limiterStatus(mpv.AlimiterSettings s) =>
      '${CompressorSettingsModel.amplitudeToDb(s.limit).round()} dB · '
      '${s.attack.toStringAsFixed(1)} ms';

  String _extrastereoStatus(mpv.ExtrastereoSettings s) =>
      '差分 ×${s.m.toStringAsFixed(1)}';

  String _surroundStatus(mpv.SurroundSettings s) =>
      '${s.angle.round()}° · ${_focusText(s.focus)}';

  /// 环绕上混「聚焦」的读数，滑块与参数快照共用。
  static String _focusText(double v) => v > 0.005
      ? '前 ${v.toStringAsFixed(2)}'
      : v < -0.005
      ? '后 ${(-v).toStringAsFixed(2)}'
      : '居中';

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

    // 6 个 lavfi 效果：草稿优先，否则就是已提交的包。
    final fx = _fxDraft ?? effects;
    final sub = fx.asubboost ?? const mpv.AsubboostSettings();
    final exc = fx.aexciter ?? const mpv.AexciterSettings();
    final echo = fx.aecho ?? const mpv.AechoSettings();
    final lim = fx.alimiter ?? const mpv.AlimiterSettings();
    final st = fx.extrastereo ?? const mpv.ExtrastereoSettings();
    final su = fx.surround ?? const mpv.SurroundSettings();

    final scheme = Theme.of(context).colorScheme;
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : scheme.primary;

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '音效与均衡器'),
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // ── 均衡器 ──
          _module(
            m: _Module.eq,
            icon: Icons.equalizer,
            status: _eqStatus(eqModel),
            enabled: eqEnabled,
            onEnabledChanged: _toggleEqEnabled,
            onReset: _resetEq,
            note:
                '8 段可调频段均衡器（实时）。按住节点拖动：横向调频段'
                '中心频率，纵向调增益，双击节点将增益归零；'
                '横向滚动使用曲线顶部的专用滑动条。各频段按几何'
                '中点切分、互不重叠，并在边界处平滑衔接。',
            primary: primary,
            scheme: scheme,
            controls: [
              EqualizerCurve(
                model: eqModel,
                enabled: eqEnabled,
                onBandChanged: _onEqBandChanged,
                onDragEnd: _commitEqDraft,
              ),
            ],
            // 均衡器的正文尾部是「预设 + 重置」一行（预设是它独有的入口）。
            footer: Row(
              children: [
                PopupMenuButton<EqualizerPreset>(
                  tooltip: '预设',
                  onSelected: _applyEqPreset,
                  padding: EdgeInsets.zero,
                  position: PopupMenuPosition.under,
                  itemBuilder: (context) => [
                    for (final group in kEqualizerPresetGroups) ...[
                      // 组标题：禁用的菜单项只作分隔，不参与选择。
                      PopupMenuItem<EqualizerPreset>(
                        enabled: false,
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          group.title,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      for (final p in group.presets)
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
                  ],
                  icon: const Icon(Icons.tune, size: 18),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _resetEq,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('重置'),
                ),
              ],
            ),
          ),

          // ── 交叉回馈 ──
          _module(
            m: _Module.crossfeed,
            icon: Icons.headphones_rounded,
            status: _crossfeedStatus(cfModel),
            enabled: cfEnabled,
            onEnabledChanged: _toggleCrossfeed,
            onReset: _resetCrossfeed,
            note:
                '耳机左右声道串扰，模拟音箱的自然声场体验。'
                '强度决定对侧混音量；范围决定低架截频对应的声场宽度。'
                '对室内音箱摆放的录音有提升，对单声道/假立体声录音慎用。'
                '打开后会产生一定延迟。',
            primary: primary,
            scheme: scheme,
            controls: [
              CrossfeedDiagram(
                strength: cfModel.strength,
                range: cfModel.range,
                enabled: cfEnabled,
              ),
              _SliderRow(
                label: '强度',
                value: cfModel.strength,
                min: 0,
                max: 1,
                format: _percent,
                onChanged: (v) => _setCrossfeedDraft(cfModel.withStrength(v)),
                onChangeEnd: (_) => _commitCrossfeedDraft(),
                primary: primary,
              ),
              _SliderRow(
                label: '范围',
                value: cfModel.range,
                min: 0,
                max: 1,
                format: _percent,
                onChanged: (v) => _setCrossfeedDraft(cfModel.withRange(v)),
                onChangeEnd: (_) => _commitCrossfeedDraft(),
                primary: primary,
              ),
            ],
          ),

          // ── 压缩器 ──
          _module(
            m: _Module.compressor,
            icon: Icons.compress_rounded,
            status: _compressorStatus(compModel),
            enabled: compEnabled,
            onEnabledChanged: _toggleCompressor,
            onReset: _resetCompressor,
            note:
                '动态范围压缩（古典 / 现场录音首选）。'
                '阈值以上信号按压缩比折叠；补偿增益把压掉的响度补回来。'
                '古典 / 现场录音：低阈值 + 较高压缩比 + 中等启动/释放 '
                '+ 适当补偿增益，能让 ppp ↔ fff 整体可控。',
            primary: primary,
            scheme: scheme,
            controls: [
              CompressorCurve(
                threshold: CompressorSettingsModel.dbToAmplitude(
                  compModel.thresholdDb,
                ),
                ratio: compModel.ratio,
                makeup: CompressorSettingsModel.dbToAmplitude(
                  compModel.makeupDb,
                ),
                enabled: compEnabled,
              ),
              _SliderRow(
                label: '阈值',
                value: compModel.thresholdDb,
                min: -60,
                max: 0,
                format: (v) => '${v.round()} dB',
                onChanged: (v) =>
                    _setCompressorDraft(compModel.withThresholdDb(v)),
                onChangeEnd: (_) => _commitCompressorDraft(),
                primary: primary,
              ),
              _SliderRow(
                label: '压缩比',
                value: compModel.ratio,
                min: 1,
                max: 20,
                format: (v) => '${v.toStringAsFixed(1)}:1',
                onChanged: (v) => _setCompressorDraft(compModel.withRatio(v)),
                onChangeEnd: (_) => _commitCompressorDraft(),
                primary: primary,
              ),
              _SliderRow(
                label: '启动时间',
                value: compModel.attackMs,
                min: 0.01,
                max: 2000,
                divisions: null,
                format: (v) => '${v.round()} ms',
                onChanged: (v) =>
                    _setCompressorDraft(compModel.withAttackMs(v)),
                onChangeEnd: (_) => _commitCompressorDraft(),
                primary: primary,
              ),
              _SliderRow(
                label: '释放时间',
                value: compModel.releaseMs,
                min: 0.01,
                max: 9000,
                divisions: null,
                format: (v) => '${v.round()} ms',
                onChanged: (v) =>
                    _setCompressorDraft(compModel.withReleaseMs(v)),
                onChangeEnd: (_) => _commitCompressorDraft(),
                primary: primary,
              ),
              _SliderRow(
                label: '补偿增益',
                value: compModel.makeupDb,
                min: 0,
                max: 24,
                format: (v) => '+${v.round()} dB',
                onChanged: (v) =>
                    _setCompressorDraft(compModel.withMakeupDb(v)),
                onChangeEnd: (_) => _commitCompressorDraft(),
                primary: primary,
              ),
            ],
          ),

          // ── 低频激励 asubboost ──
          _module(
            m: _Module.subboost,
            icon: Icons.graphic_eq_rounded,
            status: _subboostStatus(sub),
            enabled: sub.enabled,
            onEnabledChanged: (v) => _toggleFx(
              _Module.subboost,
              v,
              _editSubboost((s) => s.copyWith(enabled: v)),
            ),
            onReset: () => _applyFx(
              _editSubboost((s) => mpv.AsubboostSettings(enabled: s.enabled)),
            ),
            note:
                '补回下潜不足的低频。增益是最大提升倍数，'
                '截频决定抬哪一段以下，干/湿是原声与激励声的配比，'
                '反馈让提升带上延音。耳机低频发虚时效果明显，'
                '音箱上开大容易轰头。',
            primary: primary,
            scheme: scheme,
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
          ),

          // ── 高频谐波激励 aexciter ──
          _module(
            m: _Module.exciter,
            icon: Icons.waves_rounded,
            status: _exciterStatus(exc),
            enabled: exc.enabled,
            onEnabledChanged: (v) => _toggleFx(
              _Module.exciter,
              v,
              _editExciter((s) => s.copyWith(enabled: v)),
            ),
            onReset: () => _applyFx(
              _editExciter((s) => mpv.AexciterSettings(enabled: s.enabled)),
            ),
            note:
                '生成谐波补回高频空气感。在起振频率以上生成谐波，'
                '给码率偏低、听着发闷的稿件补一点空气感。激励量是谐波强度，'
                '驱动决定谐波染色。开大了齿音会变重。',
            primary: primary,
            scheme: scheme,
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
          ),

          // ── 回声 aecho ──
          _module(
            m: _Module.echo,
            icon: Icons.repeat_rounded,
            status: _echoStatus(echo),
            enabled: echo.enabled,
            onEnabledChanged: (v) => _toggleFx(
              _Module.echo,
              v,
              _editEcho((s) => s.copyWith(enabled: v)),
            ),
            onReset: () => _applyFx(
              _editEcho((s) => mpv.AechoSettings(enabled: s.enabled)),
            ),
            note:
                '单次反射拉开空间感。延迟是回声晚多少毫秒到，'
                '衰减是回声比原声响多少。输入/输出增益分别控制进、出滤镜的'
                '电平，轻微回声能拉开空间。',
            primary: primary,
            scheme: scheme,
            controls: [
              _SliderRow(
                label: '延迟',
                // lavfi 上限 90000 ms，UI 卡在 5 s：音乐里超过几秒的回声
                // 已经不是「空间感」而是另一段歌词了，留着会调出怪东西。
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
          ),

          // ── 限幅器 alimiter ──
          _module(
            m: _Module.limiter,
            icon: Icons.speed_rounded,
            status: _limiterStatus(lim),
            enabled: lim.enabled,
            onEnabledChanged: (v) => _toggleFx(
              _Module.limiter,
              v,
              _editLimiter((s) => s.copyWith(enabled: v)),
            ),
            onReset: () => _applyFx(
              _editLimiter((s) => mpv.AlimiterSettings(enabled: s.enabled)),
            ),
            note:
                '输出天花板，防爆音。输出永远不会越过设定的'
                '天花板，防止前面几级激励把峰值顶爆。启动/释放决定它压下去和'
                '松开的快慢。作为链尾保险，前面调得激进时尤其值得开着。',
            primary: primary,
            scheme: scheme,
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
          ),

          // ── 立体声宽度 extrastereo ──
          _module(
            m: _Module.extrastereo,
            icon: Icons.unfold_more_rounded,
            status: _extrastereoStatus(st),
            enabled: st.enabled,
            onEnabledChanged: (v) => _toggleFx(
              _Module.extrastereo,
              v,
              _editExtrastereo((s) => s.copyWith(enabled: v)),
            ),
            onReset: () => _applyFx(
              _editExtrastereo(
                (s) => mpv.ExtrastereoSettings(enabled: s.enabled),
              ),
            ),
            note:
                '放大左右差信号拉宽声场。把左右声道的差信号'
                '放大后叠回两声道，直接拉宽声场：系数为正是增宽，为负会反相'
                '收窄。单声道或假立体声录音加宽只会更糊。',
            primary: primary,
            scheme: scheme,
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
          ),

          // ── 环绕上混 surround ──
          _module(
            m: _Module.surround,
            icon: Icons.surround_sound_rounded,
            status: _surroundStatus(su),
            enabled: su.enabled,
            onEnabledChanged: (v) => _toggleFx(
              _Module.surround,
              v,
              _editSurround((s) => s.copyWith(enabled: v)),
            ),
            onReset: () => _applyFx(
              _editSurround((s) => mpv.SurroundSettings(enabled: s.enabled)),
            ),
            note:
                '立体声上混 5.1 再交回输出端。'
                '角度是声场旋转方向，聚焦在前后声像之间取舍，'
                '窗重叠与平滑控制变换的连续性。'
                '相位会被改写，耳机上听感变化最大，且会加重 CPU 负担。',
            primary: primary,
            scheme: scheme,
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
                format: _focusText,
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
          ),
        ],
      ),
    );
  }

  /// 组装一个折叠模块：头部（标题取自 [m]、展开态按 [_isOpen] 推导）
  /// + 正文（[controls] → [footer] / 重置 → [note]）。
  ///
  /// 9 个模块全部走这里，结构差异只允许落在参数上——这是「统一风格」
  /// 能被守住的原因：新增一个效果只要再填一次这些参数，不可能长歪。
  Widget _module({
    required _Module m,
    required IconData icon,
    required String status,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required VoidCallback onReset,
    required String note,
    required Color primary,
    required ColorScheme scheme,
    required List<Widget> controls,
    Widget? footer,
  }) {
    return _FxModule(
      icon: icon,
      title: m.title,
      status: status,
      enabled: enabled,
      expanded: _isOpen(m, enabled),
      primary: primary,
      scheme: scheme,
      onEnabledChanged: onEnabledChanged,
      onExpandedChanged: (v) => _setOpen(m, v),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...controls,
          footer ?? _resetRow(onReset),
          _note(note, scheme),
        ],
      ),
    );
  }

  Widget _resetRow(VoidCallback onReset) => Row(
    children: [
      const Spacer(),
      TextButton.icon(
        onPressed: onReset,
        icon: const Icon(Icons.restart_alt, size: 18),
        label: const Text('重置'),
      ),
    ],
  );

  Widget _note(String text, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
    ),
  );

  /// 0..1 → 百分比读数，几个效果的干湿 / 衰减 / 比例共用。
  static String _percent(double v) => '${(v * 100).round()}%';
}

/// 页面上的 9 个折叠模块，也是展开态覆盖表 [_AudioDspPageState._open] 的键。
///
/// 标题放这里而不是散在 build 里：头部文案与折叠状态的键**必须**指向
/// 同一个模块，分开写迟早会漏改一边。
enum _Module {
  eq('均衡器'),
  crossfeed('交叉回馈'),
  compressor('压缩器'),
  subboost('低频激励'),
  exciter('高频谐波激励'),
  echo('回声'),
  limiter('限幅器'),
  extrastereo('立体声宽度'),
  surround('环绕上混');

  const _Module(this.title);

  /// 头部第一行。
  final String title;
}

/// 一个同构折叠模块：**头部**（图标 · 名称 · 参数快照 · 展开箭头 · 启用
/// 开关）+ **可折叠正文**。
///
/// 页面上 9 个模块只有正文内容不同，头部结构与交互完全一致：
///
/// - **两个互不重叠的手势目标**：左侧整块（图标 / 标题 / 快照）与右端
///   箭头都只做展开 / 收起，`Switch` 独立在点击区**之外**。开关若嵌进
///   同一个 InkWell，点开关会顺带触发一次展开——手势竞技场里两个
///   `TapGestureRecognizer` 抢同一个指针，行为依赖命中顺序，不能靠运气。
/// - **收起 = 正文整棵卸载**，不是 `opacity: 0`：收起的模块不该占布局，
///   更不该让 `Slider` / `EqualizerCurve` 的手势区继续留在命中测试里
///   （等价于 `ExpansionTile` 的 `maintainState: false`）。
/// - 高度过渡走 [AnimatedSize]，外面套一层 `ClipRect` 兜住收缩过程中
///   正文绘制超出的部分。
class _FxModule extends StatelessWidget {
  const _FxModule({
    required this.icon,
    required this.title,
    required this.status,
    required this.enabled,
    required this.expanded,
    required this.primary,
    required this.scheme,
    required this.onEnabledChanged,
    required this.onExpandedChanged,
    required this.body,
  });

  final IconData icon;
  final String title;

  /// 头部第二行：当前参数快照（开关已经表达了开 / 关，这里不重复）。
  final String status;
  final bool enabled;
  final bool expanded;
  final Color primary;
  final ColorScheme scheme;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onExpandedChanged;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onVariant = scheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 头部 ──
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  onTap: () => onExpandedChanged(!expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 22, color: primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: onVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Switch(value: enabled, onChanged: onEnabledChanged),
              // 展开箭头单独一个点击区，与 Switch 平级，不抢手势。
              InkWell(
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                onTap: () => onExpandedChanged(!expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 8, 8),
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: onVariant,
                  ),
                ),
              ),
            ],
          ),

          // ── 正文 ──
          if (expanded) const Divider(height: 1, indent: 12, endIndent: 12),
          ClipRect(
            child: AnimatedSize(
              duration: AppTokens.standardDuration,
              curve: AppTokens.standardEasing,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: body,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
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
