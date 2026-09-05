import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// 白底二维码渲染壳 —— 登录二维码与配对二维码共用。
///
/// [data] 为空时显示加载态（二维码尚未生成）。
class QrPanel extends StatelessWidget {
  final String? data;

  /// 二维码绘制区边长（不含白底内边距）。
  final double size;

  const QrPanel({super.key, required this.data, this.size = 220});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: SizedBox(
        width: size,
        height: size,
        child: data == null
            ? const Center(child: CircularProgressIndicator())
            : PrettyQrView.data(
                data: data!,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSquaresSymbol(),
                ),
              ),
      ),
    );
  }
}
