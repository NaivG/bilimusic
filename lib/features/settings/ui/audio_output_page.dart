import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/app/shells/shell_page_manager.dart';
import 'package:bilimusic/features/player/audio_output_providers.dart';
import 'package:bilimusic/features/settings/logic/audio_output_options.dart';
import 'package:bilimusic/features/settings/settings_provider.dart';
import 'package:bilimusic/shared/theme/app_tokens.dart';
import 'package:bilimusic/shared/utils/platform_helper.dart';
import 'package:bilimusic/shared/widgets/auto_appbar.dart';

/// 音频输出（设置 → 音频）。
///
/// 四个开关项 + 免责说明。
///
/// | 设置项 | mpv 属性 | 重建 AO？ |
/// | --- | --- | --- |
/// | 音频延迟 | `audio-delay` | 否 |
/// | 硬件直通（独占） | `audio-exclusive` | 是 |
/// | 强制 DAC 采样率 | `audio-samplerate` | 是 |
/// | 输出设备 | `audio-device` | 是 |
///
/// 「重建 AO」= 短暂静音，所以下发一律**逐字段**走
/// `audioOutputCommandsProvider`，绝不打包成一次 apply——只想改延迟却把
/// 设备重开一遍是没道理的。
///
/// 写入链路：UI → PlayerCoordinator（先落 SettingsManager 再推引擎）→
/// DualAudioService（A/B 两路）。引擎写失败只在两路全挂时抛，这里转 SnackBar；
/// 此时设置已经落盘，下次启动由 `PlayerCoordinator.initialize` 重放。
class AudioOutputPage extends ConsumerStatefulWidget {
  const AudioOutputPage({super.key});

  @override
  ConsumerState<AudioOutputPage> createState() => _AudioOutputPageState();
}

class _AudioOutputPageState extends ConsumerState<AudioOutputPage> {
  /// 拖动中的延迟本地草稿；null 表示当前没有未提交的编辑。
  ///
  /// 滑动条每帧都会回调，**不能逐帧下发**：每次写都是「落盘 + 推 A/B 两路
  /// 两次 FFI」，既刷写盘噪音又没意义。`onChangeEnd` 提交一次即可
  /// （同 `AudioDspPage` 顶部那段提交节奏的取舍）。
  int? _delayDraft;

  @override
  void initState() {
    super.initState();
    // 弹窗不能发生在 build 里（会撞 "setState() or markNeedsBuild()
    // called during build"），推迟到首帧之后。
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureDisclaimer());
  }

  /// 首次进入的免责闸门。同意 → 写设置、留在本页；不同意 → 退回设置页。
  ///
  /// 弹窗 `barrierDismissible: false`：这是个必须二选一的门槛，
  /// 点空白处「既没同意也没离开」会让页面停在一个说不清的状态。
  Future<void> _ensureDisclaimer() async {
    if (!mounted) return;
    if (ref.read(settingsProvider).audioOutputDisclaimerAccepted) return;

    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 36),
        title: const Text('高级音频输出 · 免责说明'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 硬件直通（独占模式）会锁死输出设备，期间其他应用将没有声音。'),
            SizedBox(height: 10),
            Text('2. 强制采样率、切换设备可能与硬件不兼容，出现无声、爆音，或需要重启应用。'),
            SizedBox(height: 10),
            Text('3. 以上均为高级音频选项，因配置导致的问题请自行承担。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (agreed == true) {
      await ref.read(settingsProvider.notifier).acceptAudioOutputDisclaimer();
      return;
    }

    // 外壳导航是 ShellPageManager 的自定义栈，**不是** Navigator.pop。
    // SnackBar 走 MaterialApp 的全局 messenger，页面被 AnimatedSwitcher
    // 换掉之后照常显示——所以先弹再退栈，反过来会看不到。
    _snack('需先同意免责说明，才能调整音频输出');
    ShellPageManager.instance.pop();
  }

  /// 跑一次引擎写入。两路播放器全挂才抛（见 DualAudioService._broadcast），
  /// 这里转成 SnackBar 并返回 `false`，让调用方别再补一句「成功了」。
  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      _snack('设置未生效：$e');
      return false;
    }
  }

  /// 弹提示。**收口成一个同步方法**：`mounted` 判断与 `context` 使用必须
  /// 落在同一个同步块里——跨 await 之后各自再写一遍，会被
  /// `use_build_context_synchronously` 判成「拿了个没 guard 的 context」。
  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final devices = ref.watch(audioDevicesProvider);
    final activeDevice = ref.watch(audioDeviceProvider);
    final commands = ref.read(audioOutputCommandsProvider.notifier);

    final scheme = Theme.of(context).colorScheme;
    final primary = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : scheme.primary;

    final delayMs = _delayDraft ?? settings.audioDelayMs;

    // 已存的设备可能已经不在清单里（拔了 / 改名了）。DropdownButton 的
    // value 必须命中某个 item 否则直接断言，所以回落到「自动」，
    // 由下面的回退提示把真实情况讲清楚。
    final deviceNames = ['', ...devices.map((d) => d.name)];
    final storedDevice = normalizeDeviceName(settings.audioDeviceName);
    final selectedDevice = deviceNames.contains(storedDevice)
        ? storedDevice
        : '';
    // 实际生效的设备 ≠ 存的偏好 = mpv 回退了（设备被拔 / 不可用）。
    // 两个词表先各自归一（设置存空串，mpv 回读是 'auto'）再比。
    final fellBack = normalizeDeviceName(activeDevice.name) != storedDevice;

    // 落盘值不在档位表里（手改过 prefs）时退回「自动」，
    // 否则 DropdownButton 的 value 命不中 item 会直接断言。
    final storedRate =
        kDacSampleRates.any((o) => o.rate == settings.audioSampleRate)
        ? settings.audioSampleRate
        : 0;

    return Scaffold(
      appBar: AutoAppBar.generateAppBar(title: '音频输出'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // ── 音频延迟 ──
          _card(
            icon: Icons.timelapse,
            title: '音频延迟',
            value: formatAudioDelay(delayMs),
            primary: primary,
            scheme: scheme,
            note: '正值＝声音延后，负值＝声音提前。用来补蓝牙耳机 / 外接声卡的固有延迟。',
            child: Slider(
              value: delayMs.toDouble().clamp(
                kAudioDelayMinMs.toDouble(),
                kAudioDelayMaxMs.toDouble(),
              ),
              min: kAudioDelayMinMs.toDouble(),
              max: kAudioDelayMaxMs.toDouble(),
              divisions: kAudioDelayDivisions,
              label: formatAudioDelay(delayMs),
              onChanged: (v) => setState(() => _delayDraft = v.round()),
              onChangeEnd: (v) {
                setState(() => _delayDraft = null);
                _run(() => commands.setDelayMs(v.round()));
              },
            ),
          ),

          // ── 硬件直通 ──
          _card(
            icon: Icons.cable,
            title: '硬件直通（独占模式）',
            primary: primary,
            scheme: scheme,
            note: PlatformHelper.isDesktop
                ? '绕过系统混音器和重采样直接写硬件，实现 bit-perfect 输出。'
                      '独占期间其他应用将没有声音，关掉立即恢复。'
                : '仅 Windows / Linux / macOS 支持；移动端由系统音频服务接管。',
            trailing: Switch(
              value: settings.audioExclusive,
              onChanged: PlatformHelper.isDesktop
                  ? (v) => _run(() => commands.setExclusive(v))
                  : null,
            ),
          ),

          // ── 强制采样率 ──
          _card(
            icon: Icons.speed,
            title: '强制 DAC 采样率',
            primary: primary,
            scheme: scheme,
            note:
                '默认跟随音源、不做多余重采样。'
                '要 bit-perfect 就选与音源一致的档位，'
                '选了硬件不支持的档位可能直接无声。',
            trailing: DropdownButton<int>(
              value: storedRate,
              isExpanded: false,
              items: [
                for (final o in kDacSampleRates)
                  DropdownMenuItem<int>(value: o.rate, child: Text(o.label)),
              ],
              onChanged: (v) {
                if (v == null) return;
                _run(() => commands.setSampleRate(v));
              },
            ),
          ),

          // ── 输出设备 ──
          _card(
            icon: Icons.speaker_group,
            title: '输出设备',
            primary: primary,
            scheme: scheme,
            note: fellBack
                ? '当前实际输出：${_deviceLabel(normalizeDeviceName(activeDevice.name), devices)}'
                      '（请求的设备不可用，已回退）'
                : devices.isEmpty
                ? '设备列表尚未就绪——mpv 初始化完成后自动填充。'
                : '切换会重建音频输出，当前曲目可能出现短暂静音。',
            trailing: DropdownButton<String>(
              value: selectedDevice,
              isExpanded: false,
              // 列表没就绪时禁用而不是给一个空下拉：空下拉看起来像
              // 「系统只有自动一个设备」，那是假信息。
              onChanged: devices.isEmpty
                  ? null
                  : (v) {
                      if (v == null) return;
                      _run(() => commands.setDeviceName(v));
                    },
              selectedItemBuilder: (ctx) => [
                for (final name in deviceNames)
                  _deviceItem(_deviceLabel(name, devices)),
              ],
              items: [
                for (final name in deviceNames)
                  DropdownMenuItem<String>(
                    value: name,
                    child: _deviceItem(_deviceLabel(name, devices)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── 恢复默认 ──
          Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  if (await _run(() => commands.resetDefaults())) {
                    _snack('已恢复默认输出设置');
                  }
                },
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('恢复默认'),
              ),
            ],
          ),
          _note(
            '恢复默认只重置上面四项，不影响已同意的免责说明。',
            scheme,
          ),
        ],
      ),
    );
  }

  /// 一张设置卡：图标 · 标题 · 当前值 · 控件 · 说明。
  ///
  /// **没有折叠头、没有展开箭头**——本页四项都是一眼可读的开关，
  /// 藏进折叠里只会让人以为还有东西没看见。
  Widget _card({
    required IconData icon,
    required String title,
    String? value,
    Widget? trailing,
    Widget? child,
    required String note,
    required Color primary,
    required ColorScheme scheme,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                    if (value != null)
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
          if (child != null) ...[const SizedBox(height: 4), child],
          _note(note, scheme),
        ],
      ),
    );
  }

  Widget _note(String text, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
    ),
  );

  /// 设备下拉项的固定宽度 + 省略号：设备描述能长到
  /// 「扬声器 (Realtek(R) Audio)」这种长度，不裁会在卡片里把标题挤没。
  Widget _deviceItem(String label) => SizedBox(
    width: 200,
    child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
  );

  String _deviceLabel(String name, List<mpv.Device> devices) {
    if (name.isEmpty) return '自动（系统默认）';
    for (final d in devices) {
      if (d.name == name) {
        return d.description.isEmpty || d.description == name
            ? name
            : d.description;
      }
    }
    return name;
  }
}
