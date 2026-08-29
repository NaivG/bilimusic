import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 显示本机的"配对二维码"——内容为 `{id}|{name}|{pin}`，供对方扫码后用。
///
/// TODO(未实现功能): 项目内暂无扫码端（无 mobile_scanner 等扫码依赖），
/// "扫一扫"入口未实现，二维码 payload 目前无人消费；待扫码配对实现后移除此提示。
///
/// 对方扫到后用我们的 id/name/PIN 主动发起配对（PIN 在对方 hello-ack 之前
/// 直接随 hello / pin 消息带过去，省去手动输入）。
class PairQrDialog extends StatelessWidget {
  final String deviceId;
  final String deviceName;
  final String pin;

  const PairQrDialog({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.pin,
  });

  String get _qrPayload => '$deviceId|$deviceName|$pin';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_2, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '本机配对码',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: PrettyQrView.data(
                      data: _qrPayload,
                      decoration: const PrettyQrDecoration(
                        shape: PrettyQrSquaresSymbol(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _LabeledLine(
                label: '设备名',
                value: deviceName,
                onCopy: () => _copy(context, deviceName),
              ),
              const SizedBox(height: 8),
              _LabeledLine(
                label: '6 位 PIN',
                value: pin,
                onCopy: () => _copy(context, pin),
                monospace: true,
              ),
              const SizedBox(height: 12),
              Text(
                '在对方设备"局域网同步"页点"扫一扫"即可完成配对；'
                'PIN 是一次性的，重置后会失效。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }
}

class _LabeledLine extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool monospace;

  const _LabeledLine({
    required this.label,
    required this.value,
    required this.onCopy,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: monospace ? 16 : 14,
              fontFamily: monospace ? 'monospace' : null,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          visualDensity: VisualDensity.compact,
          tooltip: '复制',
          onPressed: onCopy,
        ),
      ],
    );
  }
}
