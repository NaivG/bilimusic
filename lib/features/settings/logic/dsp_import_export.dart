import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import 'package:bilimusic/features/player/logic/effects_codec.dart';

/// DSP 配置（音频效果包）的导入 / 导出。
///
/// 页面上同一个音频效果包 [mpv.AudioEffects] 既支持「一次性整包」也支持
/// 「逐模块」读写。
///
/// 单项的载体是同样的 [EffectsCodec]，只是解出全包后只覆盖目标那一栏——
/// 见 [DspConfigImportExport.applyModule]。这样文件格式与现有
/// `player_audio_effects_v1` 落盘 JSON 形状一致。
class DspConfigImportExport {
  DspConfigImportExport._();

  /// 文件 envelope 的格式版本。任何不匹配这个数字的旧 / 新文件都拒绝导入。
  /// 升级时改这里，并相应改 [EffectsCodec] 的解码逻辑兼容旧数据。
  static const int envelopeVersion = 1;

  /// 单项导出 / 导入用到的模块键与 [mpv.AudioEffects] 字段的映射。
  ///
  /// 「键」即是 codec 输出 JSON 里的那一栏，与 codec 的 encode/decode 双向
  /// 同步：改 [EffectsCodec] 时这两条表要一起更新。
  ///
  /// 排序按页面 9 个模块从上到下的展示顺序，导入 / 导出菜单就照这个序。
  static const List<DspModuleExport> modules = [
    DspModuleExport(key: 'aneq', label: '均衡器', apply: _applyAneq),
    DspModuleExport(key: 'crossfeed', label: '交叉回馈', apply: _applyCrossfeed),
    DspModuleExport(key: 'comp', label: '压缩器', apply: _applyCompressor),
    DspModuleExport(key: 'subboost', label: '低频激励', apply: _applySubboost),
    DspModuleExport(key: 'exciter', label: '高频谐波激励', apply: _applyExciter),
    DspModuleExport(key: 'echo', label: '回声', apply: _applyEcho),
    DspModuleExport(key: 'limiter', label: '限幅器', apply: _applyLimiter),
    DspModuleExport(key: 'stereo', label: '立体声宽度', apply: _applyExtrastereo),
    DspModuleExport(key: 'surround', label: '环绕上混', apply: _applySurround),
  ];

  /// 反查：key → 元数据。导入失败时用得上。
  static DspModuleExport? moduleByKey(String key) {
    for (final m in modules) {
      if (m.key == key) return m;
    }
    return null;
  }

  // ── 导出 ──────────────────────────────────────────────────────────────

  /// 导出一个完整的 [mpv.AudioEffects] 包。
  ///
  /// 用 envelope 包一层而不是裸 codec 输出，避免用户误把 prefs 备份当 export
  /// 再次 import 时被「整包整包地覆盖意料外的字段」。
  static String encodeAll(mpv.AudioEffects effects) {
    final body = <String, Object?>{
      'kind': 'full',
      'version': envelopeVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'config': EffectsCodec.encode(effects),
    };
    return jsonEncode(body);
  }

  /// 导出某个模块的当前配置。
  ///
  /// 注意这里**不**临时构造一个只剩 target 槽位的 effects 再 encode 整包，
  /// 而是直接从当前 effects 的 codec 输出里切片——多走的字段不存在，
  /// 切到的也只是 `EffectsCodec.encode` 已声明的字段，不会引入隐藏耦合。
  static String encodeModule(mpv.AudioEffects effects, DspModuleExport m) {
    final full = EffectsCodec.encode(effects);
    final section = full[m.key];
    final body = <String, Object?>{
      'kind': 'module',
      'version': envelopeVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'module': m.key,
      'moduleLabel': m.label,
      'config': section is Map ? section : const <String, Object?>{},
    };
    return jsonEncode(body);
  }

  /// 导出文件建议的文件名前缀（「模块」 / 「完整」）在调用方决定时间戳。
  static String fileNamePrefixFull() => 'bilimusic_dsp_all';
  static String fileNamePrefixModule(DspModuleExport m) =>
      'bilimusic_dsp_${m.key}';

  // ── 导入 ──────────────────────────────────────────────────────────────

  /// 解析后的 envelope 形态。
  ///
  /// 「整包」与「单项」两种 kind 都汇集成同一个数据结构，调用方按
  /// [isFull] 分流。失败抛 [DspConfigFormatException]。
  static DspEnvelope decodeEnvelope(String content) {
    Object? raw;
    try {
      raw = jsonDecode(content);
    } on FormatException catch (e) {
      throw DspConfigFormatException('文件不是合法的 JSON：${e.message}');
    }
    if (raw is! Map) {
      throw const DspConfigFormatException('文件根节点不是对象');
    }
    final map = raw.cast<String, Object?>();

    final version = map['version'];
    if (version is! int || version != envelopeVersion) {
      throw DspConfigFormatException(
        '不支持的格式版本：$version（当前支持 $envelopeVersion）',
      );
    }

    final kind = map['kind'];
    final config = map['config'];
    if (config is! Map) {
      throw const DspConfigFormatException('缺少 config 字段');
    }

    return switch (kind) {
      'full' => DspEnvelope._(
        isFull: true,
        module: null,
        config: config.cast<String, Object?>(),
      ),
      'module' => () {
        final moduleKey = map['module'];
        if (moduleKey is! String) {
          throw const DspConfigFormatException('module 字段缺失或类型错误');
        }
        final module = moduleByKey(moduleKey);
        if (module == null) {
          throw DspConfigFormatException('未知模块：$moduleKey');
        }
        final section = config[moduleKey];
        if (section is! Map) {
          throw DspConfigFormatException('config 里没有 $moduleKey 一栏');
        }
        return DspEnvelope._(
          isFull: false,
          module: module,
          config: section.cast<String, Object?>(),
        );
      }(),
      _ => throw DspConfigFormatException('未知 kind：$kind'),
    };
  }

  /// 整包导入：直接交给 codec 走全字段，没有额外路径。
  static mpv.AudioEffects decodeFull(DspEnvelope env) {
    assert(env.isFull, '单模块 envelope 不能走整包解码');
    return EffectsCodec.decode(env.config);
  }

  /// 单项导入：在 [base] 上只覆盖目标模块。
  static mpv.AudioEffects applyModule(mpv.AudioEffects base, DspEnvelope env) {
    assert(!env.isFull, '整包 envelope 必须走 setEffects，不能局部覆盖');
    final m = env.module!;
    final partial = <String, Object?>{m.key: env.config};
    final patched = EffectsCodec.decode(partial);
    return m.apply(base, patched);
  }

  // ── 单模块 apply helpers ─────────────────────────────────────────────
  //
  // 写成顶层静态函数方便 [DspModuleExport] 的 const 构造期引用。
  // 把 [patched] 里对应槽位的非空实例 copyWith 回 [base]，其它槽位
  // 完全不动。
  static mpv.AudioEffects _applyAneq(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.anequalizer == null
      ? base
      : base.copyWith(anequalizer: patched.anequalizer);

  static mpv.AudioEffects _applyCrossfeed(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.crossfeed == null
      ? base
      : base.copyWith(crossfeed: patched.crossfeed);

  static mpv.AudioEffects _applyCompressor(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.acompressor == null
      ? base
      : base.copyWith(acompressor: patched.acompressor);

  static mpv.AudioEffects _applySubboost(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.asubboost == null
      ? base
      : base.copyWith(asubboost: patched.asubboost);

  static mpv.AudioEffects _applyExciter(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.aexciter == null
      ? base
      : base.copyWith(aexciter: patched.aexciter);

  static mpv.AudioEffects _applyEcho(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.aecho == null ? base : base.copyWith(aecho: patched.aecho);

  static mpv.AudioEffects _applyLimiter(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.alimiter == null
      ? base
      : base.copyWith(alimiter: patched.alimiter);

  static mpv.AudioEffects _applyExtrastereo(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.extrastereo == null
      ? base
      : base.copyWith(extrastereo: patched.extrastereo);

  static mpv.AudioEffects _applySurround(
    mpv.AudioEffects base,
    mpv.AudioEffects patched,
  ) => patched.surround == null
      ? base
      : base.copyWith(surround: patched.surround);
}

/// 单项导出的元数据：UI 上每个模块一行，导出 / 导入都靠这张表分发。
@immutable
class DspModuleExport {
  const DspModuleExport({
    required this.key,
    required this.label,
    required this.apply,
  });

  /// EffectsCodec 输出 JSON 里的那一栏（与 codec 同步）。
  final String key;

  /// UI 上显示的模块名。
  final String label;

  /// 单项导入时把目标栏 copyWith 回 base effect 上的回调。
  final mpv.AudioEffects Function(mpv.AudioEffects, mpv.AudioEffects) apply;
}

/// 解析后的导入信封。
///
/// 由 [DspConfigImportExport.decodeEnvelope] 产出，按 [isFull] 分流：
/// - true  走 [DspConfigImportExport.decodeFull] 整包解码；
/// - false 用 [module] + [config] 走 [DspConfigImportExport.applyModule]。
@immutable
class DspEnvelope {
  const DspEnvelope._({
    required this.isFull,
    required this.module,
    required this.config,
  });

  /// true 表示整包，false 表示单模块（[module] 非 null）。
  final bool isFull;

  /// 单模块导入时对应的元数据；整包导入时为 null。
  final DspModuleExport? module;

  /// 解码后的 codec 配置。
  ///
  /// 整包：直接喂给 [EffectsCodec.decode]；单模块：只有一项（即 [module!.key]）。
  final Map<String, Object?> config;
}

/// 文件格式不合法 / 版本不支持 / 缺字段等「结构性」错误。
class DspConfigFormatException implements Exception {
  const DspConfigFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
