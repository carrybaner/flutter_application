import '../models/protocol_item.dart';
import '../utils/crc16_utils.dart';
import 'data_type_converter.dart';

/// 命令构建器 — 完全对齐参考项目 bluetooth-utils.js
///
/// 帧格式: 标识码(1B) + 功能码(1B) + 寄存器地址(2B) + 数据长度(2B) + [数据(N)] + CRC(2B)
class CommandBuilder {
  CommandBuilder._();

  static const _flagNum = '00';
  static const _writeFuncFlag = '10';

  // ============================================================
  // 读命令
  // ============================================================

  /// 构建读命令
  /// 帧: 00 + Code(1B) + Address(2B) + Length(2B) + CRC(2B)
  /// Address = (RegisterCode << 10) | RegisterAddress
  static String buildReadCommand(ProtocolGroup group) {
    final header = group.header;

    final code = int.parse(_stripHex(header.code!), radix: 16)
        .toRadixString(16)
        .padLeft(2, '0');

    final regCode = int.parse(_stripHex(header.registerCode!), radix: 16);
    final regAddr = int.parse(_stripHex(header.registerAddress!), radix: 16);
    final address = ((regCode << 10) | regAddr)
        .toRadixString(16)
        .padLeft(4, '0');

    final length =
        header.length.toRadixString(16).padLeft(4, '0');

    final cmd = '$_flagNum$code$address$length';
    final crc = Crc16Utils.calculate(cmd);
    return cmd + crc;
  }

  /// 构建异常记录读命令（共 64 条）
  /// 每条命令的寄存器地址高 6 位 = recordIndex (0~63)
  static List<String> buildReadErrorRecordCommands(ProtocolGroup group) {
    final header = group.header;
    final commands = <String>[];

    for (int i = 0; i < 64; i++) {
      final code = int.parse(_stripHex(header.code!), radix: 16)
          .toRadixString(16)
          .padLeft(2, '0');

      final height6 = i.toRadixString(2).padLeft(6, '0');
      final low4 = int.parse(_stripHex(header.registerAddress!), radix: 16)
          .toRadixString(2)
          .padLeft(4, '0');
      final address =
          int.parse(height6 + low4, radix: 2).toRadixString(16).padLeft(4, '0');

      final length =
          header.length.toRadixString(16).padLeft(4, '0');

      final cmd = '$_flagNum$code$address$length';
      final crc = Crc16Utils.calculate(cmd);
      commands.add(cmd + crc);
    }
    return commands;
  }

  // ============================================================
  // 写命令
  // ============================================================

  /// 构建写命令
  /// [fieldIndex] — 要修改的字段在 group.fields 中的索引（0-based）
  /// [newValue]   — 用户输入的新值
  /// [pairedValue] — Length=1 时的配对字段当前值
  static String buildWriteCommand(
    ProtocolGroup group,
    int fieldIndex,
    dynamic newValue, {
    dynamic pairedValue,
  }) {
    final header = group.header;
    final fields = group.fields;
    final valueItem = fields[fieldIndex];

    // ===== Length=1 配对处理 =====
    if (valueItem.length == 1 &&
        pairedValue != null &&
        pairedValue != '') {
      return _buildPairedWriteCommand(
          header, fields, fieldIndex, newValue, pairedValue);
    }

    // ===== 正常 Length >= 2 流程 =====

    // 计算目标寄存器地址
    double regAddr = int.parse(_stripHex(header.registerAddress!), radix: 16)
        .toDouble();
    for (int i = 0; i < fieldIndex; i++) {
      regAddr += fields[i].length / 2.0;
    }
    final regAddress = regAddr.round();
    final regAddrHex = regAddress.toUnsigned(16).toRadixString(16);

    final height6 = int.parse(_stripHex(header.registerCode!), radix: 16)
        .toRadixString(2)
        .padLeft(6, '0');
    final low10 = int.parse(regAddrHex, radix: 16)
        .toRadixString(2)
        .padLeft(10, '0');
    final addrHex =
        int.parse(height6 + low10, radix: 2).toRadixString(16).padLeft(4, '0');

    // 反向转换管线
    var data = DataTypeConverter.handleReverseOperation(
        (newValue is num) ? newValue : double.parse(newValue.toString()),
        valueItem.dataType,
        valueItem.operation,
        valueItem.ratio);
    data = DataTypeConverter.handleReverseTemperature(data, valueItem.dataType);
    var dataHex = DataTypeConverter.handleReverseDataType(
        data, valueItem.dataType, valueItem.length, valueItem.bitDesc);
    dataHex = dataHex.padLeft(valueItem.length * 2, '0');
    dataHex = DataTypeConverter.littleEndian(dataHex);
    dataHex = DataTypeConverter.twoExchange(dataHex);

    // 组装帧
    final regCount =
        (valueItem.length ~/ 2).toRadixString(16).padLeft(4, '0');
    final cmd = '$_flagNum$_writeFuncFlag$addrHex$regCount$dataHex';
    final crc = Crc16Utils.calculate(cmd);
    return cmd + crc;
  }

  /// Length=1 配对写入
  static String _buildPairedWriteCommand(
    ProtocolItem header,
    List<ProtocolItem> fields,
    int fieldIndex,
    dynamic newValue,
    dynamic pairedValue,
  ) {
    final pairIndex = (fieldIndex % 2 == 0) ? fieldIndex + 1 : fieldIndex - 1;
    final evenIndex = fieldIndex < pairIndex ? fieldIndex : pairIndex;
    final oddIndex = fieldIndex < pairIndex ? pairIndex : fieldIndex;

    final evenField = fields[evenIndex];
    final oddField = fields[oddIndex];

    dynamic evenVal, oddVal;
    if (fieldIndex == evenIndex) {
      evenVal = newValue;
      oddVal = pairedValue;
    } else {
      evenVal = pairedValue;
      oddVal = newValue;
    }

    // 两个字段各自走反向转换管线
    var eHex = _reverseConvertField(evenVal, evenField);
    var oHex = _reverseConvertField(oddVal, oddField);

    eHex = eHex.padLeft(evenField.length * 2, '0');
    oHex = oHex.padLeft(oddField.length * 2, '0');

    // 合并: 高字节(odd) + 低字节(even) → littleEndian → twoExchange
    var combined = oHex + eHex;
    combined = DataTypeConverter.littleEndian(combined);
    combined = DataTypeConverter.twoExchange(combined);

    // 地址对齐到偶数位（Length=1 字段 0.5 寄存器，累积后取整）
    double regAddr = int.parse(_stripHex(header.registerAddress!), radix: 16)
        .toDouble();
    for (int i = 0; i < evenIndex; i++) {
      regAddr += fields[i].length / 2.0;
    }
    final regAddress = regAddr.round();

    final height6 = int.parse(_stripHex(header.registerCode!), radix: 16)
        .toRadixString(2)
        .padLeft(6, '0');
    final low10Bin = int.parse(
            regAddress.toUnsigned(16).toRadixString(16).padLeft(4, '0'),
            radix: 16)
        .toRadixString(2)
        .padLeft(10, '0');
    final addrHex = int.parse(height6 + low10Bin, radix: 2)
        .toRadixString(16)
        .padLeft(4, '0');

    final cmd = '$_flagNum$_writeFuncFlag$addrHex${'0001'}$combined';
    final crc = Crc16Utils.calculate(cmd);
    return cmd + crc;
  }

  /// 单字段反向转换管线
  static String _reverseConvertField(dynamic value, ProtocolItem field) {
    num numVal;
    if (value is num) {
      numVal = value;
    } else {
      final s = value.toString();
      if (s.startsWith('0x')) {
        numVal = int.parse(s.substring(2), radix: 16);
      } else {
        numVal = double.parse(s);
      }
    }
    var data = DataTypeConverter.handleReverseOperation(
        numVal, field.dataType, field.operation, field.ratio);
    data = DataTypeConverter.handleReverseTemperature(data, field.dataType);
    return DataTypeConverter.handleReverseDataType(
        data, field.dataType, field.length, field.bitDesc);
  }

  // ============================================================
  // 扩展指令（固定命令）
  // ============================================================

  /// 充电开关
  static String buildChargeSwitch(bool enable) =>
      _buildExtensionCommand(enable ? '0020' : '0020');
  // 注: 充电开关切换固定命令，每次都发同样的toggle指令
  static String buildChargeToggleCommand() =>
      _buildExtensionCommand('0020');

  /// 放电开关
  static String buildDischargeToggleCommand() =>
      _buildExtensionCommand('0021');

  /// 同步时间
  static String buildTimeSyncCommand() {
    final now = DateTime.now();
    final minute = now.minute.toRadixString(16).padLeft(2, '0');
    final second = now.second.toRadixString(16).padLeft(2, '0');
    final day = now.day.toRadixString(16).padLeft(2, '0');
    final hour12 = (now.hour > 12 ? now.hour - 12 : now.hour)
        .toRadixString(16)
        .padLeft(2, '0');
    final year = (now.year - 2000).toRadixString(16).padLeft(2, '0');
    final month = now.month.toRadixString(16).padLeft(2, '0');

    var cmd = '0010C0000003$minute$second$day$hour12$year$month';
    cmd = cmd.toUpperCase();
    final crc = Crc16Utils.calculate(cmd);
    return cmd + crc;
  }

  /// 重启 BMS
  static String buildRestartBmsCommand() =>
      _buildExtensionCommand('0041');

  /// 校准零点偏移
  static String buildCalibrateZeroCommand() =>
      _buildExtensionCommand('0022');

  /// 保存校准参数
  static String buildSaveCalibrationCommand() =>
      _buildExtensionCommand('0026');

  /// 校准电流
  static String buildCalibrateCurrentCommand(double actualCurrentA) {
    return _buildCalibrationCommand('0024', actualCurrentA * 1000);
  }

  /// 校准电压
  static String buildCalibrateVoltageCommand(double actualVoltageV) {
    return _buildCalibrationCommand('0025', actualVoltageV * 1000);
  }

  /// 通用扩展指令: 0010FC000001 + subCmd + CRC
  static String _buildExtensionCommand(String subCmd) {
    final cmd = '0010FC000001$subCmd';
    final crc = Crc16Utils.calculate(cmd);
    return cmd + crc;
  }

  /// 校准指令: 0010FC000003 + subCmd + value(4B)
  static String _buildCalibrationCommand(String subCmd, num rawValue) {
    String valueHex;
    if (rawValue >= 0) {
      valueHex = rawValue
          .round()
          .toUnsigned(32)
          .toRadixString(16)
          .padLeft(8, '0');
    } else {
      // 负数：取反码
      valueHex = (~rawValue.abs().round())
          .toUnsigned(32)
          .toRadixString(16)
          .padLeft(8, '0');
    }
    valueHex = DataTypeConverter.twoExchange(
        DataTypeConverter.littleEndian(valueHex));

    final cmd = '0010FC000003$subCmd$valueHex';
    final crc = Crc16Utils.calculate(cmd);
    return cmd + crc;
  }

  // ============================================================
  // 辅助
  // ============================================================

  static String _stripHex(String s) {
    return s.replaceFirst('0x', '').replaceFirst('0X', '');
  }
}
