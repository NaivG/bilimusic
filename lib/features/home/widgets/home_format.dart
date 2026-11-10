import 'package:bilimusic/domain/music.dart';

/// 曲目时长：`m:ss`，超过一小时用 `h:mm:ss`；缺时长时返回 `--:--`。
String formatTrackTime(Duration? duration) {
  if (duration == null || duration.inSeconds <= 0) return '--:--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final two = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$two';
  }
  return '$minutes:$two';
}

/// 舞台卡副标题：`UP 主 · 专辑`，没有专辑时只留 UP 主。
String heroSubtitle(Music music) {
  final album = music.album.trim();
  return album.isEmpty
      ? music.artist.displayName
      : '${music.artist.displayName} · $album';
}
