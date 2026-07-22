import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/device_data_provider.dart' show realtimeDataProvider;
import '../../../theme/app_theme.dart';
import '../widgets/battery_gauge.dart';
import '../widgets/cell_voltage_grid.dart';
import '../widgets/temperature_grid.dart';
import '../widgets/status_bit_panel.dart';
import '../widgets/segmented_switch.dart';

/// 电池信息 Tab — 消费 RealtimePoller 的实时数据
class BatteryInfoTab extends ConsumerWidget {
  const BatteryInfoTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(realtimeDataProvider);
    final batteryInfo = data['BatteryInfo'];
    final cellVoltage = data['Cell Voltage'];
    final tempCh = data['Tempe CH'];
    final afeStatus = data['AFE Status'];
    final bmsTime = data['BMS Time'];

    if (batteryInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _BatteryInfoContent(
      batteryInfo: batteryInfo,
      cellVoltage: cellVoltage,
      tempCh: tempCh,
      afeStatus: afeStatus,
      bmsTime: bmsTime,
    );
  }
}

class _BatteryInfoContent extends StatefulWidget {
  final Map<String, dynamic> batteryInfo;
  final Map<String, dynamic>? cellVoltage;
  final Map<String, dynamic>? tempCh;
  final Map<String, dynamic>? afeStatus;
  final Map<String, dynamic>? bmsTime;

  const _BatteryInfoContent({
    required this.batteryInfo,
    this.cellVoltage,
    this.tempCh,
    this.afeStatus,
    this.bmsTime,
  });

  @override
  State<_BatteryInfoContent> createState() => _BatteryInfoContentState();
}

class _BatteryInfoContentState extends State<_BatteryInfoContent> {
  int _segmentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final info = widget.batteryInfo;

    // 从协议字段取值
    final soc = (info['SOC'] as num?)?.toInt() ?? 0;
    final voltage = (info['BatteryVoltage'] as num?)?.toDouble() ?? 0;
    final current = (info['Current'] as num?)?.toDouble() ?? 0;
    final power = (voltage * current.abs()).toString();
    final cycleCount = (info['Cycle_Count'] as num?)?.toInt() ?? 0;
    final soh = (info['SOH'] as num?)?.toInt() ?? 0;
    final remainingCap = (info['RemainingCapacity'] as num?)?.toString() ?? '--';
    final fullCap = ((info['FullChargeCapacity'] ?? info['Full Capacity']) as num?)?.toString() ?? '--';
    final timeToEmpty = (info['AverageTimeToEmpty'] as num?)?.toInt() ?? 0;
    final timeToFull = (info['AverageTimeToFull'] as num?)?.toInt() ?? 0;
    final isCharging = current > 0;
    final isDischarging = current < 0;
    final chargeStatus = isCharging ? '充电中' : (isDischarging ? '放电中' : '待机');
    String? remainingTimeLabel;
    String? remainingTime;
    if (isCharging && timeToFull < 65500) {
      remainingTimeLabel = '充满';
      remainingTime = '${timeToFull}min';
    } else if (isDischarging && timeToEmpty < 65500) {
      remainingTimeLabel = '放空';
      remainingTime = '${timeToEmpty}min';
    }

    // 单体电压列表
    List<double> cellVoltages = [];
    if (widget.cellVoltage != null) {
      for (int i = 1; i <= 24; i++) {
        final v = widget.cellVoltage!['Voltage $i'];
        if (v is num && v > 0) {
          cellVoltages.add(v.toDouble() / 1000.0); // mV → V
        }
      }
    }

    // 温度列表（探头 + MOS）
    final temperatures = <String, double>{};
    if (widget.tempCh != null) {
      for (int i = 1; i <= 5; i++) {
        final t = widget.tempCh!['Temper$i'];
        if (t is num && t > 0) {
          temperatures['探头 $i'] = t.toDouble();
        }
      }
      final mos = widget.tempCh!['MOS Temper'];
      if (mos is num && mos > 0) {
        temperatures['MOS'] = mos.toDouble();
      }
    }

    // 保护/告警状态位
    // BatteryAlarm → 告警  BatterySafety → 软件保护  AFE Status → 硬件保护
    final alarmData = info['BatteryAlarm'];
    final safetyData = info['BatterySafety'];
    final afeData = widget.afeStatus?['AFE Safety'];
    final swFlags = _extractBitFlags(safetyData);
    final hwFlags = _extractBitFlags(afeData);
    final alarmRaw = _extractBitFlags(alarmData);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 板块1：仪表盘 + 指标
          _SectionCard(
            child: Column(
              children: [
                BatteryGaugeSection(
                  soc: soc,
                  chargeStatus: chargeStatus,
                  voltage: voltage,
                  current: current,
                  bmsTime: _formatBmsTime(widget.bmsTime),
                ),
                const SizedBox(height: 8),
                _IndicatorGrid(
                  power: power,
                  cycleCount: cycleCount,
                  soh: soh,
                  remainingCap: remainingCap,
                  fullCap: fullCap,
                  remainingTimeLabel: remainingTimeLabel,
                  remainingTime: remainingTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 板块2：分段切换
          _SectionCard(
            child: Column(
              children: [
                SegmentedSwitch(
                  segments: const ['单体电压', '温度', '状态位'],
                  selectedIndex: _segmentIndex,
                  onChanged: (i) => setState(() => _segmentIndex = i),
                ),
                const SizedBox(height: 16),
                if (_segmentIndex == 0)
                  CellVoltageGrid(cellVoltages: cellVoltages)
                else if (_segmentIndex == 1)
                  TemperatureGrid(temperatures: temperatures)
                else
                  StatusBitPanel(
                    swFlags: swFlags,
                    hwFlags: hwFlags,
                    alarmFlags: alarmRaw,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _extractBitFlags(dynamic data) {
    if (data is List) {
      int flags = 0;
      for (int i = 0; i < data.length && i < 16; i++) {
        if (data[i] is Map && (data[i]['value'] as num?)?.toInt() == 1) {
          flags |= (1 << i);
        }
      }
      return flags;
    }
    return 0;
  }

  String _formatBmsTime(Map<String, dynamic>? bmsTime) {
    if (bmsTime == null) return '';
    final t = bmsTime['BMS Time'];
    return t?.toString() ?? '';
  }
}

/// 仪表盘区域（移除BmsData依赖，改用原始值）
class BatteryGaugeSection extends StatelessWidget {
  final int soc;
  final String chargeStatus;
  final double voltage;
  final double current;
  final String bmsTime;

  const BatteryGaugeSection({
    super.key,
    required this.soc,
    required this.chargeStatus,
    required this.voltage,
    required this.current,
    required this.bmsTime,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(
          child: BatteryGauge(
            soc: soc,
            chargeStatus: chargeStatus,
            size: 220,
          ),
        ),
        Positioned(
          top: 0,
          right: 4,
          child: Text(
            bmsTime,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[500], fontSize: 13),
          ),
        ),
        Positioned(
          top: 50,
          left: 0,
          child: _CornerLabel(
            label: '电压',
            value: voltage.toString(),
            unit: 'V',
          ),
        ),
        Positioned(
          top: 50,
          right: 0,
          child: _CornerLabel(
            label: '电流',
            value: current.toString(),
            unit: 'A',
          ),
        ),
      ],
    );
  }
}

class _CornerLabel extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  const _CornerLabel({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('$label $unit',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _IndicatorGrid extends StatelessWidget {
  final String power;
  final int cycleCount;
  final int soh;
  final String remainingCap;
  final String fullCap;
  final String? remainingTimeLabel;
  final String? remainingTime;

  const _IndicatorGrid({
    required this.power,
    required this.cycleCount,
    required this.soh,
    required this.remainingCap,
    required this.fullCap,
    required this.remainingTimeLabel,
    required this.remainingTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _IndicatorCard(label: '功率', value: '${power}W')),
            const SizedBox(width: 10),
            Expanded(child: _IndicatorCard(label: '循环次数', value: '${cycleCount}次')),
            const SizedBox(width: 10),
            Expanded(child: _IndicatorCard(label: '电池健康', value: '$soh%')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _IndicatorCard(label: '剩余容量', value: '${remainingCap}Ah')),
            const SizedBox(width: 10),
            Expanded(child: _IndicatorCard(label: '满充容量', value: '${fullCap}Ah')),
            const SizedBox(width: 10),
            Expanded(
                child: remainingTimeLabel != null && remainingTime != null
                    ? _IndicatorCard(
                        label: remainingTimeLabel!,
                        value: remainingTime!)
                    : const SizedBox()),
          ],
        ),
      ],
    );
  }
}

class _IndicatorCard extends StatelessWidget {
  final String label;
  final String value;
  const _IndicatorCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade200,
        ),
      ),
      child: child,
    );
  }
}
