import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:bilimusic/core/storage/database.dart';
import 'package:bilimusic/domain/taste_profile.dart';
import 'package:bilimusic/features/playlist/playlist_service.dart';
import 'package:bilimusic/features/taste/logic/profile_builder.dart';
import 'package:bilimusic/features/taste/logic/text_normalizer.dart';
import 'package:bilimusic/features/taste/services/taste_worker.dart';

/// 音乐画像服务：收集正信号样本 → 建画像 → 落盘 kv 表 → 24h 节流。
///
/// 样本来源（v1 只用正信号，负反馈按设计决议不接入）：
/// - 播放历史：按新鲜度衰减加权（越近越重）
/// - 收藏：固定加成
/// - 用户歌单名 / 歌单标签名：[forcedTexts]，最高权重（用户亲手写的词）
///
/// 分词放在常驻 worker isolate（[TasteWorker]）里跑，主 isolate 只负责收集
/// 样本、落盘与读盘；worker 空闲一段时间后自行退出，模型内存随之回收。
///
/// 生命周期：Provider 在 `app_providers.dart` 创建，worker 由 Provider 释放；
/// 本服务自身无资源需要释放。
class TasteProfileService {
  TasteProfileService({
    required PlaylistService playlistService,
    TasteProfileBuilder? builder,
    TasteWorker? worker,
    AppDatabase? db,
  }) : this._(playlistService, builder, worker, db ?? AppDatabase.instance);

  TasteProfileService._(
    this._playlistService,
    this._builder,
    this._worker,
    this._db,
  );

  static const String _storageKey = 'taste_profile_v1';
  static const Duration _ttl = Duration(hours: 24);

  /// 样本权重下限：历史尾部的歌不至于完全没话语权。
  static const double _historyFloor = 0.15;

  final PlaylistService _playlistService;

  /// 就地构建（测试注入）：非 null 时不进 worker。
  final TasteProfileBuilder? _builder;

  /// 常驻 worker isolate：生产环境唯一的画像构建执行器。
  final TasteWorker? _worker;
  final AppDatabase _db;

  TasteProfile? _cached;

  /// 在飞的重建：首页与画像页可能同时触发，共享同一次构建。
  Future<TasteProfile>? _building;

  /// 内存中的画像（可能是 null：还没 ensureFresh 过）。
  TasteProfile? get cached => _cached;

  /// 取一份「够新」的画像：内存 → 盘上 → 重建，24h 节流。
  ///
  /// 空画像（样本不足建不出关键词）不享受节流——冷启动装机后
  /// 第一次听歌就该能把画像建起来。
  Future<TasteProfile> ensureFresh({bool force = false}) async {
    final now = DateTime.now();
    final memory = _cached;
    if (!force && memory != null && _isFresh(memory, now)) return memory;

    if (!force) {
      final stored = await _load();
      if (stored != null && _isFresh(stored, now) && !stored.isEmpty) {
        return _cached = stored;
      }
    }
    return rebuild();
  }

  /// 立即重建画像并落盘；并发调用共享同一次构建。
  Future<TasteProfile> rebuild() {
    final inFlight = _building;
    if (inFlight != null) return inFlight;
    final future = _rebuild().whenComplete(() => _building = null);
    _building = future;
    return future;
  }

  Future<TasteProfile> _rebuild() async {
    final now = DateTime.now();
    final profile = await _build(_collectSamples(), _collectForcedTexts(), now);
    _cached = profile;
    try {
      await _db.kvSet(_storageKey, jsonEncode(profile.toJson()));
    } catch (e) {
      debugPrint('[TasteProfileService] 画像落盘失败: $e');
    }
    return profile;
  }

  Future<TasteProfile> _build(
    List<ProfileSample> samples,
    List<String> forcedTexts,
    DateTime now,
  ) {
    final builder = _builder;
    if (builder != null) {
      return builder.build(samples, forcedTexts: forcedTexts, now: now);
    }
    final worker = _worker;
    if (worker == null) {
      throw StateError('TasteProfileService 需要在 builder 或 worker 中二选一');
    }
    return worker.buildProfile(samples, forcedTexts: forcedTexts, now: now);
  }

  bool _isFresh(TasteProfile p, DateTime now) =>
      !p.updatedAt.isAfter(now) && now.difference(p.updatedAt) < _ttl;

  /// 历史（新鲜度衰减）+ 收藏（加成）→ 样本，按 Music.key 去重取最高权重。
  List<ProfileSample> _collectSamples() {
    final weightByKey = <String, double>{};
    final textByKey = <String, String>{};

    final history = _playlistService.playHistorySnapshot;
    for (var i = 0; i < history.length; i++) {
      final m = history[i];
      final w = math.max(_historyFloor, 1.0 / (1 + i * 0.08));
      if (w > (weightByKey[m.key] ?? 0)) {
        weightByKey[m.key] = w;
        textByKey[m.key] = tasteText(m);
      }
    }

    for (final m in _playlistService.favoritesSnapshot) {
      const favWeight = 1.5;
      if (favWeight > (weightByKey[m.key] ?? 0)) {
        weightByKey[m.key] = favWeight;
        textByKey[m.key] = tasteText(m);
      }
    }

    return [
      for (final e in textByKey.entries)
        ProfileSample(text: e.value, weight: weightByKey[e.key]!),
    ];
  }

  /// 用户歌单名 + 歌单标签名：亲手写下的口味词，最高权重信号。
  List<String> _collectForcedTexts() {
    final texts = <String>[];
    for (final p in _playlistService.userPlaylists.value) {
      if (p.name.trim().isNotEmpty) texts.add(p.name);
      for (final tag in p.tags) {
        if (tag.name.trim().isNotEmpty) texts.add(tag.name);
      }
    }
    return texts;
  }

  Future<TasteProfile?> _load() async {
    try {
      final raw = await _db.kvGet(_storageKey);
      if (raw == null || raw.isEmpty) return null;
      final profile = TasteProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      // schema 版本不符时 fromJson 返回 epoch 时间戳的空画像，当没有处理
      if (profile.updatedAt.millisecondsSinceEpoch == 0) return null;
      return profile;
    } catch (e) {
      debugPrint('[TasteProfileService] 画像读盘失败: $e');
      return null;
    }
  }
}
