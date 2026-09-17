import 'package:flutter_test/flutter_test.dart';

import 'package:bilimusic/features/lan_sync/models/sync_message.dart';

/// 遥控动作与"被控端退出漫游"的边界约定。
///
/// 被控端收到遥控即代表主控端接管播放，必须交出漫游会话（否则续杯会把推荐曲
/// 追加进队列，被控端跟不住主控端）；只有只读的 `state` 索取快照不改播放状态。
void main() {
  test('所有会改变播放的遥控动作都要求被控端先退出漫游', () {
    const takeover = [
      CmdActions.play,
      CmdActions.pause,
      CmdActions.resume,
      CmdActions.seek,
      CmdActions.next,
      CmdActions.prev,
      CmdActions.playAt,
      CmdActions.playMusic,
    ];

    for (final action in takeover) {
      expect(CmdActions.exitsRoaming(action), isTrue, reason: action);
    }
  });

  test('只读的 state 快照索取不触发退出漫游', () {
    expect(CmdActions.exitsRoaming(CmdActions.requestState), isFalse);
  });
}
