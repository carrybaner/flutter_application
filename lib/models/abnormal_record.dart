/// 异常记录
class AbnormalRecord {
  final int sequenceNumber;
  final DateTime timestamp;
  final String severity;
  final double current;
  final double maxVoltage;
  final double minVoltage;
  final double mosTemp;
  final double maxTemp;
  final double minTemp;
  final int batterySafety;
  final int afeSafety;
  final int safetyFail;

  const AbnormalRecord({
    required this.sequenceNumber,
    required this.timestamp,
    required this.severity,
    required this.current,
    required this.maxVoltage,
    required this.minVoltage,
    required this.mosTemp,
    required this.maxTemp,
    required this.minTemp,
    this.batterySafety = 0,
    this.afeSafety = 0,
    this.safetyFail = 0,
  });

  /// 从协议解析的 values 列表构造异常记录
  /// 字段顺序: index(0), Time(1), Current(2), BatterySafety(3),
  ///   MAX_Voltage(4), MIN_Voltage(5), MOS_Temper(6), MAX_Temper(7),
  ///   MIN_Temper(8), AFE_Safety(9), Safety_Fail(10)
  factory AbnormalRecord.fromValues(List<dynamic> values) {
    double v(int i, [double def = 0]) =>
        values.length > i && values[i] is num
            ? (values[i] as num).toDouble()
            : def;

    int getInt(int i, [int def = 0]) =>
        values.length > i && values[i] is num
            ? (values[i] as num).toInt()
            : def;

    int getFlags(int i) {
      final val = values.length > i ? values[i] : null;
      if (val is num) return val.toInt();
      if (val is String) {
        // Calendar 组 BitTag=false，返回原始 hex，bit 未反转
        // 需反转为与 parseBitDescription 对齐的顺序
        final raw = int.tryParse(val.replaceFirst('0x', ''), radix: 16) ?? 0;
        int reversed = 0;
        for (int j = 0; j < 16; j++) {
          if ((raw >> j) & 1 == 1) {
            reversed |= (1 << (15 - j));
          }
        }
        return reversed;
      }
      if (val is List) {
        int flags = 0;
        for (int j = 0; j < val.length && j < 16; j++) {
          if (val[j] is Map && (val[j]['value'] as num?)?.toInt() == 1) {
            flags |= (1 << j);
          }
        }
        return flags;
      }
      return 0;
    }

    DateTime ts = DateTime.now();
    if (values.length > 1 && values[1] is String) {
      try {
        final parts = (values[1] as String).replaceAll('/', '-').split(' ');
        ts = DateTime.tryParse('${parts[0]} ${parts[1]}') ?? ts;
      } catch (_) {}
    }

    return AbnormalRecord(
      sequenceNumber: getInt(0),
      timestamp: ts,
      severity: '提示',
      current: v(2),
      maxVoltage: v(4, 0) / 1000.0,
      minVoltage: v(5, 0) / 1000.0,
      mosTemp: v(6),
      maxTemp: v(7),
      minTemp: v(8),
      batterySafety: getFlags(3),
      afeSafety: getFlags(9),
      safetyFail: getFlags(10),
    );
  }
}
