import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../i18n/app_strings.dart';

/// 24 单体电压网格
///
/// 摘要行（最高/最低/压差）+ 24格(6列×4行)，高亮最大(绿)最小(红)
/// [balancingCells] 正在均衡的 cell 索引集合（0-based），右上角显示蓝色圆点
class CellVoltageGrid extends StatelessWidget {
  final AppStrings s;
  final List<double> cellVoltages;
  final Set<int> balancingCells;
  const CellVoltageGrid({super.key, required this.cellVoltages, required this.s, this.balancingCells = const {}});

  @override
  Widget build(BuildContext context) {
    if (cellVoltages.isEmpty) {
      return Text(s.battery.noData, style: TextStyle(color: Colors.grey));
    }

    final maxV = cellVoltages.reduce((a, b) => a > b ? a : b);
    final minV = cellVoltages.reduce((a, b) => a < b ? a : b);
    final delta = maxV - minV;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 摘要行 ──
        Row(
          children: [
            _SummaryChip(
                label: s.battery.max, value: '${maxV.toStringAsFixed(3)}V', color: AppColors.socGreen),
            const SizedBox(width: 10),
            _SummaryChip(
                label: s.battery.min, value: '${minV.toStringAsFixed(3)}V', color: AppColors.socRed),
            const SizedBox(width: 10),
            _SummaryChip(
                label: s.battery.delta,
                value: '${delta.toStringAsFixed(3)}V',
                color: delta > 0.2 ? AppColors.socRed : AppColors.socYellow),
          ],
        ),
        const SizedBox(height: 12),

        // ── 24 格 Grid ──
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            childAspectRatio: 1.3,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: cellVoltages.length,
          itemBuilder: (_, i) {
            final v = cellVoltages[i];
            final isMax = v == maxV;
            final isMin = v == minV;

            Color bgColor;
            Color textColor;
            Color borderColor;

            if (isMax) {
              bgColor = AppColors.socGreen.withOpacity(0.12);
              textColor = AppColors.socGreen;
              borderColor = AppColors.socGreen.withOpacity(0.4);
            } else if (isMin) {
              bgColor = AppColors.socRed.withOpacity(0.1);
              textColor = AppColors.socRed;
              borderColor = AppColors.socRed.withOpacity(0.3);
            } else {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              bgColor = isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade50;
              textColor = Theme.of(context).colorScheme.onSurface;
              borderColor = isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200;
            }

            final isBalancing = balancingCells.contains(i);

            return Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${i + 1}',
                          style: TextStyle(fontSize: 9,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        Text(
                          v.toStringAsFixed(3),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isBalancing)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 0.5),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
