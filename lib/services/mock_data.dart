import 'dart:math';
import '../models/device_model.dart';
import '../models/broadcast_data.dart';
import '../models/bms_data.dart';
import '../models/param_group.dart';
import '../models/abnormal_record.dart';

/// Mock 数据生成器 — 开发/演示用
class MockData {
  MockData._();
  static final MockData instance = MockData._();

  final _random = Random(42);

  // ──────── 模拟设备列表 ────────

  List<DeviceModel> generateDevices() {
    return [
      _makeDevice('DCSF-3998260707064', -45),
      _makeDevice('DCSF-A9876543210AB', -62),
      _makeDevice('DCSF-B1234567890CD', -79),
      _makeDevice('DCSF-C5555666677EF', -88),
      _makeDevice('DCSF-D0000111122GH', -93),
    ];
  }

  DeviceModel _makeDevice(String name, int rssi) {
    final soc = _random.nextInt(101);
    return DeviceModel(
      deviceId: 'AA:BB:CC:${name.hashCode.toRadixString(16).padLeft(2, '0').substring(0, 5).toUpperCase()}',
      name: name,
      rssi: rssi,
      advData: BroadcastData(
        protocol: '7030',
        soc: soc,
        voltage: 70 + _random.nextDouble() * 15,
        current: (_random.nextDouble() * 10) * (_random.nextBool() ? 1 : -1),
        safetyFlags: _random.nextInt(0xFFFF),
        isValid: true,
      ),
    );
  }

  // ──────── BMS 详细数据 ────────

  BmsData generateBmsData({int? overrideSoc}) {
    final soc = overrideSoc ?? (40 + _random.nextInt(50));
    final voltage = 65 + _random.nextDouble() * 20; // 65-85V
    final isCharging = _random.nextBool();
    final current = isCharging
        ? _random.nextDouble() * 5 + 0.5 // +0.5~5.5A
        : -(_random.nextDouble() * 8 + 0.2); // -0.2~-8.2A

    final cellBase = voltage / 24.0; // ~3.0-3.5V per cell
    final cells = List.generate(24, (i) {
      final offset = (_random.nextDouble() - 0.5) * 0.15;
      return double.parse((cellBase + offset).toStringAsFixed(3));
    });

    final temps = List.generate(4, (_) {
      return 20 + _random.nextDouble() * 25; // 20-45°C
    });

    return BmsData(
      bmsTime: DateTime.now(),
      soc: soc,
      voltage: double.parse(voltage.toStringAsFixed(3)),
      current: double.parse(current.toStringAsFixed(3)),
      power: double.parse((voltage * current.abs()).toStringAsFixed(0)),
      cycleCount: 100 + _random.nextInt(900),
      batteryHealth: 85 + _random.nextInt(16),
      remainingCapacity: double.parse((40 + _random.nextDouble() * 20).toStringAsFixed(1)),
      fullChargeCapacity: double.parse((55 + _random.nextDouble() * 10).toStringAsFixed(1)),
      remainingTimeMinutes: 30 + _random.nextInt(240),
      cellVoltages: cells,
      temperatures: temps,
      swProtectionFlags: (1 << 0) | (1 << 2) | (1 << 8),  // CUV+SCD+COV
      hwProtectionFlags: (1 << 1) | (1 << 3) | (1 << 12), // OCD+DSG_OT+MOS_OT
      alarmFlags: (1 << 15) | (1 << 4),                     // ALERT+RCA
    );
  }

  // ──────── 参数设置 ────────

  List<ParamGroup> generateParamGroups() {
    return [
      _makeGroup('电压保护', [
        _p('单体过压保护', 'V', 3.65, 3.0, 4.5),
        _p('单体欠压保护', 'V', 2.80, 2.0, 3.5),
        _p('总压过压保护', 'V', 86.0, 60, 100),
        _p('总压欠压保护', 'V', 60.0, 40, 80),
        _p('过压恢复', 'V', 3.55, 3.0, 4.5),
        _p('欠压恢复', 'V', 3.00, 2.0, 3.5),
        _p('单体过压延时', 'ms', 1000, 100, 10000),
        _p('单体欠压延时', 'ms', 1000, 100, 10000),
        _p('总压过压延时', 'ms', 2000, 100, 10000),
        _p('总压欠压延时', 'ms', 2000, 100, 10000),
      ]),
      _makeGroup('电流保护', [
        _p('充电过流保护', 'A', 50.0, 5, 100),
        _p('放电过流保护', 'A', 80.0, 10, 150),
        _p('短路保护', 'A', 200.0, 50, 400),
        _p('充电过流延时', 'ms', 500, 50, 5000),
        _p('放电过流延时', 'ms', 500, 50, 5000),
        _p('短路保护延时', 'us', 200, 50, 1000),
        _p('过流恢复延时', 's', 30, 1, 300),
        _p('充电过流恢复', 'A', 48.0, 5, 100),
        _p('放电过流恢复', 'A', 78.0, 10, 150),
        _p('峰值电流限制', 'A', 120.0, 10, 200),
      ]),
      _makeGroup('温度保护', [
        _p('充电高温保护', '°C', 55.0, 30, 80),
        _p('充电低温保护', '°C', 0.0, -20, 20),
        _p('放电高温保护', '°C', 65.0, 30, 90),
        _p('放电低温保护', '°C', -10.0, -30, 20),
        _p('MOS高温保护', '°C', 85.0, 50, 120),
        _p('高温恢复', '°C', 50.0, 30, 80),
        _p('低温恢复', '°C', 5.0, -20, 20),
        _p('温度保护延时', 's', 5, 1, 60),
        _p('环境温度补偿', '°C', 0.0, -10, 10),
        _p('温升速率限制', '°C/min', 10.0, 1, 30),
      ]),
      _makeGroup('均衡', [
        _p('均衡开启电压', 'V', 3.40, 2.8, 4.2),
        _p('均衡压差阈值', 'mV', 50, 10, 500),
        _p('均衡电流', 'mA', 100, 20, 500),
        _p('均衡时间限制', 'h', 2, 0.5, 24),
        _p('均衡温度上限', '°C', 45, 30, 60),
        _p('静止均衡', '', 1.0, 0, 1),
        _p('充电均衡', '', 1.0, 0, 1),
        _p('放电均衡', '', 1.0, 0, 1),
        _p('均衡间隔', 'h', 24, 1, 168),
        _p('最小均衡SOC', '%', 30, 10, 80),
      ]),
      _makeGroup('容量', [
        _p('设计容量', 'Ah', 60.0, 10, 200),
        _p('满充容量', 'Ah', 58.5, 10, 200),
        _p('剩余容量', 'Ah', 45.2, 0, 200),
        _p('SOC满充点', '%', 100, 80, 100),
        _p('SOC放空点', '%', 0, 0, 20),
        _p('容量衰减系数', '%/年', 2.0, 0, 10),
        _p('容量学习次数', '', 5.0, 1, 50),
        _p('容量学习间隔', '天', 30, 7, 365),
        _p('初始容量补偿', '%', 0.0, -20, 20),
        _p('温度容量补偿', '%/°C', 0.5, 0, 5),
      ]),
      _makeGroup('充电', [
        _p('充电最大电压', 'V', 86.0, 60, 100),
        _p('充电最大电流', 'A', 15.0, 1, 50),
        _p('浮充电压', 'V', 82.0, 60, 90),
        _p('充电超时保护', 'h', 12, 1, 48),
        _p('预充电电压', 'V', 60.0, 40, 70),
        _p('预充电电流', 'A', 2.0, 0.5, 10),
        _p('充电CC到CV切换', '%', 90, 50, 100),
        _p('涓流充电电流', 'A', 0.5, 0.1, 5),
        _p('充电恢复电压', 'V', 80.0, 60, 90),
        _p('最大充电功率', 'W', 1200, 100, 5000),
      ]),
      _makeGroup('放电', [
        _p('放电最低电压', 'V', 60.0, 40, 80),
        _p('放电最大电流', 'A', 80.0, 10, 200),
        _p('放电超时保护', 'h', 24, 1, 72),
        _p('放电功率限制', 'W', 5000, 500, 15000),
        _p('低SOC告警', '%', 20, 5, 50),
        _p('极低SOC保护', '%', 5, 0, 20),
        _p('放电恢复电压', 'V', 65.0, 40, 80),
        _p('峰值放电电流', 'A', 120.0, 10, 300),
        _p('峰值放电时间', 's', 30, 1, 120),
        _p('放电温度补偿', 'mV/°C', -3.0, -20, 0),
      ]),
      _makeGroup('系统', [
        _p('设备地址', '', 1.0, 1, 255),
        _p('波特率', 'bps', 9600, 2400, 115200),
        _p('休眠时间', 'min', 30, 1, 240),
        _p('低功耗SOC阈值', '%', 10, 0, 50),
        _p('看门狗超时', 's', 60, 10, 600),
        _p('数据记录间隔', 's', 10, 1, 3600),
        _p('屏幕亮度', '%', 80, 10, 100),
        _p('蜂鸣器', '', 1.0, 0, 1),
        _p('LED指示', '', 1.0, 0, 1),
        _p('恢复出厂设置', '', 0.0, 0, 1),
      ]),
    ];
  }

  ParamGroup _makeGroup(String category, List<ParamItem> params) {
    return ParamGroup(categoryName: category, parameters: params);
  }

  ParamItem _p(String name, String unit, double value, double min, double max) {
    return ParamItem(
      name: name,
      unit: unit,
      currentValue: value,
      minValue: min,
      maxValue: max,
    );
  }

  // ──────── 异常记录 ────────

  List<AbnormalRecord> generateRecords() {
    final now = DateTime.now();
    return [
      _record(1, now.subtract(const Duration(minutes: 5)), '严重', 125.3, 4.25, 2.80, 85.0, 92.0, 25.0),
      _record(2, now.subtract(const Duration(hours: 1)), '警告', 55.2, 3.89, 3.21, 62.0, 68.0, 30.0),
      _record(3, now.subtract(const Duration(hours: 3)), '严重', 180.5, 4.05, 3.15, 95.0, 102.0, 28.0),
      _record(4, now.subtract(const Duration(hours: 6)), '提示', 30.1, 3.72, 3.45, 45.0, 50.0, 32.0),
      _record(5, now.subtract(const Duration(hours: 12)), '警告', 65.8, 3.95, 3.10, 70.0, 75.0, 26.0),
      _record(6, now.subtract(const Duration(days: 1)), '严重', 200.0, 4.30, 2.65, 105.0, 110.0, 22.0),
      _record(7, now.subtract(const Duration(days: 1, hours: 5)), '提示', 20.5, 3.68, 3.50, 38.0, 42.0, 33.0),
      _record(8, now.subtract(const Duration(days: 2)), '警告', 58.0, 3.88, 3.18, 68.0, 72.0, 27.0),
    ];
  }

  AbnormalRecord _record(
    int seq, DateTime time, String severity,
    double current, double maxV, double minV,
    double mosTemp, double maxTemp, double minTemp,
  ) {
    return AbnormalRecord(
      sequenceNumber: seq,
      timestamp: time,
      severity: severity,
      current: current,
      maxVoltage: maxV,
      minVoltage: minV,
      mosTemp: mosTemp,
      maxTemp: maxTemp,
      minTemp: minTemp,
    );
  }
}
