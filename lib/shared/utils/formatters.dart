/// 时长格式化 —— 全库唯一实现。
/// 常规为 `MM:SS`（分钟可超两位）；达到 1 小时起为 `H:MM:SS`。
String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '$hours:${twoDigits(duration.inMinutes % 60)}:${twoDigits(duration.inSeconds % 60)}';
  }
  final minutes = twoDigits(duration.inMinutes);
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return '$minutes:$seconds';
}
