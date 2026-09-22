import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;
import 'package:shared_preferences/shared_preferences.dart';

import 'effects_codec.dart';

/// 音频效果（DSP af 链）的**独立**持久化与状态仓库。
///
/// 职责只有两件：
/// - 启动时从盘上读回 [mpv.AudioEffects]（[initialize]，幂等）；
/// - 运行时接收新值（[update]），同步内存状态并落盘。
///
/// 引擎应用**不在这里**——链路是 调用方 → PlayerCoordinator →
/// DualAudioService（A/B 两路播放器），服务只管「值 + 落盘」。
/// 本类是效果包的事实来源：引擎写入失败只记日志，下次启动重放。
class AudioEffectsService {
  /// 独立落盘键。不要挪进 SettingsManager 的键空间。
  static const String prefsKey = 'player_audio_effects_v1';

  /// 当前生效的效果包。UI 通过 provider 桥接监听它
  /// （写法见 `effects_providers.dart`）。
  final ValueNotifier<mpv.AudioEffects> effects =
      ValueNotifier<mpv.AudioEffects>(const mpv.AudioEffects());

  bool _initialized = false;

  /// 是否已有运行时写入。启动竞态保险：若 [update] 先于读盘完成到达，
  /// 读回的旧值不得覆盖用户刚提交的新值。
  bool _dirty = false;

  /// 从 SharedPreferences 读回效果包。幂等；损坏 / 非预期的 blob
  /// 退回默认包，绝不让启动路径抛错。
  ///
  /// 返回后 [effects] **始终是「补齐形状」**：curated 槽位全部非 null
  /// （没配过的是 enabled=false 的默认实例）。null 槽位与禁用实例在
  /// af 链上等价，但补齐后 UI 可以直接读 `state.bass!.gain`，也保证
  /// 编码→解码 roundtrip 的整包相等判断稳定。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    mpv.AudioEffects loaded;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      final decoded = (raw == null || raw.isEmpty) ? null : jsonDecode(raw);
      loaded = decoded is Map
          ? EffectsCodec.decode(decoded.cast<String, Object?>())
          : EffectsCodec.decode(const {});
      debugPrint('[AudioEffectsService] 音频效果包已就绪');
    } catch (e) {
      debugPrint('[AudioEffectsService] 恢复音频效果包失败（按默认值继续）: $e');
      loaded = EffectsCodec.decode(const {});
    }
    if (_dirty) return; // 读盘期间已有运行时写入，旧值靠边
    effects.value = loaded;
  }

  /// 接收新的效果包：同步内存状态 + 落盘（异步，不抛给调用方）。
  ///
  /// 与当前值相等时直接跳过（[mpv.AudioEffects] 的 == 按字段深比较），
  /// 重复提交同一份配置不产生写盘噪音。滑动条频繁拖动应由 UI 侧用
  /// 本地 draft 承接 onChange、onChangeEnd 再提交一次（AudioEffects
  /// 不可变，每次修改都是整包 copyWith）。
  Future<void> update(mpv.AudioEffects next) async {
    if (next == effects.value) return;
    _dirty = true;
    effects.value = next;
    await _persist(next);
  }

  Future<void> _persist(mpv.AudioEffects next) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(EffectsCodec.encode(next)));
    } catch (e) {
      debugPrint('[AudioEffectsService] 保存音频效果包失败: $e');
    }
  }

  void dispose() {
    effects.dispose();
  }
}
