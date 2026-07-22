import 'package:flutter/material.dart';

/// Canvas 绘制的环形 SOC 电量指示器
///
/// 背景弧 + 前景弧 + 中心百分比文字
class SocCircle extends StatelessWidget {
  final int soc;
  final double size;
  final double strokeWidth;

  const SocCircle({
    super.key,
    required this.soc,
    this.size = 56,
    this.strokeWidth = 5,
  });

  Color get _color {
    if (soc > 60) return Colors.green;
    if (soc > 20) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SocPainter(
          percentage: soc / 100.0,
          color: _color,
          strokeWidth: strokeWidth,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '$soc%',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocPainter extends CustomPainter {
  final double percentage;
  final Color color;
  final double strokeWidth;

  _SocPainter({
    required this.percentage,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -0.5 * 3.14159; // 从顶部 12 点钟开始
    const sweepAngle = 2.0 * 3.14159; // 完整 360° 圆

    // 背景弧
    final bgPaint = Paint()
      ..color = Colors.grey.shade200
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

    // 前景弧
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
  bool shouldRepaint(_SocPainter old) =>
      percentage != old.percentage || color != old.color;
}
