/// 本地歌词来源的固定 id。
///
/// 列表首项恒为它（名字取曲名）。B 站流没有本地歌词可读，选中它等于
/// 「不要网络歌词」，因此 [LyricsService.fetchBySourceId] 对它直接返回 null。
const String localLyricSourceId = 'local';

/// 歌词来源数据类
class LyricSource {
  final String id;
  final String name;

  const LyricSource({required this.id, required this.name});

  @override
  String toString() => name;
}
