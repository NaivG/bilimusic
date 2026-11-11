import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bilimusic/app/app_providers.dart';
import 'package:bilimusic/shared/ui/controls/bm_field.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';

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
    final colors = context.bmColors;
    final type = context.bmType;
    return BmDialog(
      title: '配对请求',
      hasFields: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.peerName} 想要与你配对。',
            style: type.body.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: BmTokens.s3),
          Text(
            '请在 ${widget.peerName} 的"局域网同步"页查看 6 位 PIN 并输入：',
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: BmTokens.s2),
          BmField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            hintText: '6 位数字',
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _onConfirm(),
          ),
        ],
      ),
      actions: [
        BmDialogAction(label: '拒绝', enabled: !_busy, onPressed: _onReject),
        BmDialogAction(label: '确认', enabled: !_busy, onPressed: _onConfirm),
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
