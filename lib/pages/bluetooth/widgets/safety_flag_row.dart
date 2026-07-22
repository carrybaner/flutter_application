import 'package:flutter/material.dart';
import '../../../models/safety_flags.dart';

/// 保护状态标签行
///
/// 将 16-bit safetyFlags 展开为彩色标签：
/// - 红色 = 严重告警
/// - 橙色 = 普通报警
/// - 只显示 bit=1 的项，bit=0 不显示
class SafetyFlagRow extends StatelessWidget {
  final int flags;

  const SafetyFlagRow({super.key, required this.flags});

  @override
  Widget build(BuildContext context) {
    final active = SafetyFlags.parse(flags);
    if (active.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: active.map((f) => _FlagChip(flag: f)).toList(),
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  final SafetyFlag flag;
  const _FlagChip({required this.flag});

  @override
  Widget build(BuildContext context) {
    final color =
        flag.isCritical ? SafetyFlags.criticalColor : SafetyFlags.warningColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.5),
      ),
      child: Text(
        flag.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
