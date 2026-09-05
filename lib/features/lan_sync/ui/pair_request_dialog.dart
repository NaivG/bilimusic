import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/core/app_providers.dart';

/// 被动方收到对方 hello 时弹的"输入对端 PIN + 接受或拒绝"弹窗。
///
/// 流程：对方发来 PinMessage（携带其输入的"我端 PIN"），本端 [_handlePin] 已经
/// 用 pairing.verifyPin 校验通过；这里再让用户输入"对方的 PIN"通过
/// [LanSyncService.acceptPeerPairing] 回传给对端做最终校验。两侧都通过才进
/// syncing；任意一侧拒绝 / PIN 错误都会断开。
class PairRequestDialog extends ConsumerStatefulWidget {
  final String peerId;
  final String peerName;

  const PairRequestDialog({
    super.key,
    required this.peerId,
    required this.peerName,
  });

  @override
  ConsumerState<PairRequestDialog> createState() => _PairRequestDialogState();
}

class _PairRequestDialogState extends ConsumerState<PairRequestDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.devices),
          const SizedBox(width: 8),
          Expanded(child: Text('配对请求', style: theme.textTheme.titleMedium)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.peerName} 想要与你配对。', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            '请在 ${widget.peerName} 的"局域网同步"页查看 6 位 PIN 并输入：',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              hintText: '6 位数字',
              counterText: '',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _onConfirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _onReject,
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: _busy ? null : _onConfirm,
          child: const Text('确认'),
        ),
      ],
    );
  }

  void _onConfirm() {
    final pin = _controller.text.trim();
    if (pin.length != 6 || int.tryParse(pin) == null) {
      setState(() => _error = '请输入 6 位数字');
      return;
    }
    setState(() => _busy = true);
    ref.read(lanSyncServiceProvider).acceptPeerPairing(widget.peerId, pin);
    Navigator.pop(context, true);
  }

  void _onReject() {
    setState(() => _busy = true);
    ref.read(lanSyncServiceProvider).rejectPeerPairing(widget.peerId);
    Navigator.pop(context, false);
  }
}
