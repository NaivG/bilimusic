/// 歌词来源数据类
class LyricSource {
  final String id;
  final String name;

  const LyricSource({required this.id, required this.name});

  @override
  String toString() => name;
}
