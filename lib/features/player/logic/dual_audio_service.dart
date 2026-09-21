// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilimusic/domain/play_mode.dart';
import 'package:bilimusic/features/player/models/player_state.dart';

/// 播放器角色枚举
enum PlayerRole {
  active, // 当前正在播放的活跃播放器
  standby, // 预加载下一首的待命播放器
}

/// 播放器状态信息
class PlayerStateInfo {
  final mpv.PlayerApi player;
  PlayerRole role;
  double volume;
  String? currentUrl;
  bool isReady;

  PlayerStateInfo({
    required this.player,
    this.role = PlayerRole.standby,
    this.volume = 1.0,
    this.currentUrl,
    this.isReady = false,
  });

  /// 重置播放器状态
  void reset() {
    volume = 1.0;
    currentUrl = null;
    isReady = false;
  }
}

/// 双播放器音频服务（引擎：mpv_audio_kit / libmpv）
/// 管理两个Player实例交替工作,实现真正的交叉淡入淡出
///
/// 与 just_audio 的关键差异（换引擎后的常驻约定）：
/// - 系统媒体会话（通知栏 / SMTC / MPRIS）由 `audio_service` 独占，
///   两个 Player 不得调 `setMediaSession`（每进程单例，第二个持有者抛
///   StateError）；
/// - 播放/暂停认 `playWhenReady`（意图轴），`playing` 仅代表"真正出声"，
///   seek/缓冲期间会瞬抖；
/// - `stream.*` 不回放当前值，订阅前必须用 `player.state` 播种；
/// - `open()` 返回只等 loadfile 回复，就绪以 `seekCompleted` 或首个非零
///   `duration` 为准；
/// - mpv 音量是 0–100 百分比，应用层 0.0–1.0 由 `_toMpvVolume` 单点换算。
class DualAudioService {
  // 两个播放器实例(使用late延迟初始化)
  late PlayerStateInfo _playerA;
  late PlayerStateInfo _playerB;

  // 统一状态机：替代原 _state / CrossfadeState / _isPreloading / _isCrossfading 三件套
  final ValueNotifier<PlayerState> _playerState = ValueNotifier(PlayerIdle());
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<PlayMode> _playMode = ValueNotifier(PlayMode.sequential);
  // 实时音质：实际命中的流音质代码（30xxx），由 PlayerCoordinator 取流后写入；
  // 空串表示尚未取流（UI 回退显示设置里的请求音质）。
  final ValueNotifier<String> _actualQualityId = ValueNotifier('');

  // 待命播放器的初始音量种子。equal-power 曲线从 0 起，AudioTrack 长时静音会卡顿，
  // 所以保留一个极小非零值让 AudioTrack 持续激活；0.01 听感上无影响。
  // （换算成 mpv 百分比是 1.0，语义不变。）
  final double _standbyVolume = 0.01;
  // 音频轨道启动的额外延迟。配合上面的极小种子音量，50ms 已足够稳定。
  final int _audioTrackStartupDelay = 50;

  // 音量：相对音量模型
  // 实际输出 = _numericalValue（用户设定，持久化） × _relativeVolume（fade 内部比率 0..1）
  static const String KEY_VOLUME = 'player_volume';
  static const double DEFAULT_VOLUME = 1.0;
  final ValueNotifier<double> _numericalValue = ValueNotifier(DEFAULT_VOLUME);
  final ValueNotifier<double> _relativeVolume = ValueNotifier(1.0);
  double _previousNonZeroValue = DEFAULT_VOLUME;

  // 订阅管理
  final List<StreamSubscription> _subscriptions = [];

  // 回调函数
  Function()? onPlaybackCompleted;
  Function(Duration)? onPositionChanged;
  Function(AudioState)? onStateChanged;

  DualAudioService();

  // initialize() 是否已跑过（见其注释里的幂等说明）。
  bool _initialized = false;

  /// 应用层音量是 0.0–1.0 线性值，mpv 的 `volume` 是 0–100 百分比。
  /// 全链路**只此一处换算**，所有调用点一律传应用层值。
  /// `volume-max` 默认 130，应用层 clamp 后天然 ≤100，不需要 setVolumeMax。
  double _toMpvVolume(double v01) => v01 * 100;

  /// 创建播放器。**两个 Player 都不得调用 setMediaSession**：
  /// mpv_audio_kit 的媒体会话是每进程单例（Player._mediaSessionOwner），
  /// A/B 双播放器下第二个持有者会直接抛 StateError。系统媒体会话
  /// （通知栏 / SMTC / MPRIS）由 audio_service 独占。
  ///
  /// `resumePlayback` 显式关闭：音乐播放器语义是「每次 open 都从头播」，
  /// 绝不静默续播（虽然我们从不调 writeResumeConfig，这是双保险）。
  /// `autoPlay` 保持默认 false：open 只装载不播放，播放由 play() 显式发起。
  mpv.PlayerApi _createPlayer() => mpv.Player(
    configuration: const mpv.PlayerConfiguration(resumePlayback: false),
  );

  /// 初始化两个播放器实例。
  ///
  /// **幂等**：组合根（`dualAudioServiceProvider`）和 `PlayerCoordinator.initialize`
  /// 会各调一次。历史上第二次调用会默默重建一对播放器、丢弃旧的一对——
  /// just_audio 时代只是白建两个 AudioPlayer，mpv 时代等于白养两份 libmpv
  /// 句柄与事件 isolate（还要重复挂监听），必须拦下。
  void initialize() {
    if (_initialized) {
      debugPrint('[DualAudioService] 已初始化，跳过重复 initialize');
      return;
    }
    _initialized = true;
    _playerA = PlayerStateInfo(
      player: _createPlayer(),
      role: PlayerRole.active,
    );
    _playerB = PlayerStateInfo(
      player: _createPlayer(),
      role: PlayerRole.standby,
    );

    _setupPlayerListeners(_playerA);
    _setupPlayerListeners(_playerB);

    // 异步加载持久化音量（不影响初始化流程）
    _loadPersistedVolume();

    debugPrint('[DualAudioService] 双播放器初始化完成');
  }

  /// 从 SharedPreferences 恢复音量，并应用到两个播放器
  Future<void> _loadPersistedVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = (prefs.getDouble(KEY_VOLUME) ?? DEFAULT_VOLUME).clamp(0.0, 1.0);
      _numericalValue.value = v;
      if (v > 0) _previousNonZeroValue = v;
      await _activePlayer.player.setVolume(_toMpvVolume(v));
      await _standbyPlayer.player.setVolume(_toMpvVolume(v));
      debugPrint('[DualAudioService] 恢复音量 $v');
    } catch (e) {
      debugPrint('[DualAudioService] 恢复音量失败 $e');
    }
  }

  /// 获取活跃播放器引用
  PlayerStateInfo get _activePlayer {
    return _playerA.role == PlayerRole.active ? _playerA : _playerB;
  }

  /// 获取待命播放器引用
  PlayerStateInfo get _standbyPlayer {
    return _playerA.role == PlayerRole.standby ? _playerA : _playerB;
  }

  /// 为播放器建立监听。
  ///
  /// 与 just_audio 的 BehaviorSubject 相反，mpv_audio_kit 的 `stream.*`
  /// **不回放当前值**——订阅瞬间不会收到当前值，只收之后的增量。
  /// 所以末尾必须先播种一次；否则 crossfade 交换角色、standby 复用时
  /// 状态机会停在旧值。事件回调里一律读 `player.state` 同步快照（包保证
  /// 快照先于对应流事件更新）。
  void _setupPlayerListeners(PlayerStateInfo playerInfo) {
    final player = playerInfo.player;

    // 播放/暂停意图轴：状态机、通知栏都认它；跨 seek 与缓冲稳定。
    _subscriptions.add(
      player.stream.playWhenReady.listen(
        (_) => _recomputeAudioState(playerInfo),
      ),
    );
    // 实际出声轴 + 两种"卡"。`playing` 在 seek/缓冲期间会瞬抖，
    // 绝不拿来判播放/暂停，只在派生状态时经由 state 快照参与 spinner 判定。
    _subscriptions.add(
      player.stream.playing.listen((_) => _recomputeAudioState(playerInfo)),
    );
    _subscriptions.add(
      player.stream.buffering.listen((_) => _recomputeAudioState(playerInfo)),
    );
    _subscriptions.add(
      player.stream.pausedForCache.listen(
        (_) => _recomputeAudioState(playerInfo),
      ),
    );
    // 自然 EOF（keep-open 策略下 mpv 停在末尾，completed 是权威"播完"信号）。
    _subscriptions.add(
      player.stream.completed.listen((_) => _recomputeAudioState(playerInfo)),
    );
    // 每次 loadfile / seek 后 mpv 重新初始化播放环（PLAYBACK_RESTART）
    // 都会触发 seekCompleted——「文件就绪」的权威信号，standby 的 isReady 由它置位。
    _subscriptions.add(
      player.stream.seekCompleted.listen(
        (_) => _markReadyIfPreloaded(playerInfo),
      ),
    );
    // duration 也是 standby 就绪的兜底信号（首个非零时长）；同时喂给 UI。
    _subscriptions.add(
      player.stream.duration.listen((duration) {
        _markReadyIfPreloaded(playerInfo);
        if (playerInfo.role == PlayerRole.active && duration > Duration.zero) {
          _duration.value = duration;
        }
      }),
    );
    // 监听播放位置(保留 200ms 节流；mpv 侧约 30Hz)
    _subscriptions.add(
      player.stream.position
          .transform(
            ThrottleStreamTransformer<Duration>(
              (_) => Stream<Duration>.periodic(
                const Duration(milliseconds: 200),
                (_) => Duration.zero,
              ),
            ),
          )
          .listen((position) {
            if (playerInfo.role == PlayerRole.active) {
              _position.value = position;
              onPositionChanged?.call(position);
            }
          }),
    );
    // 引擎侧终态错误（装载/解码失败）：mpv 的 open() 只等命令回复，装载失败
    // 是异步 end-file 事件——不像 just_audio 的 setUrl 会直接抛。不接住的话
    // active 会永远停在 PlayerBuffering，standby 的 isReady 永不置位。
    _subscriptions.add(
      player.stream.error.listen(
        (error) => _handleEngineError(playerInfo, error),
      ),
    );

    _seedFromState(playerInfo);
  }

  /// 播种：mpv 的流不回放当前值，订阅之后先从同步快照推一次派生状态，
  /// 让状态机 / _position / _duration 从真实状态出发，而不是停在默认值。
  void _seedFromState(PlayerStateInfo playerInfo) {
    _recomputeAudioState(playerInfo);
    if (playerInfo.role == PlayerRole.active) {
      final state = playerInfo.player.state;
      _position.value = state.position;
      if (state.duration > Duration.zero) {
        _duration.value = state.duration;
      }
    }
  }

  /// 从 mpv 的同步状态快照派生应用层状态机（只在事件到达时调用）。
  ///
  /// 轴语义：
  /// - `playWhenReady`  = 播放/暂停意图（按钮、通知栏、状态机都认它）
  /// - `playing`        = 真正出声（mpv `core-idle` 取反；seek/缓冲期间瞬抖）
  /// - `buffering`      = start-file → file-loaded 的装载缓冲
  /// - `pausedForCache` = 播放中网络断流卡顿（mpv 的 paused-for-cache）
  /// - `completed`      = 自然 EOF
  void _recomputeAudioState(PlayerStateInfo playerInfo) {
    final state = playerInfo.player.state;

    // 检测播放完成——只认活跃播放器，且只在进入该状态时触发一次
    // （completed 流本身去重，这里再加状态机守卫，防止重复回调 Coordinator）。
    if (state.completed &&
        playerInfo.role == PlayerRole.active &&
        _playerState.value is! PlayerCompleted) {
      debugPrint('[DualAudioService] 检测到播放完成');
      _playerState.value = PlayerCompleted();
      onPlaybackCompleted?.call();
      return;
    }

    // 更新内部状态(只报告活跃播放器的状态)
    if (playerInfo.role == PlayerRole.active) {
      AudioState newState;
      if (state.completed) {
        // 已处于 PlayerCompleted 时的后续事件维持 stopped，不翻回 paused
        newState = AudioState.stopped;
      } else if (state.buffering || state.pausedForCache) {
        newState = AudioState.buffering;
      } else {
        // 意图轴：playWhenReady 才是"要不要播"。mpv 的 `playing` 是实际出声，
        // seek/缓冲期间会瞬抖——用它会让 UI 每次 seek 闪一下暂停。
        newState = state.playWhenReady ? AudioState.playing : AudioState.paused;
      }

      // 只在状态真正改变时才更新，避免不必要的通知
      if (_audioStateOf(_playerState.value) != newState) {
        debugPrint(
          '[DualAudioService] 状态变更 ${_audioStateOf(_playerState.value)} -> $newState '
          '(intent=${state.playWhenReady}, output=${state.playing}, '
          'buffering=${state.buffering}, stalled=${state.pausedForCache}, '
          'completed=${state.completed})',
        );
        _syncPlayerStateFromAudio(newState);
        onStateChanged?.call(newState);
      }
    }
  }

  /// standby 的就绪门。
  ///
  /// `open()` 返回只代表 loadfile 回复落地、文件还没解码；若照旧立即置位
  /// isReady，crossfade 会在静音里开始（fade 进去听不到声）。现在由两个
  /// 就绪信号置位：
  /// - `seekCompleted`（PLAYBACK_RESTART，每次 loadfile 后必触发一次）；
  /// - 首个非零 `duration`（FILE_LOADED 时到达，兜底）。
  /// 只认「预加载过且未就绪」的 standby，避免 seek / 角色复用误置位。
  void _markReadyIfPreloaded(PlayerStateInfo playerInfo) {
    if (playerInfo.role != PlayerRole.standby) return;
    if (playerInfo.currentUrl == null || playerInfo.isReady) return;
    if (playerInfo.player.state.duration > Duration.zero) {
      playerInfo.isReady = true;
      debugPrint(
        '[DualAudioService] 待命播放器就绪 (${playerInfo.player.state.duration})',
      );
    }
  }

  /// 引擎装载失败的兜底：mpv 把装载失败异步化（end-file error 事件），
  /// 不接住的话 active 会永远停在 PlayerBuffering。stop 的 reason=0 不进
  /// 这条流（只报真失败），所以正常停止/切歌不会误触。
  void _handleEngineError(
    PlayerStateInfo playerInfo,
    mpv.MpvPlayerError error,
  ) {
    if (playerInfo.currentUrl == null) return;
    if (error is! mpv.MpvEndFileError) return;
    debugPrint(
      '[DualAudioService] 装载失败 (${playerInfo.role}): ${error.message} '
      '(code=${error.code})',
    );
    if (playerInfo.role == PlayerRole.standby) {
      playerInfo.isReady = false;
    } else if (_playerState.value is! PlayerIdle &&
        _playerState.value is! PlayerCompleted) {
      // 与 playActive 的 catch 同一语义：回到 Idle，让 UI 可重试
      _playerState.value = PlayerIdle();
      onStateChanged?.call(AudioState.stopped);
    }
  }

  /// 从 AudioState 推导 PlayerState，保留 fadeCountdown
  void _syncPlayerStateFromAudio(AudioState audioState) {
    final current = _playerState.value;
    final fadeCountdown = current is PlayerPlaying
        ? current.fadeCountdown
        : null;

    switch (audioState) {
      case AudioState.playing:
        _playerState.value = PlayerPlaying(fadeCountdown: fadeCountdown);
        break;
      case AudioState.paused:
        _playerState.value = PlayerPaused();
        break;
      case AudioState.buffering:
        _playerState.value = PlayerBuffering();
        break;
      case AudioState.stopped:
        _playerState.value = PlayerIdle();
        break;
    }
  }

  /// 从 PlayerState 提取 AudioState 等价值（仅用于日志/旧回调）
  static AudioState _audioStateOf(PlayerState state) {
    return switch (state) {
      PlayerIdle _ => AudioState.stopped,
      PlayerBuffering _ => AudioState.buffering,
      PlayerPlaying _ => AudioState.playing,
      PlayerPaused _ => AudioState.paused,
      PlayerCompleted _ => AudioState.stopped,
    };
  }

  // ============ 公开API ============

  /// 获取活跃播放器
  mpv.PlayerApi get activePlayer => _activePlayer.player;

  /// 获取待命播放器
  mpv.PlayerApi get standbyPlayer => _standbyPlayer.player;

  /// 获取当前播放状态（PlayerState sealed class 单一状态机）
  ValueListenable<PlayerState> get playerState => _playerState;

  /// 旧 AudioState 派生（仅给 BaseAudioHandler / 旧 UI 兜底用）
  AudioState get currentAudioState => _audioStateOf(_playerState.value);

  /// 获取当前播放位置
  ValueNotifier<Duration> get position => _position;

  /// 获取当前音频时长
  ValueNotifier<Duration> get duration => _duration;

  /// 获取当前播放模式
  ValueNotifier<PlayMode> get playMode => _playMode;

  /// 当前实际播放流的音质代码（30xxx）；空串表示尚未取流。
  ValueListenable<String> get actualQualityId => _actualQualityId;

  /// 获取是否正在播放 —— 意图轴。
  ///
  /// 通知栏 / OS 媒体控件认这个，不认"真正出声"的 `playing`
  /// （那会在 seek 与缓冲期间瞬抖）。
  bool get isPlaying => _activePlayer.player.state.playWhenReady;

  /// 获取当前播放位置(同步)
  Duration get currentPosition => _activePlayer.player.state.position;

  /// 获取当前音频时长(同步)
  Duration get currentDuration => _activePlayer.player.state.duration;

  /// 获取播放进度百分比
  double get progressPercentage {
    final state = _activePlayer.player.state;
    if (state.duration.inMilliseconds == 0) {
      return 0.0;
    }
    return state.position.inMilliseconds / state.duration.inMilliseconds;
  }

  /// 是否处于淡入淡出中（替代旧 isCrossfading + crossfadeState）
  bool get isFading =>
      _playerState.value is PlayerPlaying &&
      (_playerState.value as PlayerPlaying).fadeCountdown != null;

  /// 检查待命播放器是否就绪
  bool get isStandbyReady => _standbyPlayer.isReady;

  /// 用户音量（供 UI 订阅）
  ValueListenable<double> get volume => _numericalValue;

  /// 当前实际输出音量 = 用户值 × 相对比率
  double get effectiveVolume => _numericalValue.value * _relativeVolume.value;

  /// 写状态机：替代 setPreloading + 直接赋值 crossfadeState/_isCrossfading
  void setPlayerState(PlayerState state) {
    _playerState.value = state;
  }

  /// 写入实际命中的流音质代码（PlayerCoordinator 在取流成功后调用）
  void setActualQuality(String qualityId) {
    _actualQualityId.value = qualityId;
  }

  // ============ 音量控制 ============

  /// 设置用户音量（持久化）。fade 进行中只更新用户值，fade 曲线自己走完。
  Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 1.0);
    _numericalValue.value = v;
    if (v > 0) _previousNonZeroValue = v;
    final effective = v * _relativeVolume.value;
    await _activePlayer.player.setVolume(_toMpvVolume(effective));
    await _standbyPlayer.player.setVolume(_toMpvVolume(effective));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(KEY_VOLUME, v);
    } catch (e) {
      debugPrint('[DualAudioService] 保存音量失败 $e');
    }
  }

  /// 静音 / 取消静音切换
  Future<void> toggleMute() async {
    if (_numericalValue.value > 0) {
      await setVolume(0);
    } else {
      await setVolume(_previousNonZeroValue);
    }
  }

  // ============ 播放控制方法 ============

  /// 播放源是网络流还是本地文件路径（保留给回归测试用的纯判据）。
  ///
  /// 判据用 `://` 而不是 `Uri.parse(...).scheme`：`C:\Users\...` 会被解析成
  /// "scheme = c"，据此判断必然误判。网络流（http/https/rtmp/content/asset…）
  /// 一定带 `://`；本地绝对路径（`C:\...`、`/home/...`、`\\server\share\...`）
  /// 都不带。
  ///
  /// 判据用 `://` 而不是 `Uri.parse(...).scheme`：`C:\Users\...` 会被解析成
  /// "scheme = c"，据此判断必然误判。网络流（http/https/rtmp/content/asset…）
  /// 一定带 `://`；本地绝对路径（`C:\...`、`/home/...`、`\\server\share\...`）
  /// 都不带。
  ///
  /// just_audio 时代它决定走 `setUrl` 还是 `setFilePath`（本地路径必须
  /// 绕开 setUrl 的百分号编码）；mpv 的 `open(Media(...))` 网络与本地统一入口，
  /// 生产代码不再分支，判据保留给单测。
  @visibleForTesting
  static bool isRemoteSource(String source) => source.contains('://');

  /// 把播放源交给播放器：mpv 对网络 URL 与本地路径统一入口。
  ///
  /// mpv_audio_kit 的 uri_resolver 只转换 `asset://` 与 Android `content://`，
  /// 其余——包括**裸文件系统路径**（`C:\...`、`/data/user/0/...`）——原样透传给
  /// loadfile。离线命名 `<歌手> - <标题> [cid].m4a`（空格/中文/方括号）
  /// 直接可开，见 `test/player/mpv_path_preflight_test.dart`。
  ///
  /// **历史包袱已卸下**：just_audio 的 `setUrl` 曾把本地路径百分号编码
  /// （`MIMI_music%20-%20%E3%80%90...%5D.m4a`）导致 `Cannot open file`，
  /// 那时需要 `setFilePath` 分支绕行；换 mpv 后这条约束消失，不再区分。
  static Future<void> _setSource(mpv.PlayerApi player, String source) {
    return player.open(mpv.Media(source));
  }

  /// 使用活跃播放器播放URL（或本地文件路径）
  Future<void> playActive(String url) async {
    try {
      debugPrint('[DualAudioService] 开始播放 $url');
      _playerState.value = PlayerBuffering();
      await _setSource(_activePlayer.player, url);
      // 注意：这里**不能**再 seek(0)。open() 返回只等 loadfile 回复，此刻文件
      // 尚未解码，mpv 对加载中的 seek 直接抛错（实测 MpvException code=-12）。
      // 新 loadfile 本来就从 0 开始（工厂里已关 resumePlayback）。
      _relativeVolume.value = 1.0;
      final v = _numericalValue.value;
      await _activePlayer.player.setVolume(_toMpvVolume(v));
      _activePlayer.volume = v;
      _activePlayer.currentUrl = url;
      _activePlayer.isReady = true;
      await _activePlayer.player.play();
      // 注意：不立即设置_playerState为playing，让播放器状态监听器来更新状态
      debugPrint('[DualAudioService] 播放命令已发送');
    } catch (e) {
      debugPrint('[DualAudioService] 播放失败 $e');
      _playerState.value = PlayerIdle();
      rethrow;
    }
  }

  /// 预加载音频到待命播放器（参数可能是网络 URL 或本地文件路径）
  Future<void> preloadToStandby(String url) async {
    try {
      debugPrint('[DualAudioService] 开始预加载 $url');
      // 注意：不要修改_playerState，因为这是standby播放器，不应该影响UI显示的active状态

      await _setSource(_standbyPlayer.player, url);
      _standbyPlayer.currentUrl = url;
      // **不能**在这里置位 isReady——open() 返回时文件还没解码，照旧置位
      // 会让 crossfade 在静音里开始。isReady 改由就绪信号置位（seekCompleted /
      // 首个非零 duration，见 _markReadyIfPreloaded）；executeCrossfade 的
      // isReady 守卫保持不变。
      // 不在这里设置音量为0.0，避免AudioTrack进入长时间mute状态
      // 音量将在executeCrossfade时设置

      debugPrint('[DualAudioService] 预加载已发起，等待就绪信号');
    } catch (e) {
      debugPrint('[DualAudioService] 预加载失败 $e');
      _standbyPlayer.isReady = false;
      rethrow;
    }
  }

  /// 执行交叉淡入淡出切换（编排：_primeStandby → swap → fade curve → finalize）
  Future<void> executeCrossfade(int durationMs) async {
    if (isFading) {
      debugPrint('[DualAudioService] Crossfade已在进行中,跳过');
      return;
    }

    if (!_standbyPlayer.isReady) {
      debugPrint('[DualAudioService] 待命播放器未就绪,无法执行crossfade');
      throw Exception('Standby player not ready');
    }

    debugPrint('[DualAudioService] 开始Crossfade,时长${durationMs}ms');

    try {
      await _primeStandby();
      // 立即交换角色，让 UI 切到新 active
      _swapPlayers();

      // 延长延迟确保AudioTrack完全启动
      await Future.delayed(Duration(milliseconds: _audioTrackStartupDelay));

      await _performFadeCurve(durationMs);
      await _finalizeSwap();
    } catch (e) {
      debugPrint('[DualAudioService] Crossfade失败 $e');
      await _recoverFromCrossfadeError();
      rethrow;
    } finally {
      // fade 结束时清掉 fadeCountdown，但保留 Playing/Paused 本身
      final cur = _playerState.value;
      if (cur is PlayerPlaying) {
        _playerState.value = PlayerPlaying();
      }
    }
  }

  /// Step 1：准备待命播放器（音量 + seek + play）。
  /// 音量故意给到 `_standbyVolume * _numericalValue`（非 0），避免 AudioTrack
  /// 进入长时间 mute；乘上用户音量，确保不会超过用户设定的听感峰值。
  Future<void> _primeStandby() async {
    final primeVolume = _standbyVolume * _numericalValue.value;
    await _standbyPlayer.player.setVolume(_toMpvVolume(primeVolume));
    _standbyPlayer.volume = primeVolume;
    _relativeVolume.value = 0.0;
    // 走到这里 isReady 已由就绪信号置位（executeCrossfade 守卫过），文件已解码，
    // seek 不会再撞"加载中"窗口（加载中的 seek 会抛 MpvException）。
    // 位置本就在 0，这里是契约保底。
    await _standbyPlayer.player.seek(Duration.zero);

    // mpv 的 play() 是乐观写入（意图轴同步置位）+ 异步命令：内部先等 bring-up
    // 再发 pause=no，命令回复在事件 isolate 上异步落地。这里保持 fire-and-forget，
    // 与 just_audio 时代一致：fade 曲线紧随其后，await 反而让 standby 的启动
    // 延迟叠加进 fade 时间轴。
    _standbyPlayer.player.play();
  }

  /// Equal-power 交叉淡入淡出曲线增益。
  /// p ∈ [0,1]：返回 (active 增益, standby 增益)。
  /// sin²(πp/2) + cos²(πp/2) = 1 → 两路叠加后感知响度恒定，
  /// 避免了线性振幅叠加在中段塌陷的问题。
  ({double active, double standby}) _equalPowerGains(double p) {
    final theta = p * math.pi / 2;
    return (active: math.sin(theta), standby: math.cos(theta));
  }

  /// 在 fade 时间轴上推进一步：setVolume 不 await，
  /// 与 _primeStandby 对 play() 的 fire-and-forget 处理保持一致，
  /// 避免 50Hz 下平台通道往返延迟堆积；最新值会在音频线程覆盖旧值。
  void _applyFadeStep(double p) {
    final gains = _equalPowerGains(p);
    final userVolume = _numericalValue.value;
    _relativeVolume.value = p;

    final standbyVolume = userVolume * gains.standby;
    final activeVolume = userVolume * gains.active;

    unawaited(_standbyPlayer.player.setVolume(_toMpvVolume(standbyVolume)));
    _standbyPlayer.volume = standbyVolume;
    unawaited(_activePlayer.player.setVolume(_toMpvVolume(activeVolume)));
    _activePlayer.volume = activeVolume;
  }

  /// Step 3：按 wall clock 在 50Hz 节奏上连续推进 active/standby 音量。
  /// 相对音量模型：实际音量 = _numericalValue（用户设定）× _relativeVolume（fade 比率）
  Future<void> _performFadeCurve(int durationMs) async {
    // 标记进入 fading 子态（Coordinator 会持续更新 fadeCountdown）
    _playerState.value = PlayerPlaying(
      fadeCountdown: (durationMs / 1000).ceil(),
    );

    const tickMs = 20; // 50Hz，肉眼/听感无台阶
    final startMs = DateTime.now().millisecondsSinceEpoch;

    final completer = Completer<void>();
    Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      // 先检查 pause 中断：pause() 已把状态切到 PlayerPaused，本 tick 直接退出
      if (_playerState.value is PlayerPaused) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
      final p = (elapsed / durationMs).clamp(0.0, 1.0);
      _applyFadeStep(p);

      if (p >= 1.0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  /// Step 4-6：fade 完成后把 active 音量拉满、停止旧 active、归位 standby。
  Future<void> _finalizeSwap() async {
    // 重置相对比率为 1.0，active 拉回到用户音量
    _relativeVolume.value = 1.0;
    final v = _numericalValue.value;
    await _activePlayer.player.setVolume(_toMpvVolume(v));
    _activePlayer.volume = v;

    // 确保新 active 仍在播放（意图轴判断）
    if (!_activePlayer.player.state.playWhenReady) {
      debugPrint('[DualAudioService] 新active播放器未播放，重新启动');
      await _activePlayer.player.play();
    }

    // 停止原 active（现在角色是 standby）。mpv 的 stop 会卸载文件并归零播放头，
    // 所以不再补 seek(0)——空载播放器上的 seek 会抛 MpvException。
    await Future.delayed(const Duration(milliseconds: 100));
    await _standbyPlayer.player.stop();
    _standbyPlayer.reset();

    debugPrint('[DualAudioService] Crossfade完成,角色已交换');
  }

  /// 交换活跃/待命角色
  void _swapPlayers() {
    if (_playerA.role == PlayerRole.active) {
      _playerA.role = PlayerRole.standby;
      _playerB.role = PlayerRole.active;
    } else {
      _playerB.role = PlayerRole.standby;
      _playerA.role = PlayerRole.active;
    }
    debugPrint('[DualAudioService] 播放器角色已交换');
  }

  /// 从Crossfade错误中恢复
  Future<void> _recoverFromCrossfadeError() async {
    debugPrint('[DualAudioService] 从Crossfade错误中恢复');
    _relativeVolume.value = 1.0;

    // 确保至少有一个播放器在播放（意图轴判断）
    if (!_activePlayer.player.state.playWhenReady &&
        _standbyPlayer.player.state.playWhenReady) {
      _swapPlayers();
      await _activePlayer.player.setVolume(_toMpvVolume(_numericalValue.value));
      await _standbyPlayer.player.stop();
    } else if (!_standbyPlayer.player.state.playWhenReady) {
      await stop();
      return;
    }

    if (_playerState.value is PlayerPlaying) {
      _playerState.value = PlayerPlaying();
    } else {
      _playerState.value = PlayerIdle();
    }
  }

  /// 取消crossfade并准备播放新首歌
  /// 如果url为null，则只取消crossfade状态，不播放新歌曲
  Future<void> cancelAndPlay(String? url) async {
    // 清掉 fade 子态
    if (_playerState.value is PlayerPlaying) {
      _playerState.value = PlayerPlaying();
    }

    // 清空待命播放器。stop 会卸载文件并归零播放头，不再补 seek(0)。
    _relativeVolume.value = 1.0;
    await _standbyPlayer.player.stop();
    await _standbyPlayer.player.setVolume(_toMpvVolume(_numericalValue.value));
    _standbyPlayer.reset();

    // 如果提供了URL，则播放新歌曲
    if (url != null) {
      await playActive(url);
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    if (isFading) {
      // fade 中断：先把两路音量归位到稳定的"active 静音 / standby 用户音量"状态，
      // 避免残留 fade 中间值；再切到 Paused，_performFadeCurve 下一个 tick 自行退出。
      final v = _numericalValue.value;
      await _activePlayer.player.setVolume(_toMpvVolume(0));
      _activePlayer.volume = 0;
      await _standbyPlayer.player.setVolume(_toMpvVolume(v));
      _standbyPlayer.volume = v;
      _relativeVolume.value = 1.0;
      _playerState.value = PlayerPaused();
      debugPrint('[DualAudioService] Crossfade中暂停');
    } else {
      await _activePlayer.player.pause();
    }
    // 不在这里手动设置状态，让意图轴监听器自动处理
    // 这样可以避免手动设置与监听器回调之间的竞态条件
  }

  /// 恢复播放
  Future<void> resume() async {
    await _activePlayer.player.play();

    // 确保音量为用户设定值
    _relativeVolume.value = 1.0;
    final v = _numericalValue.value;
    await _activePlayer.player.setVolume(_toMpvVolume(v));
    _activePlayer.volume = v;

    // 不在这里手动设置状态，让意图轴监听器自动处理
  }

  /// 停止播放
  Future<void> stop() async {
    await _activePlayer.player.stop();
    await _standbyPlayer.player.stop();
    // mpv 的 stop 会卸载文件并归零播放头，不需要（也不能）再 seek(0)：
    // 空载播放器上的 seek 会抛 MpvException。
    _activePlayer.reset();
    _standbyPlayer.reset();
    _relativeVolume.value = 1.0;
    _playerState.value = PlayerIdle();
    _actualQualityId.value = '';
    onStateChanged?.call(AudioState.stopped);
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _activePlayer.player.seek(position);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final currentIndex = _playMode.value.index;
    final nextIndex = (currentIndex + 1) % PlayMode.values.length;
    _playMode.value = PlayMode.values[nextIndex];
    debugPrint('[DualAudioService] 播放模式切换为 ${_playMode.value}');
  }

  /// 显式设置播放模式（与 togglePlayMode 互不影响）。
  ///
  /// 仅支持 [PlayMode] 中的值，漫游模式（roam）由 PlayerCoordinator 内部状态机
  /// 管理，独立于 [PlayMode]，不在此处暴露。
  void setPlayMode(PlayMode mode) {
    _playMode.value = mode;
    debugPrint('[DualAudioService] setPlayMode $mode');
  }

  /// 释放资源
  Future<void> dispose() async {
    debugPrint('[DualAudioService] 开始释放资源');

    // 取消所有订阅：先摘出快照再清空列表，避免「cancel 期间又有 add」导致
    // ConcurrentModificationError（cancel 可能同步触发监听回调）。单个取消失败
    // 只记日志，不能中断后面的播放器释放。
    final subscriptions = List<StreamSubscription>.of(_subscriptions);
    _subscriptions.clear();
    for (final sub in subscriptions) {
      try {
        await sub.cancel();
      } catch (e) {
        debugPrint('[DualAudioService] 取消订阅失败 $e');
      }
    }

    // 停止并释放两个播放器：即使上一步出过问题也必须走到这里，
    // 否则 libmpv 线程会带着活跃解码器被进程退出拆掉。
    // dispose() 幂等，且内部会先摘媒体会话再拆 libmpv（不需要手动清理）。
    for (final info in [_playerA, _playerB]) {
      try {
        await info.player.stop();
      } catch (e) {
        debugPrint('[DualAudioService] 停止播放器失败 $e');
      }
      try {
        await info.player.dispose();
      } catch (e) {
        debugPrint('[DualAudioService] 释放播放器失败 $e');
      }
    }

    debugPrint('[DualAudioService] 资源释放完成');
  }
}
