import 'dart:math';

/// BMS 电池详细数据（从设备读取）
class BmsData {
  final DateTime bmsTime;
  final int soc;
  final double voltage;
  final double current; // + = 充电, - = 放电
  final double power;
  final int cycleCount;
  final int batteryHealth; // 0-100%
  final double remainingCapacity; // Ah
  final double fullChargeCapacity; // Ah
  final int remainingTimeMinutes;
  final List<double> cellVoltages; // 24 节单体
  final List<double> temperatures; // 4 个探头
  final int swProtectionFlags;
  final int hwProtectionFlags;
  final int alarmFlags;

  const BmsData({
    required this.bmsTime,
    required this.soc,
    required this.voltage,
    required this.current,
    required this.power,
    required this.cycleCount,
    required this.batteryHealth,
    required this.remainingCapacity,
    required this.fullChargeCapacity,
    required this.remainingTimeMinutes,
    required this.cellVoltages,
    required this.temperatures,
    required this.swProtectionFlags,
    required this.hwProtectionFlags,
    required this.alarmFlags,
  });

  /// 计算属性
  bool get isCharging => current > 0;
  String get chargeStatus => isCharging ? '充电中' : '放电中';
  String get remainingTimeLabel => isCharging ? '充满' : '放空';

  double get cellMaxVoltage =>
      cellVoltages.isEmpty ? 0 : cellVoltages.reduce(max);
  double get cellMinVoltage =>
      cellVoltages.isEmpty ? 0 : cellVoltages.reduce(min);
  double get cellDeltaVoltage => cellMaxVoltage - cellMinVoltage;

  double get tempMax =>
      temperatures.isEmpty ? 0 : temperatures.reduce(max);
  double get tempMin =>
      temperatures.isEmpty ? 0 : temperatures.reduce(min);

  /// 空/缺省实例
  static final empty = BmsData(
    bmsTime: DateTime(2000),
    soc: 0,
    voltage: 0,
    current: 0,
    power: 0,
    cycleCount: 0,
    batteryHealth: 0,
    remainingCapacity: 0,
    fullChargeCapacity: 0,
    remainingTimeMinutes: 0,
    cellVoltages: [],
    temperatures: [],
    swProtectionFlags: 0,
    hwProtectionFlags: 0,
    alarmFlags: 0,
  );
}
