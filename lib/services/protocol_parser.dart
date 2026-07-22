import '../models/protocol_item.dart';
import 'data_type_converter.dart';

/// 协议解析器 — 完全对齐参考项目 bluetooth-utils.js parseProtocol
///
/// 响应帧: flag(2hex) + funcCode(2hex) + dataLen(2hex) + data(N) + CRC(4hex)
class ProtocolParser {
  ProtocolParser._();

  /// 解析 hex 响应 → List<dynamic>（与 group.fields 一一对应）
  static List<dynamic>? parseToList(ProtocolGroup group, String hexStr) {
    try {
      hexStr = DataTypeConverter.cleanHexStr(hexStr);

      // CRC 校验
      if (!DataTypeConverter.verifyCRC(hexStr)) return null;

      final fields = group.fields;

      // 长度校验: header.Length 是寄存器数，响应长度字段是数据字节数
      final respDataLen = int.parse(hexStr.substring(4, 6), radix: 16);
      final expectedByteLen = group.header.length * 2;
      // 截取数据段: 跳过 flag(2) + funcCode(2) + len(2)，截掉 CRC(4)
      final dataStr = hexStr.substring(6, hexStr.length - 4);
      // 两两交换
      final exchangedStr = DataTypeConverter.twoExchange(dataStr);

      // 逐字段解析
      final valueList = <dynamic>[];
      int index = 0;
      for (int i = 0; i < fields.length; i++) {
        final field = fields[i];
        final segLen = field.length * 2;
        if (index + segLen > exchangedStr.length) {
          return null;
        }
        final seg = exchangedStr.substring(index, index + segLen);
        index += segLen;

        dynamic d = DataTypeConverter.littleEndian(seg);
        d = DataTypeConverter.handleDataType(d, field.dataType, field.bitDesc);
        d = DataTypeConverter.handleTemperature(d, field.dataType);
        d = DataTypeConverter.handleOperation(
            d, field.dataType, field.operation, field.ratio);
        valueList.add(d);
      }

      return valueList;
    } catch (e) {
      return null;
    }
  }

  /// 解析 hex 响应 → Map<String, dynamic>（nameEnglish → value）
  static Map<String, dynamic>? parseToMap(
      ProtocolGroup group, String hexStr) {
    final list = parseToList(group, hexStr);
    if (list == null) return null;

    final fields = group.fields;
    final map = <String, dynamic>{};
    for (int i = 0; i < fields.length; i++) {
      if (fields[i].nameEnglish != null && fields[i].nameEnglish!.isNotEmpty) {
        map[fields[i].nameEnglish!] = list[i];
      }
    }
    return map;
  }

  /// 从取型号响应中提取协议 ID
  ///
  /// 响应: flag(2) + funcCode(2) + len(2) + protocolId(4) + CRC(4)
  /// 正常: funcCode == 0x03 → 提取 data 段前 4 位 hex
  /// 错误: funcCode 高位为 1（如 0x83）→ 设备未就绪
  static String? extractProtocolId(String hexStr) {
    try {
      hexStr = DataTypeConverter.cleanHexStr(hexStr);
      if (hexStr.length < 10) return null;

      // CRC 校验
      if (!DataTypeConverter.verifyCRC(hexStr)) return null;

      // 功能码（第 2 字节 = hexStr[2:4]）
      final funcCode = int.parse(hexStr.substring(2, 4), radix: 16);
      // 高位为1 → 错误响应
      if (funcCode & 0x80 != 0) return null;
      // 不是 0x03 响应 → 忽略
      if (funcCode != 0x03) return null;

      // 提取协议 ID: data段前4位（跳过 flag+funcCode+len = 6chars）
      final dataPart = hexStr.substring(6, hexStr.length - 4);
      if (dataPart.length < 4) return null;
      return dataPart.substring(0, 4).toUpperCase();
    } catch (_) {
      return null;
    }
  }
}
