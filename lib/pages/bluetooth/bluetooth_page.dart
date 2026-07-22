import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/device_model.dart';
import '../../providers/theme_provider.dart';
import '../../providers/device_data_provider.dart';
import '../../services/bluetooth_service.dart';
import '../device/device_page.dart';
import 'widgets/device_card.dart';

/// 蓝牙设备扫描页
class BluetoothPage extends ConsumerStatefulWidget {
  const BluetoothPage({super.key});

  @override
  ConsumerState<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends ConsumerState<BluetoothPage>
    with TickerProviderStateMixin {
  final _service = BluetoothService.instance;
  StreamSubscription<DeviceModel>? _sub;

  final List<DeviceModel> _devices = [];
  bool _isScanning = false;

  late final AnimationController _refreshAnimCtrl;

  @override
  void initState() {
    super.initState();
    _refreshAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _startScan();
  }

  Future<void> _startScan() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
    if (Platform.isIOS) {
      await [Permission.bluetooth].request();
    }

    _sub?.cancel();
    setState(() => _devices.clear());
    _sub = _service.deviceStream.listen((device) {
      if (!mounted) return;
      setState(() {
        final idx =
            _devices.indexWhere((d) => d.deviceId == device.deviceId);
        if (idx >= 0) {
          _devices[idx] = device;
        } else {
          _devices.add(device);
        }
        _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    setState(() => _isScanning = true);
    _refreshAnimCtrl.repeat();

    try {
      await _service.startScan(); // 不设 timeout，持续扫描直到 stopScan
    } catch (_) {}
    // 只有 stopScan 被调用才会到达这里
  }

  void _onDeviceTap(DeviceModel device) async {
    // 如果已连接该设备，直接进入设备页，不重连
    final connectedDevice = ref.read(connectedDeviceProvider);
    if (connectedDevice != null && connectedDevice.deviceId == device.deviceId) {
      final result = ref.read(connectionResultProvider);
      if (result == null) return;
      _sub?.cancel();
      _service.stopScan();
      setState(() => _isScanning = false);
      _refreshAnimCtrl.stop();
      _refreshAnimCtrl.reset();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DevicePage(device: device, connectionResult: result),
        ),
      ).then((_) {
        if (mounted) _startScan();
      });
      return;
    }

    // 已连其他设备时，先完整断开旧连接
    if (connectedDevice != null) {
      try {
        ref.invalidate(disconnectDeviceProvider);
        await ref.read(disconnectDeviceProvider.future);
      } catch (_) {}
    }

    _sub?.cancel();
    _service.stopScan();
    setState(() => _isScanning = false);
    _refreshAnimCtrl.stop();
    _refreshAnimCtrl.reset();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConnectingDialog(deviceName: device.displayName),
    );

    // 使用新连接流程：连接 → 取型号 → 加载协议 → 启动轮询
    // 先 invalidate 缓存，防止同一 deviceId 重连时返回旧结果
    ref.invalidate(connectDeviceProvider(device.deviceId));
    ref.read(connectDeviceProvider(device.deviceId).future).then((result) {
      if (!mounted) return;
      ref.read(connectedDeviceProvider.notifier).state = device;
      // 延迟到下一帧，避免 build 阶段操作 Navigator
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DevicePage(
              device: device,
              connectionResult: result,
            ),
          ),
        ).then((_) {
          // 返回后不 disconnect，恢复扫描
          if (mounted) _startScan();
        });
      });
    }).catchError((e) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
        _startScan();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.stopScan();
    _refreshAnimCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(isDark),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                if (ref.read(connectedDeviceProvider) != null) {
                  ref.read(connectedDeviceProvider.notifier).state = null;
                  ref.read(isConnectedProvider.notifier).state = false;
                  ref.read(connectionResultProvider.notifier).state = null;
                  final poller = ref.read(realtimePollerProvider);
                  poller?.stop();
                  ref.read(realtimePollerProvider.notifier).state = null;
                  ref.read(realtimeDataProvider.notifier).state = {};
                  ref.read(recordCacheProvider.notifier).state = [];
                  ref.read(recordCacheOwnerProvider.notifier).state = null;
                  try {
                    await _service.disconnect();
                  } catch (_) {}
                }
                await _startScan();
              },
              child: Consumer(builder: (_, ref, __) {
                final connected = ref.watch(connectedDeviceProvider);
                final isConnected = ref.watch(isConnectedProvider);
                final showConnected = connected != null && isConnected;
                final scanDevices = showConnected
                    ? _devices
                        .where((d) => d.deviceId != connected!.deviceId)
                        .toList()
                    : _devices;

                if (!showConnected && scanDevices.isEmpty && !_isScanning) {
                  return ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bluetooth_searching,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              Text('未发现设备',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  itemCount: scanDevices.length + (showConnected ? 1 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (_, i) {
                  if (i == 0 && showConnected) {
                    return DeviceCard(
                      device: connected!,
                      isConnected: true,
                      onTap: () => _onDeviceTap(connected!),
                    );
                  }
                  final device = showConnected
                      ? scanDevices[i - 1]
                      : scanDevices[i];
                  return DeviceCard(
                    device: device,
                    onTap: () => _onDeviceTap(device),
                  );
                },
              );
            })),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 20,
        right: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color:
            isDark ? Theme.of(context).colorScheme.surface : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.15),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth,
              color: Theme.of(context).colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            '设备连接',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              size: 22,
            ),
            onPressed: () => ref.read(themeProvider.notifier).toggle(),
            tooltip: '切换主题',
          ),
          if (_isScanning)
            RotationTransition(
              turns: _refreshAnimCtrl,
              child: const Icon(Icons.refresh, size: 22),
            ),
        ],
      ),
    );
  }
}

/// 连接中弹窗
class _ConnectingDialog extends StatelessWidget {
  final String deviceName;
  const _ConnectingDialog({required this.deviceName});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text('正在连接...',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(deviceName,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
