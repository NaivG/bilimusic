/// 时长格式化 —— `MM:SS`（分钟可超两位）。
/// detail 三页与进度条时间标签共用；全库含小时分支的收敛见审计 §七 #9。
String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final minutes = twoDigits(duration.inMinutes);
  final seconds = twoDigits(duration.inSeconds.remainder(60));
  return '$minutes:$seconds';
}
