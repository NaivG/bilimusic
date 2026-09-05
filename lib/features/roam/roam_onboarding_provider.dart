import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/managers/settings_manager.dart';
import 'package:bilimusic/models/music.dart';
import 'package:bilimusic/models/roam_config.dart';
import 'package:bilimusic/models/roam_style.dart';
import 'package:bilimusic/services/player_coordinator.dart';
import 'package:bilimusic/services/playlist_service.dart';
import 'package:bilimusic/services/roaming_service.dart';
import 'package:bilimusic/utils/seed_diversity.dart';

/// 漫游引导步骤枚举。
enum OnboardingStep {
  pickPlaylist, // [A] 选择歌单
  prefetchLoading, // [A.5] 预取候选推荐
  pickSeeds, // [B] 用户挑选种子（PageView，1 或 3 页）
  pickStyle, // [C] 选择漫游风格
  finalLoading, // [D] 最终拉取推荐
  error, // 任何失败 → 错误页（可重试）
  done, // 已就绪，等 apply
}

/// 漫游数据量模式。
enum RoamMode {
  /// ≥9 首歌单：3 颗种子 → 6 首推荐 → 入队 9 首
  normal,

  /// 3~9 首歌单：1 颗种子 → 2 首推荐 → 入队 3 首
  lowData,
}

/// 漫游引导状态。
@immutable
class OnboardingState {
  final OnboardingStep step;
  final String? playlistId;
  final String? playlistName;
  final List<Music> tempQueue;
  final RoamMode mode;
  final int candidateCount; // 每轮挑选的候选数 X: 1 (lowData) 或 3 (normal)
  final int recsCount; // 最终推荐数: 2 (lowData) 或 6 (normal)

  // 步骤 [B] 用
  final List<List<Music>> roundOptions; // [round1Cards, round2Cards, ...]
  final List<int?> selectedSeedIndex; // 每轮用户选中的下标（默认 0）
  final List<Music?> userPicks; // parallel 缓存，避免索引错位
  final int currentSectionIndex; // PageView 当前页

  // 步骤 [C] 用
  final RoamStyle style;

  // 步骤 [D] 用
  final bool isLoading;
  final String? statusMessage;
  final String? error;
  final int retryCount;
  final List<Music>? finalPlaylist;

  const OnboardingState({
    this.step = OnboardingStep.pickPlaylist,
    this.playlistId,
    this.playlistName,
    this.tempQueue = const [],
    this.mode = RoamMode.normal,
    this.candidateCount = 3,
    this.recsCount = 6,
    this.roundOptions = const [],
    this.selectedSeedIndex = const [],
    this.userPicks = const [],
    this.currentSectionIndex = 0,
    this.style = RoamStyle.balanced,
    this.isLoading = false,
    this.statusMessage,
    this.error,
    this.retryCount = 0,
    this.finalPlaylist,
  });

  OnboardingState copyWith({
    OnboardingStep? step,
    String? playlistId,
    String? playlistName,
    List<Music>? tempQueue,
    RoamMode? mode,
    int? candidateCount,
    int? recsCount,
    List<List<Music>>? roundOptions,
    List<int?>? selectedSeedIndex,
    List<Music?>? userPicks,
    int? currentSectionIndex,
    RoamStyle? style,
    bool? isLoading,
    String? statusMessage,
    String? error,
    int? retryCount,
    List<Music>? finalPlaylist,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName ?? this.playlistName,
      tempQueue: tempQueue ?? this.tempQueue,
      mode: mode ?? this.mode,
      candidateCount: candidateCount ?? this.candidateCount,
      recsCount: recsCount ?? this.recsCount,
      roundOptions: roundOptions ?? this.roundOptions,
      selectedSeedIndex: selectedSeedIndex ?? this.selectedSeedIndex,
      userPicks: userPicks ?? this.userPicks,
      currentSectionIndex: currentSectionIndex ?? this.currentSectionIndex,
      style: style ?? this.style,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      error: error,
      retryCount: retryCount ?? this.retryCount,
      finalPlaylist: finalPlaylist ?? this.finalPlaylist,
    );
  }

  /// 是否所有轮次都有选中的种子。
  bool get allSeedsPicked =>
      userPicks.length == roundsCount && userPicks.every((p) => p != null);

  /// 总轮次数（lowData=1, normal=3）。
  int get roundsCount => mode == RoamMode.normal ? 3 : 1;
}

/// 漫游引导状态机 Notifier。
///
/// autoDispose：用户退出 onboarding 后自动清理，无需手动 reset。
class RoamOnboardingNotifier extends Notifier<OnboardingState> {
  late final PlayerCoordinator _coordinator;
  late final PlaylistService _playlistService;
  late final RoamingService _roamingService;
  late final SettingsManager _settingsManager;
  final Random _random = Random();
  bool _disposed = false;

  @override
  OnboardingState build() {
    _coordinator = ref.read(playerCoordinatorProvider);
    _playlistService = ref.read(playlistServiceProvider);
    _roamingService = ref.read(roamingServiceProvider);
    _settingsManager = ref.read(settingsManagerProvider);
    ref.onDispose(() => _disposed = true);
    return OnboardingState(style: _settingsManager.roamStyle);
  }

  // ─────────────── 步骤 [A] ───────────────

  /// 用户在 [A] 选中歌单：加载歌曲、count check、进入 [A.5]。
  ///
  /// 数量规则：
  /// - <3: 写入 error，停留在 pickPlaylist
  /// - 3~9: lowData (1 种子 → 2 推荐)
  /// - ≥9: normal (3 种子 → 6 推荐)
  Future<void> selectPlaylist(String playlistId, String playlistName) async {
    final List<Music> songs;
    if (playlistId == 'favorites') {
      songs = await _playlistService.getSystemPlaylistSongs('favorites');
    } else {
      songs = await _playlistService.loadPlaylistSongs(playlistId);
    }

    if (_disposed) return;

    if (songs.length < 3) {
      state = state.copyWith(error: '歌单至少需要 3 首歌（当前 ${songs.length} 首）');
      return;
    }

    final RoamMode mode;
    final int candidateCount;
    final int recsCount;
    if (songs.length < 9) {
      mode = RoamMode.lowData;
      candidateCount = 1;
      recsCount = 2;
    } else {
      mode = RoamMode.normal;
      candidateCount = 3;
      recsCount = 6;
    }

    state = state.copyWith(
      step: OnboardingStep.prefetchLoading,
      playlistId: playlistId,
      playlistName: playlistName,
      tempQueue: songs,
      mode: mode,
      candidateCount: candidateCount,
      recsCount: recsCount,
      error: null,
      statusMessage: '正在准备漫游...',
    );

    await _runPrefetch();
  }

  /// 清除错误状态（例如用户点 "再试一次"）。
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: null);
  }

  // ─────────────── 步骤 [A.5] ───────────────

  Future<void> _runPrefetch() async {
    if (_disposed) return;

    final tempQueue = state.tempQueue;
    final candidateCount = state.candidateCount;
    final roundsCount = state.roundsCount;
    final excludeIds = <String>{}; // 已选过的 candidate id，避免跨轮重复
    final previousCandidates = <Music>[]; // 前几轮选的 candidate 集合，用于多样性参考
    final roundOptions = <List<Music>>[];

    for (int round = 0; round < roundsCount; round++) {
      if (_disposed) return;

      state = state.copyWith(
        statusMessage: '正在挑选第 ${round + 1} / $roundsCount 轮候选...',
      );

      final pool = tempQueue.where((m) => !excludeIds.contains(m.id)).toList();

      final candidates = pickDiverse(
        pool: pool,
        existing: previousCandidates,
        count: candidateCount,
        random: _random,
      );

      excludeIds.addAll(candidates.map((c) => c.id));
      previousCandidates.addAll(candidates);

      final options = await _roamingService.prefetchRound(
        candidates: candidates,
      );

      roundOptions.add(options);
    }

    if (_disposed) return;

    // 默认选中每轮第一项
    final initialPicks = roundOptions
        .map((opts) => opts.isNotEmpty ? opts.first : null)
        .toList();

    state = state.copyWith(
      step: OnboardingStep.pickSeeds,
      roundOptions: roundOptions,
      selectedSeedIndex: List.filled(roundsCount, 0),
      userPicks: initialPicks,
      currentSectionIndex: 0,
      statusMessage: null,
    );
  }

  // ─────────────── 步骤 [B] ───────────────

  void selectSeed(int round, int index) {
    if (round < 0 || round >= state.roundOptions.length) return;
    final options = state.roundOptions[round];
    if (index < 0 || index >= options.length) return;

    final newIndex = List<int?>.from(state.selectedSeedIndex);
    final newPicks = List<Music?>.from(state.userPicks);
    newIndex[round] = index;
    newPicks[round] = options[index];

    state = state.copyWith(selectedSeedIndex: newIndex, userPicks: newPicks);
  }

  void setSectionIndex(int index) {
    if (index < 0 || index >= state.roundsCount) return;
    if (state.currentSectionIndex == index) return;
    state = state.copyWith(currentSectionIndex: index);
  }

  void goToStyle() {
    if (!state.allSeedsPicked) return;
    state = state.copyWith(step: OnboardingStep.pickStyle);
  }

  void backToSeeds() {
    state = state.copyWith(step: OnboardingStep.pickSeeds);
  }

  // ─────────────── 步骤 [C] ───────────────

  void setStyle(RoamStyle style) {
    state = state.copyWith(style: style);
  }

  Future<void> goToFinalFetch() async {
    state = state.copyWith(
      step: OnboardingStep.finalLoading,
      isLoading: true,
      statusMessage: '正在为你生成歌单...',
      retryCount: 0,
      error: null,
    );
    await _runFinalFetch();
  }

  // ─────────────── 步骤 [D] ───────────────

  Future<void> _runFinalFetch() async {
    if (_disposed) return;

    final seeds = state.userPicks.whereType<Music>().toList();
    final totalSize = state.recsCount;
    final style = state.style;

    final recs = await _roamingService.fetchMultiSeed(
      seeds: seeds,
      style: style,
      totalSize: totalSize,
    );

    if (_disposed) return;

    // 接受部分失败，但 < 50% 视为不足
    final minThreshold = (totalSize * 0.5).ceil();
    if (recs.length < minThreshold) {
      if (state.retryCount == 0) {
        state = state.copyWith(retryCount: 1, statusMessage: '推荐不足，正在重试...');
        await Future.delayed(const Duration(milliseconds: 500));
        if (_disposed) return;
        return _runFinalFetch();
      }
      state = state.copyWith(
        step: OnboardingStep.error,
        isLoading: false,
        statusMessage: null,
        error: '推荐不足，请稍后重试（${recs.length} / $totalSize）',
      );
      return;
    }

    // 把 (种子 + 推荐) 打乱
    final all = <Music>[...seeds, ...recs];
    all.shuffle(_random);

    state = state.copyWith(
      step: OnboardingStep.done,
      finalPlaylist: all,
      isLoading: false,
      statusMessage: null,
    );
  }

  Future<void> retryFinalFetch() async {
    state = state.copyWith(
      step: OnboardingStep.finalLoading,
      isLoading: true,
      statusMessage: '正在为你生成歌单...',
      retryCount: 0,
      error: null,
    );
    await _runFinalFetch();
  }

  // ─────────────── 步骤 [E] ───────────────

  /// 应用漫游播放列表。完成不自动关闭页面，由用户在 [_PlayingStep] 手动返回。
  Future<void> apply() async {
    if (_disposed) return;
    final playlist = state.finalPlaylist;
    if (playlist == null) return;

    final playlistId = state.playlistId;
    final seeds = state.userPicks.whereType<Music>().toList();
    final style = state.style;
    if (seeds.isEmpty) return;
    if (playlistId == null) return;

    try {
      await _coordinator.applyRoamPlaylist(
        songs: playlist,
        style: style,
        seeds: seeds,
      );
    } catch (e) {
      state = state.copyWith(
        step: OnboardingStep.error,
        isLoading: false,
        error: '应用失败: $e',
      );
    }
  }

  // ─────────────── 导入配置入口 ───────────────

  /// 导入 [RoamConfig] 后直接进入 finalLoading → done → apply 的标准流程。
  ///
  /// 跳过 A→D 的交互步骤，但保留 shuffle、阈值校验、错误页等一致性约束。
  /// 不持有源歌单 ID：[_PlayingStep] 仅展示已生成曲数 + 风格。
  Future<void> importConfig(RoamConfig config) async {
    if (_disposed) return;

    state = state.copyWith(
      step: OnboardingStep.finalLoading,
      isLoading: true,
      statusMessage: '正在为你生成歌单...',
      retryCount: 0,
      error: null,
    );

    if (_disposed) return;

    try {
      final seeds = await Future.wait(
        config.seeds.map(_roamingService.resolveSeed),
      );
      if (_disposed) return;

      final recs = await _roamingService.fetchMultiSeed(
        seeds: seeds,
        style: config.style,
        totalSize: 6,
      );
      if (_disposed) return;

      final minThreshold = (6 * 0.5).ceil();
      if (recs.length < minThreshold) {
        state = state.copyWith(
          step: OnboardingStep.error,
          isLoading: false,
          statusMessage: null,
          error: '推荐不足，请稍后重试（${recs.length} / 6）',
        );
        return;
      }

      final all = <Music>[...seeds, ...recs]..shuffle(_random);

      state = state.copyWith(
        step: OnboardingStep.done,
        finalPlaylist: all,
        isLoading: false,
        statusMessage: null,
        style: config.style,
        playlistId: '',
        playlistName: '导入配置',
        userPicks: seeds,
        roundOptions: const [],
        selectedSeedIndex: const [],
        tempQueue: const [],
        mode: RoamMode.normal,
        candidateCount: 3,
        recsCount: 6,
        currentSectionIndex: 0,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(
        step: OnboardingStep.error,
        isLoading: false,
        statusMessage: null,
        error: '导入失败: $e',
      );
    }
  }
}

final roamOnboardingProvider =
    NotifierProvider.autoDispose<RoamOnboardingNotifier, OnboardingState>(
      RoamOnboardingNotifier.new,
    );
