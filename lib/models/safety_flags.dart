import 'package:flutter/material.dart';

/// 单个安全标志定义
class SafetyFlag {
  final int bit;
  final String label;
  final bool isCritical; // true=红色告警, false=黄色报警

  const SafetyFlag({
    required this.bit,
    required this.label,
    this.isCritical = false,
  });
}

/// 安全标志位定义（16 bits，按协议 BitDesc）
///
/// BitDesc: CUV|OCD|SCD|DSG_OT|RCA|DSG_UT|REVC|REVC|
///           COV|OCC|CHG_OT|CHG_UT|MOS_OT|REVC|P_DSG|ALERT
class SafetyFlags {
  SafetyFlags._();

  /// 软件保护 / 告警位定义
  /// 顺序与 parseBitDescription 反转后的 bitDesc 对齐
  /// bitDesc: ALERT|P_DSG|REVC|MOS_OT|CHG_UT|CHG_OT|OCC|COV|REVC|REVC|DSG_UT|RCA|DSG_OT|SCD|OCD|CUV
  static const _flags = [
    SafetyFlag(bit: 0, label: 'ALERT'),
    SafetyFlag(bit: 1, label: 'P_DSG'),
    SafetyFlag(bit: 2, label: 'REVC'),
    SafetyFlag(bit: 3, label: 'MOS_OT'),
    SafetyFlag(bit: 4, label: '充电低温'),           // CHG_UT
    SafetyFlag(bit: 5, label: '充电过温', isCritical: true),  // CHG_OT
    SafetyFlag(bit: 6, label: '充电过流', isCritical: true),  // OCC
    SafetyFlag(bit: 7, label: '单体过压', isCritical: true),  // COV
    SafetyFlag(bit: 8, label: 'REVC'),
    SafetyFlag(bit: 9, label: 'REVC'),
    SafetyFlag(bit: 10, label: '放电低温'),          // DSG_UT
    SafetyFlag(bit: 11, label: '剩余容量保护'),      // RCA
    SafetyFlag(bit: 12, label: '放电过温', isCritical: true), // DSG_OT
    SafetyFlag(bit: 13, label: '电池短路', isCritical: true), // SCD
    SafetyFlag(bit: 14, label: '放电过流', isCritical: true), // OCD
    SafetyFlag(bit: 15, label: '单体欠压', isCritical: true), // CUV
  ];

  /// 硬件保护 AFE Safety 16bit（反转后与 parseBitDescription 对齐）
  /// 协议 bitDesc: COV|SCD|UV|OCC1|OCC2|ODC1|ODC2|UTD|OTD|UTC|OTC|LV0|DIS_PF|WDT|ALARM|REVC
  static const _afeFlags = [
    SafetyFlag(bit: 0, label: 'REVC'),
    SafetyFlag(bit: 1, label: 'ALARM'),
    SafetyFlag(bit: 2, label: 'WDT'),
    SafetyFlag(bit: 3, label: 'DIS_PF'),
    SafetyFlag(bit: 4, label: 'LV0'),
    SafetyFlag(bit: 5, label: '充电高温', isCritical: true),
    SafetyFlag(bit: 6, label: '充电低温'),
    SafetyFlag(bit: 7, label: '放电高温', isCritical: true),
    SafetyFlag(bit: 8, label: '放电低温'),
    SafetyFlag(bit: 9, label: '放电过流', isCritical: true),
    SafetyFlag(bit: 10, label: '放电过流', isCritical: true),
    SafetyFlag(bit: 11, label: 'OCC2'),
    SafetyFlag(bit: 12, label: '充电过流', isCritical: true),
    SafetyFlag(bit: 13, label: '欠压', isCritical: true),
    SafetyFlag(bit: 14, label: '短路', isCritical: true),
    SafetyFlag(bit: 15, label: '过压', isCritical: true),
  ];

  /// 广播原始值位定义（非反转，与寄存器 bit 顺序一致）
  /// CUV|OCD|SCD|DSG_OT|RCA|DSG_UT|REVC|REVC|COV|OCC|CHG_OT|CHG_UT|MOS_OT|REVC|P_DSG|ALERT
  static const _rawFlags = [
    SafetyFlag(bit: 0, label: '单体欠压', isCritical: true),
    SafetyFlag(bit: 1, label: '放电过流', isCritical: true),
    SafetyFlag(bit: 2, label: '电池短路', isCritical: true),
    SafetyFlag(bit: 3, label: '放电过温', isCritical: true),
    SafetyFlag(bit: 4, label: '剩余容量保护'),
    SafetyFlag(bit: 5, label: '放电低温'),
    SafetyFlag(bit: 6, label: 'REVC'),
    SafetyFlag(bit: 7, label: 'REVC'),
    SafetyFlag(bit: 8, label: '单体过压', isCritical: true),
    SafetyFlag(bit: 9, label: '充电过流', isCritical: true),
    SafetyFlag(bit: 10, label: '充电过温', isCritical: true),
    SafetyFlag(bit: 11, label: '充电低温'),
    SafetyFlag(bit: 12, label: 'MOS_OT'),
    SafetyFlag(bit: 13, label: 'REVC'),
    SafetyFlag(bit: 14, label: 'P_DSG'),
    SafetyFlag(bit: 15, label: 'ALERT'),
  ];

  /// 软件保护 / 告警 位解析（BatterySafety / BatteryAlarm，已反转）
  static List<SafetyFlag> parse(int flags) {
    return _flags.where((f) => (flags >> f.bit) & 1 == 1).toList();
  }

  /// 广播原始值位解析（非反转，直接对应寄存器 bit）
  static List<SafetyFlag> parseRaw(int flags) {
    return _rawFlags.where((f) => (flags >> f.bit) & 1 == 1).toList();
  }

  /// 安全故障位定义（Safety_Fail，反转后与 parseBitDescription 对齐）
  /// 协议 bitDesc: SUV|SOCD|SOT_DSG|SUT_DSG|REVC|REVC|REVC|REVC|SOV|SOCC|SOT_CHG|SUT_CHG|SOT_MOS|ALERT|REVC|REVC
  static const _failFlags = [
    SafetyFlag(bit: 0, label: 'REVC'),
    SafetyFlag(bit: 1, label: 'REVC'),
    SafetyFlag(bit: 2, label: 'ALERT'),
    SafetyFlag(bit: 3, label: '安全过温MOS', isCritical: true),
    SafetyFlag(bit: 4, label: '安全欠温充电'),
    SafetyFlag(bit: 5, label: '安全过温充电', isCritical: true),
    SafetyFlag(bit: 6, label: '安全过流充电', isCritical: true),
    SafetyFlag(bit: 7, label: '安全过压', isCritical: true),
    SafetyFlag(bit: 8, label: 'REVC'),
    SafetyFlag(bit: 9, label: 'REVC'),
    SafetyFlag(bit: 10, label: 'REVC'),
    SafetyFlag(bit: 11, label: 'REVC'),
    SafetyFlag(bit: 12, label: '安全欠温放电'),
    SafetyFlag(bit: 13, label: '安全过温放电', isCritical: true),
    SafetyFlag(bit: 14, label: '安全过流放电', isCritical: true),
    SafetyFlag(bit: 15, label: '安全欠压', isCritical: true),
  ];

  /// 硬件保护位解析（AFE Safety）
  static List<SafetyFlag> parseAfe(int flags) {
    return _afeFlags.where((f) => (flags >> f.bit) & 1 == 1).toList();
  }

  /// 安全故障位解析（Safety_Fail）
  static List<SafetyFlag> parseFail(int flags) {
    return _failFlags.where((f) => (flags >> f.bit) & 1 == 1).toList();
  }

  static Color criticalColor = Colors.red;
  static Color warningColor = Colors.orange;
}
