import 'package:flutter/material.dart';

/// 信号强度指示器（柱状图 + dBm 数值）
class RssiIndicator extends StatelessWidget {
  final int rssi;

  const RssiIndicator({super.key, required this.rssi});

  Color get _color {
    if (rssi > -85) return Colors.green;
    if (rssi > -95) return Colors.orange;
    return Colors.red;
  }

  /// 将 RSSI 映射到 0~4 格
  int get _bars {
    if (rssi > -50) return 4;
    if (rssi > -70) return 3;
    if (rssi > -85) return 2;
    if (rssi > -95) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 柱状图
        SizedBox(
          height: 14,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) {
              final active = i < _bars;
              return Container(
                width: 3,
                height: 4.0 + i * 3,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: active
                      ? _color
                      : (isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$rssi dB',
          style: TextStyle(fontSize: 12, color: _color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
