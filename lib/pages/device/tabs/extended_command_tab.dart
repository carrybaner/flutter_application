import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/device_data_provider.dart';
import '../../../services/command_builder.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirmation_dialog.dart';
import '../widgets/switch_toggle_card.dart';

/// 扩展指令 Tab — 使用 CommandBuilder 下发固定扩展指令
class ExtendedCommandTab extends ConsumerStatefulWidget {
  const ExtendedCommandTab({super.key});

  @override
  ConsumerState<ExtendedCommandTab> createState() =>
      _ExtendedCommandTabState();
}

class _ExtendedCommandTabState extends ConsumerState<ExtendedCommandTab> {
  bool _chargeEnabled = true;
  bool _dischargeEnabled = true;

  final _currentCalCtrl = TextEditingController();
  final _voltageCalCtrl = TextEditingController();

  @override
  void dispose() {
    _currentCalCtrl.dispose();
    _voltageCalCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCommand(String cmd, String successMsg) async {
    final poller = ref.read(realtimePollerProvider);
    if (poller == null) {
      _showSnackBar('蓝牙未连接');
      return;
    }

    try {
      await poller.sendAndWaitResponse(cmd);
      _showSnackBar(successMsg);
    } catch (_) {
      _showSnackBar('指令发送失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 充/放电开关
          _sectionTitle('控制开关'),
          const SizedBox(height: 8),
          SwitchToggleCard(
            label: '充电开关',
            subtitle: '控制电池充电功能',
            icon: Icons.power,
            value: _chargeEnabled,
            onChanged: (v) {
              setState(() => _chargeEnabled = v);
              _sendCommand(
                CommandBuilder.buildChargeToggleCommand(),
                '充电开关指令已发送',
              );
            },
          ),
          const SizedBox(height: 8),
          SwitchToggleCard(
            label: '放电开关',
            subtitle: '控制电池放电功能',
            icon: Icons.power_off,
            value: _dischargeEnabled,
            onChanged: (v) {
              setState(() => _dischargeEnabled = v);
              _sendCommand(
                CommandBuilder.buildDischargeToggleCommand(),
                '放电开关指令已发送',
              );
            },
          ),
          const SizedBox(height: 24),

          // 系统指令
          _sectionTitle('系统指令'),
          const SizedBox(height: 8),
          _commandTile(
            icon: Icons.access_time,
            title: '同步时间',
            subtitle: '将BMS时钟同步为手机时间',
            onTap: () => _showConfirm('同步时间', '确定要将BMS时钟同步为手机时间吗？', () {
              _sendCommand(
                CommandBuilder.buildTimeSyncCommand(),
                '时间同步成功',
              );
            }),
          ),
          _commandTile(
            icon: Icons.restart_alt,
            iconColor: AppColors.dangerRed,
            title: '重启 BMS',
            subtitle: '危险操作，重启电池管理系统',
            titleColor: AppColors.dangerRed,
            isDanger: true,
            onTap: () => _showConfirm('重启 BMS',
                '重启电池管理系统可能导致电池暂时不可用，确定继续吗？', () {
              _sendCommand(
                CommandBuilder.buildRestartBmsCommand(),
                '重启指令已发送',
              );
            }),
          ),
          const SizedBox(height: 24),

          // 校准操作
          _sectionTitle('校准设置'),
          const SizedBox(height: 8),
          _calZeroRow(),
          const SizedBox(height: 10),
          _calInputRow(
            hint: '输入实际电流值',
            unit: 'A',
            btnLabel: '校准电流',
            controller: _currentCalCtrl,
            onTap: () {
              final val = double.tryParse(_currentCalCtrl.text);
              if (val == null) {
                _showSnackBar('请输入有效的电流值');
                return;
              }
              _sendCommand(
                CommandBuilder.buildCalibrateCurrentCommand(val),
                '电流校准完成',
              );
            },
          ),
          const SizedBox(height: 10),
          _calInputRow(
            hint: '输入实际电压值',
            unit: 'V',
            btnLabel: '校准电压',
            controller: _voltageCalCtrl,
            onTap: () {
              final val = double.tryParse(_voltageCalCtrl.text);
              if (val == null) {
                _showSnackBar('请输入有效的电压值');
                return;
              }
              _sendCommand(
                CommandBuilder.buildCalibrateVoltageCommand(val),
                '电压校准完成',
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => _sendCommand(
                CommandBuilder.buildSaveCalibrationCommand(),
                '校准参数保存成功',
              ),
              icon: const Icon(Icons.save),
              label: const Text('保存校准参数'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.socGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
  }

  Widget _commandTile({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    Color? titleColor,
    bool isDanger = false,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w500, color: titleColor)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _calZeroRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.center_focus_strong,
                    size: 18, color: Colors.lightBlue.shade300),
                const SizedBox(width: 8),
                const Text(
                  '校准零点偏移',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: () => _sendCommand(
            CommandBuilder.buildCalibrateZeroCommand(),
            '零点偏移校准完成',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 42),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('校准', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  Widget _calInputRow({
    required String hint,
    required String unit,
    required String btnLabel,
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.grey.shade300,
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                suffixText: unit,
                suffixStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size(80, 42),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(btnLabel, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Future<void> _showConfirm(
      String title, String message, VoidCallback onConfirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(title: title, message: message),
    );
    if (ok == true) onConfirm();
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}
