import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 配对服务：管理本机 PIN、selfToken 和私有配对拓扑。
///
/// 私有群组不是一个可被 mDNS 直接信任的 groupId，而是已验证配对边的
/// 连通分量。边通过 private 会话传播，最终成员仍需使用自己的 token
/// 与本机建立直连 TCP 会话。
class PairingService {
  static const String _prefsPin = 'lan_pairing_pin';
  static const String _prefsSelfToken = 'lan_pairing_self_token';
  static const String _prefsPeerTokens = 'lan_pairing_peer_tokens';
  static const String _prefsEdges = 'lan_pairing_edges';
  static const int _pinLength = 6;
  static const int _tokenBytes = 32;

  String? _pin;
  String? _selfToken;
  String _localId = '';
  Map<String, String> _peerTokens = const {};
  Map<String, Map<String, String>> _edges = const {};

  /// 当前本机 PIN（6 位数字字符串）。load 之前为空。
  String get currentPin => _pin ?? '';

  /// 本机 selfToken（64 字符 hex）。load 之前为空。
  String get selfToken => _selfToken ?? '';

  /// 当前节点已知的私有配对边，用于向其他 private peer 传播拓扑。
  List<Map<String, String>> get rosterEdges =>
      _edges.values.map((edge) => Map<String, String>.from(edge)).toList();

  /// 从持久化存储加载 PIN、selfToken、peer tokens 和拓扑边。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    var pin = prefs.getString(_prefsPin);
    if (pin == null || pin.length != _pinLength) {
      pin = _generatePin();
      await prefs.setString(_prefsPin, pin);
    }
    _pin = pin;

    var selfToken = prefs.getString(_prefsSelfToken);
    if (selfToken == null || selfToken.isEmpty) {
      selfToken = generateToken();
      await prefs.setString(_prefsSelfToken, selfToken);
    }
    _selfToken = selfToken;

    final tokensJson = prefs.getString(_prefsPeerTokens);
    if (tokensJson != null && tokensJson.isNotEmpty) {
      try {
        final map = jsonDecode(tokensJson) as Map<String, dynamic>;
        _peerTokens = map.map((k, v) => MapEntry(k, v as String));
      } catch (_) {
        _peerTokens = const {};
      }
    }

    final edgesJson = prefs.getString(_prefsEdges);
    if (edgesJson != null && edgesJson.isNotEmpty) {
      try {
        final list = jsonDecode(edgesJson) as List<dynamic>;
        _edges = {
          for (final value in list)
            if (value is Map)
              _edgeKey(value['a'] as String, value['b'] as String):
                  Map<String, String>.from(value),
        };
      } catch (_) {
        _edges = const {};
      }
    }
  }

  /// 设置本机设备 id，并把旧版本只保存 token 的直接配对迁移为边。
  Future<void> configureLocalId(String id) async {
    if (id.isEmpty || _localId == id) return;
    _localId = id;
    var changed = false;
    for (final entry in _peerTokens.entries) {
      final peerId = entry.key;
      if (!_edges.containsKey(_edgeKey(_localId, peerId))) {
        _putEdge(_localId, _selfToken!, peerId, entry.value);
        changed = true;
      }
    }
    if (changed) await _persist();
  }

  /// 校验 [code] 是否匹配本机 PIN。
  bool verifyPin(String code) => _pin != null && _pin == code;

  /// 查询对端的预期 token（对端应在 hello 里携带这个 token）。
  String? expectedTokenFor(String peerId) => _peerTokens[peerId];

  /// 记录一次用户确认的直接私有配对。
  Future<void> rememberDirectPeer(String peerId, String token) async {
    if (peerId.isEmpty || token.isEmpty) return;
    _peerTokens = {..._peerTokens, peerId: token};
    if (_localId.isNotEmpty && _selfToken != null) {
      _putEdge(_localId, _selfToken!, peerId, token);
    }
    await _persist();
  }

  /// 记录通过 private roster 发现的成员 token，不新增本机直接配对边。
  Future<void> rememberPeerToken(String peerId, String token) async {
    if (peerId.isEmpty || token.isEmpty) return;
    if (_peerTokens[peerId] == token) return;
    _peerTokens = {..._peerTokens, peerId: token};
    await _persist();
  }

  /// 合并来自已授权 private 会话的拓扑边。
  ///
  /// 该方法不会被 public 会话调用。返回值表示本地拓扑是否发生变化。
  Future<bool> mergeRoster(List<Map<String, String>> edges) async {
    var changed = false;
    for (final value in edges) {
      final a = value['a'];
      final b = value['b'];
      final aToken = value['aToken'];
      final bToken = value['bToken'];
      if (a == null || b == null || aToken == null || bToken == null) continue;
      if (a.isEmpty ||
          b.isEmpty ||
          a == b ||
          aToken.isEmpty ||
          bToken.isEmpty) {
        continue;
      }
      final key = _edgeKey(a, b);
      final normalized = <String, String>{
        'a': a,
        'aToken': aToken,
        'b': b,
        'bToken': bToken,
      };
      if (!_sameEdge(_edges[key], normalized)) {
        _edges = {..._edges, key: normalized};
        changed = true;
      }
      if (a != _localId && _peerTokens[a] != aToken) {
        _peerTokens = {..._peerTokens, a: aToken};
        changed = true;
      }
      if (b != _localId && _peerTokens[b] != bToken) {
        _peerTokens = {..._peerTokens, b: bToken};
        changed = true;
      }
    }
    if (changed) {
      _pruneUnreachable();
      await _persist();
    }
    return changed;
  }

  /// 取消本机与 [peerId] 的直接配对，并清除失去路径的派生成员。
  Future<void> forgetPeer(String peerId) async {
    if (_localId.isEmpty) {
      _peerTokens = Map.from(_peerTokens)..remove(peerId);
      await _persist();
      return;
    }
    final key = _edgeKey(_localId, peerId);
    if (!_edges.containsKey(key)) return;
    _edges = Map.from(_edges)..remove(key);
    _pruneUnreachable();
    await _persist();
  }

  /// 删除任意一条已传播的边，用于处理远端 revoke。
  Future<void> removeEdge(String a, String b) async {
    final key = _edgeKey(a, b);
    if (!_edges.containsKey(key)) return;
    _edges = Map.from(_edges)..remove(key);
    _pruneUnreachable();
    await _persist();
  }

  /// 重置本机 PIN。
  Future<void> rotatePin() async {
    final newPin = _generatePin();
    _pin = newPin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPin, newPin);
  }

  /// 生成新 token（hex 编码 64 字符）。
  static String generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(_tokenBytes, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _generatePin() {
    final rng = Random.secure();
    final n = rng.nextInt(1000000);
    return n.toString().padLeft(_pinLength, '0');
  }

  void _putEdge(
    String firstId,
    String firstToken,
    String secondId,
    String secondToken,
  ) {
    final edge = firstId.compareTo(secondId) < 0
        ? <String, String>{
            'a': firstId,
            'aToken': firstToken,
            'b': secondId,
            'bToken': secondToken,
          }
        : <String, String>{
            'a': secondId,
            'aToken': secondToken,
            'b': firstId,
            'bToken': firstToken,
          };
    _edges = {..._edges, _edgeKey(firstId, secondId): edge};
  }

  void _pruneUnreachable() {
    if (_localId.isEmpty) return;
    final reachable = <String>{_localId};
    final queue = <String>[_localId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final edge in _edges.values) {
        final a = edge['a'];
        final b = edge['b'];
        final next = a == current
            ? b
            : b == current
            ? a
            : null;
        if (next != null && reachable.add(next)) queue.add(next);
      }
    }
    _edges = {
      for (final entry in _edges.entries)
        if (reachable.contains(entry.value['a']) &&
            reachable.contains(entry.value['b']))
          entry.key: entry.value,
    };
    _peerTokens = {
      for (final entry in _peerTokens.entries)
        if (reachable.contains(entry.key)) entry.key: entry.value,
    };
  }

  static bool _sameEdge(Map<String, String>? left, Map<String, String> right) {
    if (left == null) return false;
    return left['a'] == right['a'] &&
        left['aToken'] == right['aToken'] &&
        left['b'] == right['b'] &&
        left['bToken'] == right['bToken'];
  }

  static String _edgeKey(String a, String b) =>
      a.compareTo(b) < 0 ? '$a\u0000$b' : '$b\u0000$a';

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPeerTokens, jsonEncode(_peerTokens));
    await prefs.setString(_prefsEdges, jsonEncode(_edges.values.toList()));
  }
}
