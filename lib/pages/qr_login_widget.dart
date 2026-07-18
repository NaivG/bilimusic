import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'package:bilimusic/core/service_locator.dart';
import 'package:bilimusic/services/qr_login_service.dart';
import 'package:bilimusic/utils/network_config.dart';

/// 扫码登录面板
/// 展示二维码并轮询扫码状态；登录成功时写 cookie、刷新 UserManager 并回调 [onSuccess]。
class QrLoginWidget extends StatefulWidget {
  /// 登录成功后的回调（由父组件决定如何退出登录页）
  final VoidCallback onSuccess;

  const QrLoginWidget({super.key, required this.onSuccess});

  @override
  State<QrLoginWidget> createState() => _QrLoginWidgetState();
}

class _QrLoginWidgetState extends State<QrLoginWidget> {
  static const Duration _qrTtl = Duration(seconds: 180);
  static const Duration _pollInterval = Duration(seconds: 1);

  final QrLoginService _service = QrLoginService();

  QrLoginInfo? _info;
  QrPollStatus _status = QrPollStatus.waiting;
  DateTime? _expiresAt;
  DateTime _now = DateTime.now();
  String? _errorMessage;
  bool _isGenerating = false;
  int _consecutiveErrors = 0;

  Timer? _pollTimer;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final info = await _service.generate();
      _consecutiveErrors = 0;
      final expiresAt = DateTime.now().add(_qrTtl);
      if (!mounted) return;
      setState(() {
        _info = info;
        _status = QrPollStatus.waiting;
        _expiresAt = expiresAt;
        _now = DateTime.now();
        _isGenerating = false;
      });
      _startTimers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _tickerTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _pollOnce() async {
    final info = _info;
    if (info == null) return;
    if (_status == QrPollStatus.success || _status == QrPollStatus.expired) {
      _pollTimer?.cancel();
      return;
    }

    try {
      final result = await _service.poll(info.qrcodeKey);
      _consecutiveErrors = 0;
      if (!mounted) return;

      if (result.status == QrPollStatus.success) {
        if (result.cookies.isNotEmpty) {
          NetworkConfig.updateCookies(result.cookies);
        }
        _stopTimers();
        setState(() => _status = QrPollStatus.success);
        // 通知 UserManager 刷新用户信息
        sl.userManager.clear();
        sl.userManager.getUserInfo(forceRefresh: true);
        widget.onSuccess();
      } else {
        setState(() => _status = result.status);
      }
    } catch (_) {
      // 忽略网络抖动；连续失败 5 次再切到 error
      _consecutiveErrors++;
      if (_consecutiveErrors >= 5 && mounted) {
        setState(() {
          _status = QrPollStatus.unknown;
          _errorMessage = '网络异常，请检查后刷新';
        });
      }
    }
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  int get _remainingSeconds {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return 0;
    final diff = expiresAt.difference(_now).inSeconds;
    return diff > 0 ? diff : 0;
  }

  String get _hintText {
    switch (_status) {
      case QrPollStatus.waiting:
        return '请使用哔哩哔哩手机客户端扫码';
      case QrPollStatus.scanned:
        return '扫描成功，请在手机上确认登录';
      case QrPollStatus.success:
        return '登录成功';
      case QrPollStatus.expired:
        return '二维码已失效';
      case QrPollStatus.unknown:
        return _errorMessage ?? '未知状态';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    final remaining = _remainingSeconds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          _hintText,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: _status == QrPollStatus.success
                ? Colors.green
                : _status == QrPollStatus.expired
                ? theme.colorScheme.error
                : theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isGenerating || info == null
                ? const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : SizedBox(
                    width: 220,
                    height: 220,
                    child: PrettyQrView.data(
                      data: info.url,
                      decoration: const PrettyQrDecoration(
                        shape: PrettyQrSquaresSymbol(),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          info != null ? '有效期 ${remaining}s' : '',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_errorMessage != null && info == null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _isGenerating ? null : _generate,
          icon: const Icon(Icons.refresh),
          label: Text(_status == QrPollStatus.expired ? '刷新二维码' : '刷新'),
        ),
        const SizedBox(height: 8),
        Text(
          '提示：扫码登录不会触发极验人机验证，是桌面端推荐的方式',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
