import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/device_model.dart';
import '../../i18n/app_strings.dart';
import '../../i18n/locale_provider.dart';
import '../../providers/device_data_provider.dart';
import '../../services/bluetooth_service.dart';
import '../../utils/sn_parser.dart';
import '../device/device_page.dart';

/// 扫码自动连接设备页
class ScanPage extends ConsumerStatefulWidget {
  /// 父级传入的可见性通知器
  final ValueNotifier<bool> isActiveNotifier;
  const ScanPage({super.key, required this.isActiveNotifier});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _service = BluetoothService.instance;
  StreamSubscription<DeviceModel>? _btSub;
  final List<DeviceModel> _devices = [];
  bool _isScanning = false;
  AppStrings _s = AppStrings.zh;

  MobileScannerController? _cameraCtrl;
  bool _cameraReady = false;
  bool _isProcessing = false;
  String _lastScannedSn = '';
  DateTime _lastScanTime = DateTime(2000);
  Completer<void>? _connectCompleter;

  // 扫描线动画
  late final AnimationController _scanAnimCtrl;
  late final Animation<double> _scanAnim;

  bool _initialized = false;

  // ──── 生命周期 ────

  bool get _isActive => widget.isActiveNotifier.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scanAnimCtrl = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _scanAnim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanAnimCtrl, curve: Curves.easeInOut),
    );

    widget.isActiveNotifier.addListener(_onActiveChanged);
    // 首次 Tab 切到扫码时才触发权限请求，不做预初始化
    if (_isActive) _onActiveChanged();
  }

  Future<void> _requestPermissionsAndStart() async {
    // 先请求所有必需权限
    if (Platform.isAndroid) {
      await [
        Permission.camera,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
    }
    if (Platform.isIOS) {
      await [Permission.camera, Permission.bluetooth].request();
    }

    if (!mounted || !_isActive) return;
    _initCamera();
    _startBtScan();
  }

  void _onActiveChanged() {
    if (!_isActive) {
      _cameraCtrl?.stop();
      _btSub?.cancel();
      _service.stopScan();
      setState(() => _isScanning = false);
      return;
    }

    // 首次激活：请求权限 + 启动
    if (!_initialized) {
      _initialized = true;
      _requestPermissionsAndStart();
      return;
    }

    // 后续切回：恢复相机和扫描
    if (_cameraReady) _cameraCtrl?.start();
    _startBtScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isActive) return;
    if (state == AppLifecycleState.resumed && _cameraReady) {
      _cameraCtrl?.start();
    } else if (state == AppLifecycleState.inactive) {
      _cameraCtrl?.stop();
    }
  }

  void _initCamera() {
    _cameraCtrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
    );
    _cameraCtrl!.start().then((_) {
      if (mounted) setState(() => _cameraReady = true);
    });
  }

  void _startBtScan() {
    if (!_isActive) return;
    if (_btSub != null && _isScanning) return;

    _btSub?.cancel();
    _btSub = _service.deviceStream.listen((device) {
      if (!mounted) return;
      setState(() {
        final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
        if (idx >= 0) {
          _devices[idx] = device;
        } else {
          _devices.add(device);
        }
        _devices.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    setState(() => _isScanning = true);
    _service.startScan().catchError((_) {});
  }

  // ──── QR 检测 ────

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || !mounted) return;

    // 收集本轮所有不同的 SN
    final snSet = <String>{};
    final now = DateTime.now();

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final sn = SnParser.extract(raw);
      if (sn == null) continue;

      // 防抖：同一 SN 3 秒内不过
      if (sn == _lastScannedSn && now.difference(_lastScanTime).inSeconds < 3) {
        continue;
      }
      snSet.add(sn);
    }

    if (snSet.isEmpty) return;

    // 只有一个 → 直接处理
    if (snSet.length == 1) {
      final sn = snSet.first;
      _lastScannedSn = sn;
      _lastScanTime = now;
      _handleSn(sn);
      return;
    }

    // 多个 → 让用户选
    _lastScanTime = now;
    _showSnPicker(snSet.toList());
  }

  // ──── SN 处理 ────

  void _handleSn(String sn) async {
    setState(() => _isProcessing = true);
    _cameraCtrl?.stop();

    // 1. 在设备列表中查找匹配
    DeviceModel? matched = _findDevice(sn);

    if (matched == null) {
      _showSnackBar(_s.scan.notFound + ' ' + sn);
      setState(() => _isProcessing = false);
      _cameraCtrl?.start();
      return;
    }

    // 2. 检查是否已连接同一设备
    final connectedDevice = ref.read(connectedDeviceProvider);
    final isConnected = ref.read(isConnectedProvider);

    if (isConnected && connectedDevice != null && connectedDevice.deviceId == matched.deviceId) {
      final result = ref.read(connectionResultProvider);
      if (result != null) {
        _navigateToDevice(matched, result);
        return;
      }
      // result 异常为空 → 提示但不走重连
      _showSnackBar(_s.scan.connectionError);
      setState(() => _isProcessing = false);
      _cameraCtrl?.start();
      return;
    }

    // 3. 已连其他设备，直接断开再连新
    if (isConnected && connectedDevice != null && connectedDevice.deviceId != matched.deviceId) {
      try {
        ref.invalidate(disconnectDeviceProvider);
        await ref.read(disconnectDeviceProvider.future);
      } catch (_) {}
    }

    // 4. 连接（带超时）
    _showConnectingDialog(matched);
    _connectCompleter = Completer<void>();

    try {
      ref.invalidate(connectDeviceProvider(matched.deviceId));
      final future = ref.read(connectDeviceProvider(matched.deviceId).future);

      // 15 秒超时
      final result = await future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(_s.scan.timeout),
      );

      if (!mounted) return;
      ref.read(connectedDeviceProvider.notifier).state = matched;
      _connectCompleter?.complete();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _closeConnectingDialog();
        _navigateToDevice(matched, result);
      });
    } catch (e) {
      if (!mounted) return;
      _connectCompleter?.complete();
      _closeConnectingDialog();
      _showSnackBar(e is TimeoutException ? _s.scan.timeout : '${_s.bluetooth.connectFailed}: $e');
      setState(() => _isProcessing = false);
      _cameraCtrl?.start();
    }
  }

  // ──── 设备匹配 ────

  DeviceModel? _findDevice(String sn) {
    final upperSn = sn.toUpperCase();

    // 剥离 SN 中的已知前缀（DCSF/BMS + 分隔符），用于跨前缀匹配
    // 例：QR 中是 "BMS+7003260715056"，BLE 广播是 "DCSF-7003260715056"
    final snCore = sn.replaceAll(RegExp(r'^(?:DCSF|BMS)[_\-:+\s]?'), '').toUpperCase();

    for (final d in _devices) {
      final dName = d.name.toUpperCase();
      final dDisp = d.displayName.toUpperCase();

      if (dName == upperSn) return d;
      if (dDisp == upperSn) return d;
      if (dName.endsWith(upperSn)) return d;
      // 跨前缀匹配：用 SN 核心数字部分匹配
      if (dDisp == snCore) return d;
      if (dName.endsWith(snCore)) return d;
      if (upperSn.length >= 5 && dName.contains(upperSn)) return d;
      if (snCore.length >= 5 && dName.contains(snCore)) return d;
    }
    return null;
  }

  // ──── 导航 ────

  void _navigateToDevice(DeviceModel device, ConnectionResult result) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DevicePage(device: device, connectionResult: result),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (_isActive && _cameraReady) _cameraCtrl?.start();
      }
    });
  }

  // ──── 弹窗 ────

  OverlayEntry? _connectingOverlay;

  void _showConnectingDialog(DeviceModel device) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text('${_s.scan.connecting} ${device.displayName}...'),
            ],
          ),
        ),
      ),
    );
  }

  void _closeConnectingDialog() {
    if (_connectingOverlay != null) {
      _connectingOverlay!.remove();
      _connectingOverlay = null;
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showSnPicker(List<String> snList) {
    _cameraCtrl?.stop();
    showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(_s.scan.multipleCodes,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            ...snList.map((sn) => ListTile(
                  leading: const Icon(Icons.qr_code),
                  title: Text(sn),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, sn),
                )),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_s.scan.cancel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((selected) {
      if (selected != null) {
        _lastScannedSn = selected;
        _handleSn(selected);
      } else {
        setState(() => _isProcessing = false);
        _cameraCtrl?.start();
      }
    });
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──── UI ────

  @override
  Widget build(BuildContext context) {
    _s = ref.watch(localeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_s.scan.title),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(child: _buildScanner()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 相机
          if (_cameraReady && _cameraCtrl != null)
            MobileScanner(
              controller: _cameraCtrl,
              onDetect: _onDetect,
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white54),
                  SizedBox(height: 16),
                  Text(_s.scan.cameraLoading, style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
          // 扫描框
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // 扫描线
          Center(
            child: AnimatedBuilder(
              animation: _scanAnim,
              builder: (_, __) {
                return Container(
                  width: 240,
                  height: 240,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
                  child: Align(
                    alignment: Alignment(0, _scanAnim.value * 2 - 1),
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.withOpacity(0),
                            Colors.greenAccent,
                            Colors.green.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 角标
          Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  Positioned(top: -2, left: -2, child: _corner(Alignment.topLeft)),
                  Positioned(top: -2, right: -2, child: _corner(Alignment.topRight)),
                  Positioned(bottom: -2, left: -2, child: _corner(Alignment.bottomLeft)),
                  Positioned(bottom: -2, right: -2, child: _corner(Alignment.bottomRight)),
                ],
              ),
            ),
          ),
          // 提示文字
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              _s.scan.hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner(Alignment align) {
    return Transform.rotate(
      angle: _cornerAngle(align),
      child: CustomPaint(
        size: const Size(20, 20),
        painter: _CornerPainter(),
      ),
    );
  }

  double _cornerAngle(Alignment align) {
    if (align == Alignment.topLeft) return 0;
    if (align == Alignment.topRight) return 1.5708;
    if (align == Alignment.bottomRight) return 3.14159;
    return 4.71239;
  }

  Widget _buildStatusBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connected = ref.watch(connectedDeviceProvider);
    final isConnected = ref.watch(isConnectedProvider);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
      child: Row(
        children: [
          Icon(
            Icons.bluetooth_searching,
            size: 18,
            color: _isScanning ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            _isScanning ? '${_s.scan.scanning} · ${_devices.length}${_s.scan.devicesUnit}' : _s.scan.stopped,
            style: const TextStyle(fontSize: 13),
          ),
          const Spacer(),
          if (connected != null && isConnected)
            Chip(
              avatar: const Icon(Icons.bluetooth_connected, size: 16),
              label: Text(connected.displayName, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _btSub?.cancel();
    _service.stopScan();
    _cameraCtrl?.dispose();
    _scanAnimCtrl.dispose();
    super.dispose();
  }
}

// ──── 扫描框角标 Painter ────

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, 0)
      ..lineTo(0, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
