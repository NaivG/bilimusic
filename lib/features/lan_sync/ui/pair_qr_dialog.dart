import 'package:flutter/material.dart';

import 'package:bilimusic/shared/ui/controls/bm_icon_button.dart';
import 'package:bilimusic/shared/ui/overlay/bm_dialog.dart';
import 'package:bilimusic/shared/ui/tokens/bm_colors.dart';
import 'package:bilimusic/shared/ui/tokens/bm_tokens.dart';
import 'package:bilimusic/shared/ui/tokens/bm_typography.dart';
import 'package:bilimusic/shared/utils/clipboard_helpers.dart';
import 'package:bilimusic/shared/widgets/qr_panel.dart';

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
    final colors = context.bmColors;
    final type = context.bmType;
    return BmDialog(
      title: '本机配对码',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: QrPanel(data: _qrPayload),
            ),
          ),
          const SizedBox(height: BmTokens.s4),
          _LabeledLine(
            label: '设备名',
            value: deviceName,
            onCopy: () => copyToClipboard(context, deviceName),
          ),
          const SizedBox(height: BmTokens.s2),
          _LabeledLine(
            label: '6 位 PIN',
            value: pin,
            onCopy: () => copyToClipboard(context, pin),
            monospace: true,
          ),
          const SizedBox(height: BmTokens.s3),
          Text(
            '在对方设备"局域网同步"页点"扫一扫"即可完成配对；'
            'PIN 是一次性的，重置后会失效。',
            style: type.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
      actions: [
        BmDialogAction(
          label: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
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
    final colors = context.bmColors;
    final type = context.bmType;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.label.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.bodyStrong.copyWith(
              color: colors.textPrimary,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
        BmIconButton(
          icon: Icons.copy,
          tooltip: '复制',
          size: BmIconButtonSize.sm,
          onPressed: onCopy,
        ),
      ],
    );
  }
}
