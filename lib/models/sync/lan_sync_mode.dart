/// 局域网同步模式。
///
/// `off` — 完全关闭，不广播不发现。
/// `private` — 私有模式：仅配对后的对端可见，可双向同步 + 远程控制。
/// `public` — 公共模式：对局域网内其他 BiliMusic 客户端只读暴露"现在播放"。
enum LanSyncMode {
  off,
  private,
  public;

  /// 本地是否接受私有配对连接。
  bool get acceptsPrivate => this == LanSyncMode.private;

  /// 在 mDNS TXT 中广播的字符串。
  ///
  /// 映射到对端的解析：
  /// - `private` → 对端能 connect
  /// - `public` → 对端只能 read
  String get mdnsValue {
    if (this == LanSyncMode.off) return 'off';
    if (this == LanSyncMode.private) return 'private';
    return 'public';
  }

  static LanSyncMode fromString(String? s) {
    if (s == null) return LanSyncMode.off;
    for (final m in LanSyncMode.values) {
      if (m.name == s) return m;
    }
    return LanSyncMode.off;
  }
}

/// 设备列表 chip 等紧凑位置使用的简短 mode 标签。
String modeShortLabel(LanSyncMode m) {
  return switch (m) {
    LanSyncMode.private => '私有',
    LanSyncMode.public => '公共',
    LanSyncMode.off => '已关闭',
  };
}
