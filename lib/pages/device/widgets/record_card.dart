import 'package:flutter/material.dart';
import '../../../models/abnormal_record.dart';
import '../../../i18n/app_strings.dart';
import '../../../models/safety_flags.dart';
import '../../../theme/app_theme.dart';

/// 异常记录卡片
class RecordCard extends StatelessWidget {
  final AppStrings s;
  final AbnormalRecord record;
  const RecordCard({super.key, required this.record, required this.s});

  String get _formatTime {
    final dt = record.timestamp;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
        ' ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  List<SafetyFlag> get _allFlags => [
        ...SafetyFlags.parse(record.batterySafety),
        ...SafetyFlags.parseAfe(record.afeSafety),
        ...SafetyFlags.parseFail(record.safetyFail),
      ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allFlags = _allFlags;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶行: 序号 + 时间 + 保护状态
          Row(
            children: [
              Text(
                '#${record.sequenceNumber.toString().padLeft(3, '0')}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatTime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              if (allFlags.isNotEmpty)
                Flexible(
                  child: SizedBox(
                    height: 20,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: allFlags.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 3),
                      itemBuilder: (_, i) {
                        final f = allFlags[i];
                        final color = f.isCritical
                            ? SafetyFlags.criticalColor
                            : SafetyFlags.warningColor;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: color.withOpacity(0.4), width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            f.displayLabel(s.locale == AppLocale.zh),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),
          Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade200),
          const SizedBox(height: 8),

          // Row 1: 电流 / 最高电压 / 最低电压
          Row(
            children: [
              _DataField(
                  label: s.record.current, value: '${record.current.toStringAsFixed(3)}A'),
              const SizedBox(width: 8),
              _DataField(
                  label: s.record.maxVoltage,
                  value: '${record.maxVoltage.toStringAsFixed(3)}V'),
              const SizedBox(width: 8),
              _DataField(
                  label: s.record.minVoltage,
                  value: '${record.minVoltage.toStringAsFixed(3)}V'),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: MOS温度 / 最高温度 / 最低温度
          Row(
            children: [
              _DataField(
                  label: s.record.mosTemp,
                  value: '${record.mosTemp.toStringAsFixed(1)}°C'),
              const SizedBox(width: 8),
              _DataField(
                  label: s.record.maxTemp,
                  value: '${record.maxTemp.toStringAsFixed(1)}°C'),
              const SizedBox(width: 8),
              _DataField(
                  label: s.record.minTemp,
                  value: '${record.minTemp.toStringAsFixed(1)}°C'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DataField extends StatelessWidget {
  final String label;
  final String value;
  const _DataField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
