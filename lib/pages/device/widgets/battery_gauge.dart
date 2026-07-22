import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// 渐变弧电量仪表盘
///
/// 270°弧（135°→405°），红→黄→绿渐变，中心大字SOC + 充放电状态
class BatteryGauge extends StatelessWidget {
  final int soc;
  final String chargeStatus;
  final double size;

  const BatteryGauge({
    super.key,
    required this.soc,
    required this.chargeStatus,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          percentage: soc / 100.0,
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // SOC 百分比大字
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$soc%',
                  style: TextStyle(
                    fontSize: size * 0.22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // 充放电状态
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                decoration: BoxDecoration(
                  color: soc > 50
                      ? AppColors.socGreen.withOpacity(0.12)
                      : AppColors.socYellow.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chargeStatus,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: soc > 50 ? AppColors.socGreen : AppColors.socYellow,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percentage;
  final bool isDark;

  _GaugePainter({required this.percentage, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;
    final strokeWidth = size.width * 0.09;

    const startAngle = math.pi * 0.75; // 135°
    const sweepAngle = math.pi * 1.5; // 270°

    // ── 背景弧 ──
    final bgPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200
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

    // ── 渐变前景弧 ──
    final rect = Rect.fromCircle(center: center, radius: radius + strokeWidth);
    final gradient = SweepGradient(
      startAngle: 0.0,
      endAngle: math.pi * 2,
      colors: const [
        AppColors.socRed,
        AppColors.socYellow,
        AppColors.socGreen,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final fgPaint = Paint()
      ..shader = gradient.createShader(rect)
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

    // ── 刻度点（每10%，圆点在内侧，SOC内绿色，SOC外灰色） ──
    final dotR = strokeWidth * 0.18;
    final innerR = radius - strokeWidth * 0.85; // 圆弧内侧更靠里
    final activePaint = Paint()
      ..color = AppColors.socGreen
      ..style = PaintingStyle.fill;
    final inactivePaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.2) : Colors.grey.shade300
      ..style = PaintingStyle.fill;

    for (int i = 0; i <= 10; i++) {
      final tickPct = i / 10.0;
      final angle = startAngle + (sweepAngle * tickPct);
      final tx = center.dx + innerR * math.cos(angle);
      final ty = center.dy + innerR * math.sin(angle);
      final paint = tickPct <= percentage ? activePaint : inactivePaint;
      canvas.drawCircle(Offset(tx, ty), dotR, paint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      percentage != old.percentage || isDark != old.isDark;
}
