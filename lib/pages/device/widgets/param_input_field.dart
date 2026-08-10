import 'package:flutter/material.dart';
import '../../../models/param_group.dart';

/// 参数输入字段
///
/// Label + TextField + Unit，失焦时触发 onChanged 回调
class ParamInputField extends StatefulWidget {
  final ParamItem param;
  final void Function(double oldValue, double newValue)? onChanged;

  const ParamInputField({
    super.key,
    required this.param,
    this.onChanged,
  });

  @override
  State<ParamInputField> createState() => _ParamInputFieldState();
}

class _ParamInputFieldState extends State<ParamInputField> {
  late TextEditingController _ctrl;
  late FocusNode _focusNode;
  double _lastValue = 0;

  String get _displayText {
    if (widget.param.displayText != null) return widget.param.displayText!;
    final v = widget.param.currentValue;
    // 浮点精度容差，去掉 -20.00000000000003 这类尾数
    final rounded = v.roundToDouble();
    if ((v - rounded).abs() < 1e-9) return rounded.toInt().toString();
    // 去掉常见浮点尾数
    return v.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  void initState() {
    super.initState();
    _lastValue = widget.param.currentValue;
    _ctrl = TextEditingController(text: _displayText);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(ParamInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.param.currentValue != oldWidget.param.currentValue ||
        widget.param.displayText != oldWidget.param.displayText) {
      _lastValue = widget.param.currentValue;
      _ctrl.text = _displayText;
    }
  }

  void _checkAndNotify() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    double? newVal = double.tryParse(text);
    newVal ??= int.tryParse(text.replaceFirst('0x', ''), radix: 16)?.toDouble();
    newVal ??= int.tryParse(text)?.toDouble();
    if (newVal != null && newVal != _lastValue) {
      widget.onChanged?.call(_lastValue, newVal);
      _ctrl.text = _displayText;
    } else if (newVal == null) {
      _ctrl.text = _displayText;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _checkAndNotify();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.param;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // 参数名
          SizedBox(
            width: 80,
            child: Text(
              p.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),

          // 输入框
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _ctrl,
                focusNode: _focusNode,
                readOnly: p.readOnly,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true, signed: true),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.readOnly ? Colors.grey : null),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  isDense: true,
                ),
                onEditingComplete: () {
                  _focusNode.unfocus();
                  _checkAndNotify();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 单位
          SizedBox(
            width: 50,
            child: Text(
              p.unit,
              style: TextStyle(fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
