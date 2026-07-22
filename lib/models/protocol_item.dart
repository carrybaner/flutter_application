/// 协议项 — 对应协议列表中每一行
///
/// show=false 的是 header 行，包含 Code/RegisterCode/RegisterAddress 用于构建命令
/// show=true  的是数据字段行，定义每个字段的解析规则
class ProtocolItem {
  final bool show;
  final String? nameEnglish;
  final String? nameChinese;
  final String? code;           // 功能码（仅header），如 "0x03"
  final String? registerCode;   // 寄存器编码（仅header），如 "0x01"
  final String? registerAddress;// 寄存器起始地址（仅header），如 "0x0000"
  final String? unit;
  final String? dataType;       // long|short|unsigned long|unsigned short|unsigned char|ushort Temper|HEX|2HEX|Time
  final int length;             // 字段字节数
  final String operation;       // * / + -
  final double ratio;           // 运算系数
  final String type;            // r | rw
  final bool bitTag;
  final String? bitDesc;        // 位描述，| 分隔
  final String? configType;         // Register | Data Memery | Calendar
  final String? configNameEnglish;  // 组名 — ConfigName_English（如 "BatteryInfo"）
  final String? configNameChinese;  // 组名中文 — ConfigName_Chinase（如 "电池信息"）
  final String? images;
  final bool graph;

  const ProtocolItem({
    required this.show,
    this.nameEnglish,
    this.nameChinese,
    this.code,
    this.registerCode,
    this.registerAddress,
    this.unit,
    this.dataType,
    required this.length,
    this.operation = '*',
    this.ratio = 1.0,
    this.type = 'r',
    this.bitTag = false,
    this.bitDesc,
    this.configType,
    this.configNameEnglish,
    this.configNameChinese,
    this.images,
    this.graph = false,
  });

  factory ProtocolItem.fromJson(Map<String, dynamic> json) {
    // 兼容 camelCase 和 PascalCase key (含下划线格式如 Name_English)
    String? j(String camel, String pascal) =>
        (json[camel] ?? json[pascal]) as String?;

    bool toBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      return v == 'TRUE' || v == 'true';
    }

    return ProtocolItem(
      show: toBool(json['show'] ?? json['Show']),
      nameEnglish: j('nameEnglish', 'Name_English'),
      nameChinese: j('nameChinese', 'Name_Chinase'),
      code: j('code', 'Code'),
      registerCode: j('registerCode', 'RegisterCode'),
      registerAddress: j('registerAddress', 'RegisterAddress'),
      unit: j('unit', 'Unit'),
      dataType: j('dataType', 'DataType'),
      length: _numVal(json['length'] ?? json['Length']),
      operation: j('operation', 'Operation') ?? '*',
      ratio: () {
          final v = json['ratio'] ?? json['Ratio'];
          if (v is num) return v.toDouble();
          return double.tryParse(v?.toString() ?? '') ?? 1.0;
        }(),
      type: j('type', 'Type') ?? 'r',
      bitTag: toBool(json['bitTag'] ?? json['BitTag']),
      bitDesc: j('bitDesc', 'BitDesc'),
      configType: j('configType', 'ConfigType'),
      configNameEnglish: j('configNameEnglish', 'ConfigName_English'),
      configNameChinese: j('configNameChinese', 'ConfigName_Chinase'),
      images: j('images', 'Images'),
      graph: toBool(json['graph'] ?? json['Graph']),
    );
  }

  static int _numVal(dynamic v) => v is num ? v.toInt() : 0;

  Map<String, dynamic> toJson() => {
        'show': show,
        if (nameEnglish != null) 'nameEnglish': nameEnglish,
        if (nameChinese != null) 'nameChinese': nameChinese,
        if (code != null) 'code': code,
        if (registerCode != null) 'registerCode': registerCode,
        if (registerAddress != null) 'registerAddress': registerAddress,
        if (unit != null) 'unit': unit,
        if (dataType != null) 'dataType': dataType,
        'length': length,
        'operation': operation,
        'ratio': ratio,
        'type': type,
        'bitTag': bitTag,
        if (bitDesc != null) 'bitDesc': bitDesc,
        if (configType != null) 'configType': configType,
        if (images != null) 'images': images,
        'graph': graph,
      };
}

/// 协议组 = 1个header行 + N个数据字段行
///
/// 一个协议组对应一条蓝牙读/写命令
class ProtocolGroup {
  final String groupCode;
  final String chineseName;
  final String configType;
  final List<ProtocolItem> items;

  const ProtocolGroup({
    required this.groupCode,
    required this.chineseName,
    required this.configType,
    required this.items,
  });

  /// header 行（show=false 且 code 非空）
  ProtocolItem get header {
    for (final i in items) {
      if (!i.show && i.code != null && i.code!.isNotEmpty) return i;
    }
    return items.first;
  }

  /// 数据字段行（show=true）
  List<ProtocolItem> get fields => items.where((i) => i.show).toList();

  factory ProtocolGroup.fromJson(Map<String, dynamic> json) {
    return ProtocolGroup(
      groupCode: json['groupCode'] as String,
      chineseName: json['chineseName'] as String? ?? '',
      configType: json['configType'] as String? ?? 'Register',
      items: (json['items'] as List<dynamic>)
          .map((e) => ProtocolItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'groupCode': groupCode,
        'chineseName': chineseName,
        'configType': configType,
        'items': items.map((e) => e.toJson()).toList(),
      };
}
