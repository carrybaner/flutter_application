/// 单个参数项
class ParamItem {
  final String name;
  final String unit;
  final double currentValue;
  final double minValue;
  final double maxValue;
  final double step;
  final String? displayText; // 非空时优先显示（HEX/2HEX 类型）

  const ParamItem({
    required this.name,
    required this.unit,
    required this.currentValue,
    this.minValue = 0,
    this.maxValue = 100,
    this.step = 0.01,
    this.displayText,
  });

  ParamItem copyWith({double? currentValue}) {
    return ParamItem(
      name: name,
      unit: unit,
      currentValue: currentValue ?? this.currentValue,
      minValue: minValue,
      maxValue: maxValue,
      step: step,
      displayText: displayText,
    );
  }
}

