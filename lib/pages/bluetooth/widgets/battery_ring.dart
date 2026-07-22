import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// 环形电量指示器（用于设备列表卡片）
///
/// 完整圆弧背景 + 按SOC着色前景弧 + 中心百分比文字
/// soc = -1 时表示无广播数据，显示灰色占位
class BatteryRing extends StatelessWidget {
  final int soc;
  final double size;
  final double strokeWidth;

  const BatteryRing({
    super.key,
    required this.soc,
    this.size = 56,
    this.strokeWidth = 5,
  });

  /// 无广播数据时为灰色
  bool get _noData => soc < 0;

  Color get _color {
    if (_noData) return Colors.grey;
    if (soc > 60) return AppColors.socGreen;
    if (soc > 20) return AppColors.socYellow;
    return AppColors.socRed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          percentage: _noData ? 0.0 : soc / 100.0,
          color: _color,
          strokeWidth: strokeWidth,
          isDark: isDark,
          noData: _noData,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                _noData ? '--' : '$soc%',
                style: TextStyle(
                  fontSize: size * (_noData ? 0.22 : 0.26),
                  fontWeight: FontWeight.w700,
                  color: _noData
                      ? (isDark ? Colors.white38 : Colors.grey)
                      : _color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percentage;
  final Color color;
  final double strokeWidth;
  final bool isDark;
  final bool noData;

  _RingPainter({
    required this.percentage,
    required this.color,
    required this.strokeWidth,
    required this.isDark,
    this.noData = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    const startAngle = -math.pi / 2;
    const sweepAngle = 2 * math.pi;

    // 背景圆弧
    final bgPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // 无数据时不画前景弧
    if (noData) return;

    // 前景圆弧
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * percentage.clamp(0.0, 1.0),
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      percentage != old.percentage ||
      color != old.color ||
      isDark != old.isDark ||
      noData != old.noData;
}
