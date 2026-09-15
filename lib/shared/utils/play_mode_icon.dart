import 'package:flutter/material.dart';

import 'package:bilimusic/domain/play_mode.dart';

/// PlayMode → 图标映射（唯一实现）。
///
/// domain 层不依赖 Flutter，故以扩展形式放在 shared/utils；
/// 统一取 rounded 风格，与 mini bar / PiP 的图标家族一致。
extension PlayModeIcon on PlayMode {
  IconData get icon => switch (this) {
    PlayMode.sequential => Icons.repeat_rounded,
    PlayMode.loop => Icons.repeat_one_rounded,
    PlayMode.shuffle => Icons.shuffle_rounded,
  };
}
