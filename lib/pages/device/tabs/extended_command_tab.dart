import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/device_data_provider.dart';
import '../../../services/command_builder.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/confirmation_dialog.dart';
import '../widgets/switch_toggle_card.dart';
import '../../../i18n/app_strings.dart';
import '../../../i18n/locale_provider.dart';

/// 扩展指令 Tab — 使用 CommandBuilder 下发固定扩展指令
class ExtendedCommandTab extends ConsumerStatefulWidget {
  const ExtendedCommandTab({super.key});

  @override
  ConsumerState<ExtendedCommandTab> createState() =>
      _ExtendedCommandTabState();
}

class _ExtendedCommandTabState extends ConsumerState<ExtendedCommandTab> {
  // 开关状态：乐观本地值，首次从 AFE Status 初始化
  bool _chargeEnabled = true;
  bool _dischargeEnabled = true;

  // 乐观更新标记：用户刚点了开关，暂时忽略一次轮询值覆盖
  bool _pendingCharge = false;
  bool _pendingDischarge = false;

  // 追踪 AFE 原始值变化
  int? _lastAfeValue;
  bool _fetInitialized = false;
  AppStrings _s = AppStrings.zh;

  // 乐观更新超时：超过 3s 未确认则放弃，强制下次轮询同步
  Timer? _chargeTimeout;
  Timer? _dischargeTimeout;

  final _currentCalCtrl = TextEditingController();
  final _voltageCalCtrl = TextEditingController();

  @override
  void dispose() {
    _chargeTimeout?.cancel();
    _dischargeTimeout?.cancel();
    _currentCalCtrl.dispose();
    _voltageCalCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCommand(String cmd, String successMsg) async {
    final poller = ref.read(realtimePollerProvider);
    if (poller == null) {
      _showSnackBar(_s.command.notConnected);
      return;
    }

    try {
      await poller.sendAndWaitResponse(cmd);
      _showSnackBar(successMsg);
    } catch (_) {
      _showSnackBar(_s.command.sendFailed);
    }
  }

  /// 从 AFE Status 解析值提取 CHG_FET(bit0) / DSG_FET(bit1)，延迟到帧末 setState
  void _syncFromAfe(dynamic afeData) {
    // 提取原始整数值（兼容 int / hex string / BitDesc List 三种格式）
    int? afeValue;
    if (afeData is int) {
      afeValue = afeData;
    } else if (afeData is String && afeData.startsWith('0x')) {
      afeValue = int.tryParse(afeData.substring(2), radix: 16);
    } else if (afeData is List) {
      // BitDesc 解析格式：[{key: 'CHG_FET', value: 0/1}, ...]
      int v = 0;
      for (final item in afeData) {
        if (item is Map) {
          final key = item['key'] as String?;
          if (key == 'CHG_FET' && item['value'] == 1) v |= (1 << 0);
          if (key == 'DSG_FET' && item['value'] == 1) v |= (1 << 1);
        }
      }
      afeValue = v;
    }
    if (afeValue == null || afeValue == _lastAfeValue) return;
    final int capturedValue = afeValue; // 类型收窄，闭包内非空

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _lastAfeValue = capturedValue;
        final realCharge = ((capturedValue >> 0) & 1) == 1;   // bit 0: CHG_FET
        final realDischarge = ((capturedValue >> 1) & 1) == 1; // bit 1: DSG_FET

        if (!_fetInitialized) {
          // 首次：直接取设备真实值
          _fetInitialized = true;
          _chargeEnabled = realCharge;
          _dischargeEnabled = realDischarge;
          _pendingCharge = false;
          _pendingDischarge = false;
        } else {
          // 后续轮询更新
          if (_pendingCharge && _chargeEnabled == realCharge) {
            // 乐观更新已被设备确认
            _pendingCharge = false;
          } else if (!_pendingCharge) {
            // 无 pending，直接同步
            _chargeEnabled = realCharge;
          }
          // pending 但值不匹配 → 保持乐观值，等待下次轮询

          if (_pendingDischarge && _dischargeEnabled == realDischarge) {
            _pendingDischarge = false;
          } else if (!_pendingDischarge) {
            _dischargeEnabled = realDischarge;
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // 监听实时数据变化，同步 AFE Status → 充/放电 FET 状态
    _s = ref.watch(localeProvider);
    ref.listen(realtimeDataProvider, (prev, next) {
      _syncFromAfe(next['AFE Status']?['AFE Status']);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 充/放电开关
          _sectionTitle(_s.command.controlSwitches),
          const SizedBox(height: 8),
          SwitchToggleCard(
            label: _s.command.chargeSwitch,
            subtitle: _s.command.chargeDesc,
            icon: Icons.power,
            value: _chargeEnabled,
            onChanged: (v) {
              setState(() {
                _chargeEnabled = v;
                _pendingCharge = true;
              });
              _chargeTimeout?.cancel();
              _chargeTimeout = Timer(const Duration(seconds: 3), () {
                if (!mounted) return;
                setState(() {
                  if (_pendingCharge) {
                    _pendingCharge = false;
                    _lastAfeValue = null; // 强制下次轮询从设备同步真实值
                  }
                });
              });
              _sendCommand(
                CommandBuilder.buildChargeToggleCommand(),
                _s.command.chargeSent,
              );
            },
          ),
          const SizedBox(height: 8),
          SwitchToggleCard(
            label: _s.command.dischargeSwitch,
            subtitle: _s.command.dischargeDesc,
            icon: Icons.power_off,
            value: _dischargeEnabled,
            onChanged: (v) {
              setState(() {
                _dischargeEnabled = v;
                _pendingDischarge = true;
              });
              _dischargeTimeout?.cancel();
              _dischargeTimeout = Timer(const Duration(seconds: 3), () {
                if (!mounted) return;
                setState(() {
                  if (_pendingDischarge) {
                    _pendingDischarge = false;
                    _lastAfeValue = null; // 强制下次轮询从设备同步真实值
                  }
                });
              });
              _sendCommand(
                CommandBuilder.buildDischargeToggleCommand(),
                _s.command.dischargeSent,
              );
            },
          ),
          const SizedBox(height: 24),

          // 系统指令
          _sectionTitle(_s.command.systemCmds),
          const SizedBox(height: 8),
          _commandTile(
            icon: Icons.access_time,
            title: _s.command.syncTime,
            subtitle: _s.command.syncDesc,
            onTap: () => _showConfirm('同步时间', _s.command.syncConfirm, () {
              _sendCommand(
                CommandBuilder.buildTimeSyncCommand(),
                _s.command.timeSyncOk,
              );
            }),
          ),
          _commandTile(
            icon: Icons.restart_alt,
            iconColor: AppColors.dangerRed,
            title: _s.command.restartBms,
            subtitle: _s.command.restartDesc,
            titleColor: AppColors.dangerRed,
            isDanger: true,
            onTap: () => _showConfirm(_s.command.restartBms,
                _s.command.restartConfirm, () {
              _sendCommand(
                CommandBuilder.buildRestartBmsCommand(),
                _s.command.restartOk,
              );
            }),
          ),
          const SizedBox(height: 24),

          // 校准操作
          _sectionTitle(_s.command.calibration),
          const SizedBox(height: 8),
          _calZeroRow(),
          const SizedBox(height: 10),
          _calInputRow(
            hint: _s.command.hintCurrent,
            unit: 'A',
            btnLabel: _s.command.calCurrent,
            controller: _currentCalCtrl,
            onTap: () {
              final val = double.tryParse(_currentCalCtrl.text);
              if (val == null) {
                _showSnackBar(_s.command.invalidCurrent);
                return;
              }
              _sendCommand(
                CommandBuilder.buildCalibrateCurrentCommand(val),
                _s.command.currentCalOk,
              );
            },
          ),
          const SizedBox(height: 10),
          _calInputRow(
            hint: _s.command.hintVoltage,
            unit: 'V',
            btnLabel: _s.command.calVoltage,
            controller: _voltageCalCtrl,
            onTap: () {
              final val = double.tryParse(_voltageCalCtrl.text);
              if (val == null) {
                _showSnackBar(_s.command.invalidVoltage);
                return;
              }
              _sendCommand(
                CommandBuilder.buildCalibrateVoltageCommand(val),
                _s.command.voltageCalOk,
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
                _s.command.saveCalOk,
              ),
              icon: const Icon(Icons.save),
              label: Text(_s.command.saveCal),
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
                    size: 18,
                    color: isDark ? Colors.lightBlue.shade200 : Colors.lightBlue.shade400),
                const SizedBox(width: 8),
                Text(
                  _s.command.calZero,
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
            _s.command.zeroCalOk,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 42),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(_s.command.calBtn, style: const TextStyle(fontSize: 14)),
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
                hintStyle: TextStyle(
                    color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.shade400,
                    fontSize: 13),
                suffixText: unit,
                suffixStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white.withOpacity(0.5) : Colors.grey.shade600,
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
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(title: title, message: message, s: _s),
    );
    if (ok == true && mounted) onConfirm();
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}
