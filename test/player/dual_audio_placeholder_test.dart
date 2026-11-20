import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lyrics/lyric_progress_source.dart';
import 'package:bilimusic/features/player/logic/dual_audio_service.dart';
import 'package:bilimusic/features/player/models/player_state.dart';

/// OHOS 占位模式的回归测试。
void main() {
  test('占位模式下同步 getter 退回状态快照，不碰未初始化的播放器', () async {
    final service = DualAudioService(placeholder: true);
    service.initialize();
    addTearDown(service.dispose);

    expect(service.currentPosition, Duration.zero);
    expect(service.currentDuration, Duration.zero);
    expect(service.currentBufferedPosition, Duration.zero);
    expect(service.isPlaying, isFalse);
    expect(service.playerState.value, isA<PlayerIdle>());
  });

  test('占位模式下歌词进度源读到零位置（详情页 initState 的真实路径）', () async {
    final service = DualAudioService(placeholder: true);
    service.initialize();
    addTearDown(service.dispose);

    final source = PlayerLyricProgressSource(
      positionTicks: service.position,
      playerState: service.playerState,
      readPosition: () => service.currentPosition,
    );
    addTearDown(source.dispose);

    // LyricController.progressSource 的 setter 会同步采样一次，
    // 这里手工复现同一次读取。
    expect(source.position, Duration.zero);
    expect(source.isAdvancing, isFalse);
  });
}
