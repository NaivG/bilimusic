import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

/// 音频输出页的**纯逻辑**：延迟量程与格式化、DAC 采样率档位表、
/// 输出设备列表的并集去重。
///
/// 刻意不碰 Flutter（CLAUDE.md「新增可测逻辑优先写成纯 Dart 类」），
/// UI 与 `DualAudioService` 都从这里取数，回归测试在
/// `test/settings/audio_output_options_test.dart`。

/// 音频延迟的量程与步进（毫秒）。
///
/// 正数＝声音延后。蓝牙 A2DP 的唇音补偿常见取值在 ±250ms 以内，
/// 两端各留出余量即可，再大只会把人拖晕。
const int kAudioDelayMinMs = -500;
const int kAudioDelayMaxMs = 500;

/// 延迟滑块的分度数：(max - min) / divisions = 10ms 一格，
/// 拖动时读数按 10ms 跳变，不会出现 `+137 ms` 这种没法复现的值。
const int kAudioDelayDivisions = 100;

/// 把延迟夹进 [kAudioDelayMinMs] ~ [kAudioDelayMaxMs]。
int clampAudioDelay(int ms) => ms.clamp(kAudioDelayMinMs, kAudioDelayMaxMs);

/// 延迟读数：`+120 ms` / `0 ms` / `-80 ms`。
///
/// 正数**必须**带 `+`——滑块从中点向两侧走，没有符号的话「往左拖」
/// 显示的数字反而在变大，用户会以为控件坏了。
String formatAudioDelay(int ms) {
  final v = clampAudioDelay(ms);
  if (v > 0) return '+$v ms';
  return '$v ms';
}

/// 一个 DAC 采样率档位：`rate` 是喂给 `setAudioSampleRate` 的值
/// （`0` 即 mpv 的「自动」），`label` 是下拉里的文案。
typedef SampleRateOption = ({int rate, String label});

/// 强制 DAC 采样率的可选档位，**顺序即下拉顺序**。
///
/// 0 走 mpv 的 auto（跟随音源，不做多余重采样）；其余按采样率升序。
/// 176.4 / 192k 是 hi-res DAC 的常见上限，再往上（384k）绝大多数
/// 桌面声卡根本不支持，选了只会让 AO 起不来——不给这个选项。
const List<SampleRateOption> kDacSampleRates = [
  (rate: 0, label: '自动（跟随音源）'),
  (rate: 44100, label: '44.1 kHz'),
  (rate: 48000, label: '48 kHz'),
  (rate: 88200, label: '88.2 kHz'),
  (rate: 96000, label: '96 kHz'),
  (rate: 176400, label: '176.4 kHz'),
  (rate: 192000, label: '192 kHz'),
];

/// 把若干份设备列表合成一份：按 `name` 去重、保持**首见顺序**。
///
/// 调用方是 `DualAudioService`——A/B 两个播放器各报一份
/// `audio-device-list`，两份内容几乎相同但顺序可能不同，直接拼接会让
/// 下拉每次 crossfade 后抖一下。`mpv.Device.==` 本来就按 `name` 比较
/// （见 mpv_audio_kit 的 `device.dart`），这里再显式按 name 归并一次，
/// 避免依赖第三方的相等语义。
///
/// **`auto` 与空名在这里被丢掉**：`auto` 是 mpv 的哨兵值不是真实设备
/// （`player_state.dart` 的 `_kDefaultDevices` 启动时就是 `[auto]`），
/// UI 自己会渲染一行「自动（系统默认）」，留着它下拉里会出现两个自动。
/// 顺带的效果是「mpv 还没报真设备」这一态归一成空列表，页面据此显示
/// 「设备列表尚未就绪」。
List<mpv.Device> mergeAudioDevices(List<List<mpv.Device>> groups) {
  final seen = <String>{};
  final out = <mpv.Device>[];
  for (final group in groups) {
    for (final d in group) {
      if (d.name.isEmpty || d.name == kAutoDeviceName) continue;
      if (!seen.add(d.name)) continue;
      out.add(d);
    }
  }
  return out;
}

/// mpv「跟随系统」的设备名。
const String kAutoDeviceName = 'auto';

/// 把两种写法的「跟随系统」归一：设置里存空串，mpv 回读是 `'auto'。
///
/// 不归一的话「我选了耳机、mpv 回退到自动」这条提示会永远判不出来，
/// 因为两边的词表根本对不上。
String normalizeDeviceName(String name) =>
    (name.isEmpty || name == kAutoDeviceName) ? '' : name;
