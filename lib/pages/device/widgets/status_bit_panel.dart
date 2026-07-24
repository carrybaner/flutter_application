import 'package:flutter/material.dart';
import '../../../models/safety_flags.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme/app_theme.dart';

/// 状态位三栏面板
///
/// 三列：软件保护 / 硬件保护 / 告警。仅显示已触发项，无显示"正常"
class StatusBitPanel extends StatelessWidget {
  final AppStrings s;
  final int swFlags;
  final int hwFlags;
  final int alarmFlags;

  const StatusBitPanel({required this.s, 
    super.key,
    required this.swFlags,
    required this.hwFlags,
    required this.alarmFlags,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _FlagColumn(s: s, 
            title: s.battery.swProt,
            icon: Icons.shield,
            flags: swFlags,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FlagColumn(s: s, 
            title: s.battery.hwProt,
            icon: Icons.security,
            flags: hwFlags,
            isHardware: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FlagColumn(s: s, 
            title: s.battery.alarm,
            icon: Icons.warning_amber,
            flags: alarmFlags,
          ),
        ),
      ],
    );
  }
}

class _FlagColumn extends StatelessWidget {
  final String title;
  final IconData icon;
  final int flags;
  final bool isHardware;
  final AppStrings s;

  const _FlagColumn({
    required this.title,
    required this.icon,
    required this.flags,
    this.isHardware = false,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final active = isHardware ? SafetyFlags.parseAfe(flags) : SafetyFlags.parse(flags);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (active.isEmpty)
            Text(s.battery.normal,
                style: TextStyle(
                    color: AppColors.socGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 13))
          else
            ...active.map((f) => _flagChip(f)).toList(),
        ],
      ),
    );
  }

  Widget _flagChip(SafetyFlag f) {
    final isZh = s.locale == AppLocale.zh;
    final color = f.isCritical ? SafetyFlags.criticalColor : SafetyFlags.warningColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          f.displayLabel(isZh),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
