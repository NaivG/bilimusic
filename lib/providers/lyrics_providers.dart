import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:bilimusic/components/lyric/lyric_source.dart';
import 'package:bilimusic/core/app_providers.dart';
import 'package:bilimusic/providers/playlist_providers.dart';
import 'package:bilimusic/services/lyrics_service.dart';

/// 把 `LyricsService` 重新以 `ChangeNotifierProvider` 暴露,使 UI providers
/// 在歌词缓存更新时自动重建(预热 / 切源完成都会触发 [ChangeNotifier.notifyListeners])。
final lyricsRevisionProvider = ChangeNotifierProvider<LyricsService>((ref) {
  return ref.watch(lyricsServiceProvider);
});

/// 用户手动选择的歌词来源 id;切歌时由 [currentMusicLyricsProvider] 自动重置。
final selectedLyricSourceProvider = StateProvider<String?>((_) => null);

/// 当前曲目的歌词载荷 (自动 / 切源后的)。
///
/// 行为:
/// - 监听 [currentMusicProvider],曲目变化时自动重置 [selectedLyricSourceProvider]。
/// - 监听 [lyricsRevisionProvider],后台预热 / 切源完成触发重建。
/// - 用户选了非空 sourceId → 调 `LyricsService.fetchBySourceId`。
/// - 否则调 `LyricsService.lyricsFor`(缓存命中秒回)。
final currentMusicLyricsProvider =
    AsyncNotifierProvider<_CurrentMusicLyricsNotifier, LyricsPayload?>(
      _CurrentMusicLyricsNotifier.new,
    );

class _CurrentMusicLyricsNotifier extends AsyncNotifier<LyricsPayload?> {
  @override
  Future<LyricsPayload?> build() async {
    final music = ref.watch(currentMusicProvider);
    if (music == null) {
      ref.read(selectedLyricSourceProvider.notifier).state = null;
      return null;
    }

    // 曲目变化 → 清掉用户上次手动选的来源
    ref.listen<dynamic>(currentMusicProvider, (prev, next) {
      ref.read(selectedLyricSourceProvider.notifier).state = null;
    });

    // 监听服务更新 (预热完成 / 切源完成)
    ref.watch(lyricsRevisionProvider);

    final svc = ref.read(lyricsServiceProvider);
    final selected = ref.watch(selectedLyricSourceProvider);
    if (selected != null) {
      return svc.fetchBySourceId(selected, music);
    }
    return svc.lyricsFor(music);
  }
}

/// 当前曲目的可选歌词来源列表(初次进入详情页立刻可读,后台预热完成后自动刷新)。
final currentMusicLyricSourcesProvider = Provider<List<LyricSource>>((ref) {
  final music = ref.watch(currentMusicProvider);
  ref.watch(lyricsRevisionProvider);
  if (music == null) return const <LyricSource>[];
  return ref.read(lyricsServiceProvider).sourcesFor(music);
});
