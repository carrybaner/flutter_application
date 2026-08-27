import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/device_data_provider.dart' show realtimeDataProvider, connectionResultProvider;
import '../../../i18n/app_strings.dart';
import '../../../i18n/locale_provider.dart';
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
    final version = ref.watch(connectionResultProvider)?.version ?? '';

    if (batteryInfo == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _BatteryInfoContent(
      batteryInfo: batteryInfo,
      cellVoltage: cellVoltage,
      tempCh: tempCh,
      afeStatus: afeStatus,
      bmsTime: bmsTime,
      version: version,
    );
  }
}

class _BatteryInfoContent extends ConsumerStatefulWidget {
  final Map<String, dynamic> batteryInfo;
  final Map<String, dynamic>? cellVoltage;
  final Map<String, dynamic>? tempCh;
  final Map<String, dynamic>? afeStatus;
  final Map<String, dynamic>? bmsTime;
  final String version;

  const _BatteryInfoContent({
    required this.batteryInfo,
    this.cellVoltage,
    this.tempCh,
    this.afeStatus,
    this.bmsTime,
    this.version = '',
  });

  @override
  ConsumerState<_BatteryInfoContent> createState() => _BatteryInfoContentState();
}

class _BatteryInfoContentState extends ConsumerState<_BatteryInfoContent> {
  int _segmentIndex = 0;
  AppStrings _s = AppStrings.zh;

  @override
  Widget build(BuildContext context) {
    _s = ref.watch(localeProvider);
    final info = widget.batteryInfo;

    // 从协议字段取值
    final soc = (info['SOC'] as num?)?.toInt() ?? 0;
    final voltage = (info['BatteryVoltage'] as num?)?.toDouble() ?? 0;
    final current = (info['Current'] as num?)?.toDouble() ?? 0;
    final power = (voltage * current.abs()).toInt().toString();
    final cycleCount = (info['Cycle_Count'] as num?)?.toInt() ?? 0;
    final soh = (info['SOH'] as num?)?.toInt() ?? 0;
    final remainingCap = (info['RemainingCapacity'] as num?)?.toStringAsFixed(2) ?? '--';
    final fullCap = ((info['FullChargeCapacity'] ?? info['Full Capacity']) as num?)?.toStringAsFixed(2) ?? '--';
    final timeToEmpty = (info['AverageTimeToEmpty'] as num?)?.toInt() ?? 0;
    final timeToFull = (info['AverageTimeToFull'] as num?)?.toInt() ?? 0;
    final isCharging = current > 0;
    final isDischarging = current < 0;
    final chargeStatus = isCharging ? _s.battery.charging : (isDischarging ? _s.battery.discharging : _s.battery.standby);
    String? remainingTimeLabel;
    String? remainingTime;
    if (isCharging && timeToFull < 65500) {
      remainingTimeLabel = _s.battery.timeToFull;
      remainingTime = '${timeToFull}min';
    } else if (isDischarging && timeToEmpty < 65500) {
      remainingTimeLabel = _s.battery.timeToEmpty;
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
          temperatures[_s.battery.probe + ' $i'] = t.toDouble();
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

    // 充放电 MOS 状态（来自 AFE Status 状态位：bit0=CHG_FET, bit1=DSG_FET）
    final afeRaw = _afeRawValue(widget.afeStatus?['AFE Status']);
    final chargeMosOn = (afeRaw != null) && ((afeRaw >> 0) & 1) == 1;
    final dischargeMosOn = (afeRaw != null) && ((afeRaw >> 1) & 1) == 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 板块1：仪表盘 + 指标
          _SectionCard(
            child: Column(
              children: [
                BatteryGaugeSection(s: _s,
                  soc: soc,
                  chargeStatus: chargeStatus,
                  voltage: voltage,
                  current: current,
                  bmsTime: _formatBmsTime(widget.bmsTime),
                  version: widget.version,
                  chargeMosOn: chargeMosOn,
                  dischargeMosOn: dischargeMosOn,
                ),
                _IndicatorGrid(s: _s,
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
                  segments: [_s.battery.cellVoltage, _s.battery.temperature, _s.battery.statusBits],
                  selectedIndex: _segmentIndex,
                  onChanged: (i) => setState(() => _segmentIndex = i),
                ),
                const SizedBox(height: 16),
                if (_segmentIndex == 0)
                  CellVoltageGrid(s: _s,
                    cellVoltages: cellVoltages,
                    balancingCells: _parseBalancingCells(widget.afeStatus),
                  )
                else if (_segmentIndex == 1)
                  TemperatureGrid(s: _s, temperatures: temperatures)
                else
                  StatusBitPanel(s: _s,
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

  /// 从 AFE Status 原始值提取整数（兼容 int / 0x hex / BitDesc List 三种格式）
  int? _afeRawValue(dynamic afeData) {
    if (afeData is int) return afeData;
    if (afeData is String && afeData.startsWith('0x')) {
      return int.tryParse(afeData.substring(2), radix: 16);
    }
    if (afeData is List) {
      int v = 0;
      for (final item in afeData) {
        if (item is Map) {
          final key = item['key'] as String?;
          if (key == 'CHG_FET' && item['value'] == 1) v |= (1 << 0);
          if (key == 'DSG_FET' && item['value'] == 1) v |= (1 << 1);
        }
      }
      return v;
    }
    return null;
  }

  /// 从 AFE Status 中解析均衡电芯索引（0-based）
  Set<int> _parseBalancingCells(Map<String, dynamic>? afeStatus) {
    if (afeStatus == null) return {};
    final cells = <int>{};

    for (int balanIdx = 1; balanIdx <= 3; balanIdx++) {
      final raw = afeStatus['AFE1 CELL BALAN$balanIdx'];
      int bits = 0;

      if (raw is int) {
        bits = raw;
      } else if (raw is String && raw.startsWith('0x')) {
        bits = int.tryParse(raw.substring(2), radix: 16) ?? 0;
      } else if (raw is List) {
        for (int i = 0; i < raw.length && i < 8; i++) {
          if (raw[i] is Map && (raw[i]['value'] as num?)?.toInt() == 1) {
            bits |= (1 << i);
          }
        }
      }

      final base = (balanIdx - 1) * 8;
      for (int bit = 0; bit < 8; bit++) {
        if ((bits >> bit) & 1 == 1) {
          cells.add(base + bit);
        }
      }
    }
    return cells;
  }

  String _formatBmsTime(Map<String, dynamic>? bmsTime) {
    if (bmsTime == null) return '';
    final t = bmsTime['BMS Time'];
    return t?.toString() ?? '';
  }
}

/// 仪表盘区域（移除BmsData依赖，改用原始值）
class BatteryGaugeSection extends StatelessWidget {
  final AppStrings s;
  final int soc;
  final String chargeStatus;
  final double voltage;
  final double current;
  final String bmsTime;
  final String version;
  final bool chargeMosOn;
  final bool dischargeMosOn;

  const BatteryGaugeSection({
    super.key,
    required this.s,
    required this.soc,
    required this.chargeStatus,
    required this.voltage,
    required this.current,
    required this.bmsTime,
    this.version = '',
    this.chargeMosOn = false,
    this.dischargeMosOn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 版本在最左、BMS 时间在右，独立一行，不再与仪表盘重叠
        if (bmsTime.isNotEmpty || version.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (version.isNotEmpty)
                Text(
                  '${s.battery.version}$version',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13),
                ),
              if (bmsTime.isNotEmpty)
                Text(
                  bmsTime,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13),
                ),
            ],
          ),
        const SizedBox(height: 4),
        // 仪表盘 + 电压/电流 叠加
        Stack(
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
              top: 50,
              left: 0,
              child: _CornerLabel(
                label: s.battery.voltage,
                value: voltage.toStringAsFixed(3),
                unit: 'V',
              ),
            ),
            Positioned(
              top: 50,
              right: 0,
              child: _CornerLabel(
                label: s.battery.current,
                value: current.toStringAsFixed(3),
                unit: 'A',
              ),
            ),
            // 充电/放电指示灯：文字在上、灯在下，位于仪表盘两侧偏上
            Positioned(
              left: 8,
              bottom: 16,
              child: _MosIndicator(
                label: s.battery.charge,
                on: chargeMosOn,
              ),
            ),
            Positioned(
              right: 8,
              bottom: 16,
              child: _MosIndicator(
                label: s.battery.discharge,
                on: dischargeMosOn,
              ),
            ),
          ],
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

/// 充放电 MOS 状态指示灯：文字在上、灯在下，开=绿带光晕，关=红
class _MosIndicator extends StatelessWidget {
  final String label;
  final bool on;

  const _MosIndicator({required this.label, required this.on});

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.socGreen : AppColors.dangerRed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
        const SizedBox(height: 3),
        // 指示灯
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: on
                ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 4)]
                : null,
          ),
        ),
      ],
    );
  }
}

class _IndicatorGrid extends StatelessWidget {
  final AppStrings s;
  final String power;
  final int cycleCount;
  final int soh;
  final String remainingCap;
  final String fullCap;
  final String? remainingTimeLabel;
  final String? remainingTime;

  const _IndicatorGrid({
    required this.s,
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
            Expanded(child: _IndicatorCard(label: s.battery.power, value: '${power}W')),
            const SizedBox(width: 10),
            Expanded(child: _IndicatorCard(label: s.battery.cycles, value: '$cycleCount${s.battery.cyclesUnit}')),
            const SizedBox(width: 10),
            Expanded(child: _IndicatorCard(label: s.battery.health, value: '$soh%')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _IndicatorCard(label: s.battery.remainingCap, value: '${remainingCap}Ah')),
            const SizedBox(width: 10),
            Expanded(child: _IndicatorCard(label: s.battery.fullCap, value: '${fullCap}Ah')),
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
              style: TextStyle(fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
