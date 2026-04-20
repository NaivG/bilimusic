import 'package:flutter/material.dart';

Widget infoRow(String label, String value, {TextStyle? labelStyle, TextStyle? valueStyle}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 60, child: Text(label, style: labelStyle)),
        Expanded(child: Text(value, style: valueStyle ?? const TextStyle(color: Colors.white))),
      ],
    ),
  );
}