import 'package:flutter/material.dart';
import '../../../models/param_group.dart';
import '../../../services/feature_guard.dart';

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

  /// 是否已通过授权（可编辑）。未授权时点按输入框先弹密码。
  bool _unlocked = false;

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
    if (newVal == null) {
      _ctrl.text = _displayText;
      return;
    }
    // 浮点噪声容差：设备值经缩放后可能是 218.68000000000001，
    // 与文本框字符串解析出的 218.68 显示相同但按位不等。
    // 直接用 == 会误判为"已修改"而弹出确认框。容差内视为未修改。
    if ((newVal - _lastValue).abs() > 1e-6) {
      widget.onChanged?.call(_lastValue, newVal);
      _ctrl.text = _displayText;
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _checkAndNotify();
  }

  /// 未解锁的输入框：点击先弹授权密码，通过后才可编辑
  Future<void> _handleUnlockTap() async {
    if (widget.param.readOnly || _unlocked) return;
    if (!await FeatureGuard.ensureUnlocked(context)) return;
    if (!mounted) return;
    setState(() => _unlocked = true);
    _focusNode.requestFocus();
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
              child: GestureDetector(
                onTap: _handleUnlockTap,
                child: AbsorbPointer(
                  absorbing: !_unlocked && !p.readOnly,
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
