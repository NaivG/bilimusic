import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:bilimusic/domain/music.dart';
import 'package:bilimusic/features/lyrics/lyric_source.dart';
import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/features/playlist/playlist_providers.dart';
import 'package:bilimusic/features/lyrics/lyrics_service.dart';

/// 把 `LyricsService` 重新以 `ChangeNotifierProvider` 暴露,使 UI providers
/// 在歌词缓存更新时自动重建(预热 / 切源完成都会触发 [ChangeNotifier.notifyListeners])。
///
/// 实例的所有权在 `lyricsServiceProvider`(它的 `ref.onDispose` 负责 dispose)。
/// `ChangeNotifierProvider` 默认会在自己被释放时再 dispose 一次返回的 notifier
/// ——退出应用释放容器时就成了双 dispose。共享实例必须关掉这个默认行为。
final lyricsRevisionProvider = ChangeNotifierProvider<LyricsService>((ref) {
  return ref.watch(lyricsServiceProvider);
}, disposeNotifier: false);

/// 用户手动指定的歌词来源。
///
/// 作用域必须跟着来源走。sourceId 是「来源 + 该来源里这首歌的 id」
/// (`ne:123456`),改成按曲目比对后就不依赖任何监听时序,
/// 不属于当前曲目的选择直接视为未选。
class LyricSelection {
  const LyricSelection({
    required this.musicIdentity,
    required this.cid,
    required this.sourceId,
  });

  /// 绑定到某首曲子。
  factory LyricSelection.of(Music music, String sourceId) => LyricSelection(
    musicIdentity: LyricsService.musicIdentityOf(music),
    cid: music.cid,
    sourceId: sourceId,
  );

  /// 与分P无关的曲目身份([LyricsService.musicIdentityOf])。
  final String musicIdentity;

  /// 所属分P的 cid,可能是空串(`ensureCid` 回填前的队列条目)。
  final String cid;

  /// 选中来源的 [LyricSource.id]。
  final String sourceId;

  /// 是否仍然作用于 [music]。
  ///
  /// 不直接比 `(id, cid)` 字面量:曲中 `ensureCid` 回填 cid 会重建 Music 对象
  /// (同 id,cid 从空到有),那不是切歌;只有两边 cid 都非空且不同才算换了分P。
  bool appliesTo(Music music) {
    if (musicIdentity != LyricsService.musicIdentityOf(music)) return false;
    if (cid.isEmpty || music.cid.isEmpty) return true;
    return cid == music.cid;
  }
}

/// 用户手动选中的歌词来源(按曲目记忆,切歌自动失效)。
class SelectedLyricSource extends Notifier<LyricSelection?> {
  @override
  LyricSelection? build() => null;

  /// 用户在「歌词来源」菜单里为 [music] 指定了 [sourceId]。
  void select(Music music, String sourceId) {
    state = LyricSelection.of(music, sourceId);
  }

  /// 复位(清空歌词缓存这类让旧 sourceId 失效的场景)。
  void clear() => state = null;
}

final selectedLyricSourceProvider =
    NotifierProvider<SelectedLyricSource, LyricSelection?>(
      SelectedLyricSource.new,
    );

/// 手动来源在**当前曲目**下的取值:属于别的曲目(切歌了)就当没选。
final currentMusicSelectedLyricSourceProvider = Provider<String?>((ref) {
  final music = ref.watch(currentMusicProvider);
  final selection = ref.watch(selectedLyricSourceProvider);
  if (music == null || selection == null) return null;
  return selection.appliesTo(music) ? selection.sourceId : null;
});

/// 当前曲目的歌词载荷 (自动 / 切源后的)。
///
/// 行为:
/// - 监听 [currentMusicProvider]:切歌后手动来源自动不再参与
///   ([currentMusicSelectedLyricSourceProvider] 变 null),直接走自动选源。
/// - 监听 [lyricsRevisionProvider],后台预热 / 切源完成触发重建。
/// - 当前曲目有生效的手动来源 → 调 `LyricsService.fetchBySourceId`;
///   取不到就回退自动选源(用户主动挑「本地」除外)。
/// - 否则调 `LyricsService.lyricsFor`(缓存命中秒回)。
final currentMusicLyricsProvider =
    AsyncNotifierProvider<_CurrentMusicLyricsNotifier, LyricsPayload?>(
      _CurrentMusicLyricsNotifier.new,
    );

class _CurrentMusicLyricsNotifier extends AsyncNotifier<LyricsPayload?> {
  @override
  Future<LyricsPayload?> build() async {
    final music = ref.watch(currentMusicProvider);
    if (music == null) return null;

    // 监听服务更新 (预热完成 / 切源完成)
    ref.watch(lyricsRevisionProvider);

    final svc = ref.read(lyricsServiceProvider);
    final selected = ref.watch(currentMusicSelectedLyricSourceProvider);
    if (selected != null) {
      // 用户主动挑「本地」= 不要网络歌词，直接给空载荷
      // （详情页收到 null 会换成占位词，不会留着上一首的模型）。
      if (selected == localLyricSourceId) return null;

      final payload = await svc.fetchBySourceId(selected, music);
      if (payload != null) return payload;
      // 手选来源这次没拿到词(候选表里已经没有它 / 该来源确实没有这首的歌词):
      // 回退自动选源,而不是把 null 交给 UI —— UI 收到 null 就不会替换
      // lyricController 里已有的内容,屏幕上会一直留着上一首的歌词,
      // 而且这条路命中缓存后不会再自动重取,用户只能手动重选一次。
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
