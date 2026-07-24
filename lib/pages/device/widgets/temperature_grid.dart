import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../i18n/app_strings.dart';

/// 温度宫格（探头 + MOS）
class TemperatureGrid extends StatelessWidget {
  final AppStrings s;
  final Map<String, double> temperatures;
  const TemperatureGrid({super.key, required this.temperatures, required this.s});

  Color _tempColor(double temp) {
    if (temp > 45) return AppColors.socRed;
    if (temp > 35) return AppColors.socYellow;
    return AppColors.socGreen;
  }

  @override
  Widget build(BuildContext context) {
    if (temperatures.isEmpty) {
      return Text(s.battery.noData, style: const TextStyle(color: Colors.grey));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = temperatures.entries.toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final label = entries[i].key;
        final temp = entries[i].value;
        final color = _tempColor(temp);

        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.thermostat, color: color, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '${temp.toStringAsFixed(1)}°C',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
