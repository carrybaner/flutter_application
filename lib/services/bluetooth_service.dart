import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/device_model.dart';
import '../models/broadcast_data.dart';
import '../utils/crc16_utils.dart';
import 'protocol_repository.dart';

/// 蓝牙核心服务 — 扫描 / 连接（含取型号+加载协议）/ 读写
class BluetoothService {
  BluetoothService._();
  static final BluetoothService instance = BluetoothService._();

  // ──────── 扫描 ────────

  final _deviceController = StreamController<DeviceModel>.broadcast();
  Stream<DeviceModel> get deviceStream => _deviceController.stream;
  final Map<String, DeviceModel> _devices = {};
  StreamSubscription<List<ScanResult>>? _scanSub;

  static const String deviceNameFilter = 'DCSF';

  Future<void> startScan() async {
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    _devices.clear();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName;
        if (name.isEmpty || !name.toUpperCase().contains(deviceNameFilter)) continue;
        final id = r.device.remoteId.str;
        final adv = _parseAdData(r);
        final d = DeviceModel(deviceId: id, name: name, rssi: r.rssi, advData: adv);
        _devices[id] = d;
        _deviceController.add(d);
      }
    });

    await FlutterBluePlus.startScan(androidUsesFineLocation: true);
  }

  Future<void> stopScan() async {
    _scanSub?.cancel();
    if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
  }

  BroadcastData _parseAdData(ScanResult r) {
    for (final bytes in r.advertisementData.manufacturerData.values) {
      final p = BroadcastData.parse(bytes);
      if (p.isValid) return p;
    }
    for (final bytes in r.advertisementData.serviceData.values) {
      final p = BroadcastData.parse(bytes);
      if (p.isValid) return p;
    }
    return BroadcastData.empty;
  }

  // ──────── 连接状态 ────────

  BluetoothDevice? _device;
  String? _writeCharId;
  String? _notifyCharId;
  BluetoothCharacteristic? _writeCharCached;
  BluetoothCharacteristic? _notifyCharCached;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  final _notifyController = StreamController<String>.broadcast();
  Stream<String> get notifyHex => _notifyController.stream;

  /// 协议数据包（连接成功后填充）
  ProtocolDataBundle? protocolBundle;

  /// 断连回调
  void Function()? onDisconnected;

  bool get isConnected => _device?.isConnected ?? false;

  // ──────── 连接（原始调试好的流程 + 协议加载）────────

  /// 连接设备，完成取型号和协议加载
  Future<ConnectionResult> connectAndInit(String deviceId) async {
    final t0 = DateTime.now();
    print('BLE: connecting...');
    await disconnect();
    // 等待 Android BLE 协议栈释放 GATT 资源
    await Future.delayed(const Duration(milliseconds: 300));

    _device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    await _device!.connect(timeout: const Duration(seconds: 10));
    print('BLE: connected ${DateTime.now().difference(t0).inMilliseconds}ms');

    try { await _device!.requestMtu(255); } catch (_) {}
    print('BLE: MTU done ${DateTime.now().difference(t0).inMilliseconds}ms');

    dynamic services;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        services = await _device!.discoverServices();
        break;
      } catch (e) {
        print('BLE: discoverServices attempt $attempt/3 failed: $e');
        if (attempt < 3) {
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          rethrow;
        }
      }
    }
    for (final s in services as Iterable) {
      for (final c in s.characteristics) {
        final raw = c.uuid.str.replaceAll('-', '');
        final u = raw.substring(0, raw.length < 8 ? raw.length : 8).toUpperCase();
        if (u.contains('FF01')) { _notifyCharId = c.uuid.str; _notifyCharCached = c; }
        if (u.contains('FF02')) { _writeCharId = c.uuid.str; _writeCharCached = c; }
      }
    }
    if (_writeCharId == null) throw Exception('FF02 not found');
    if (_notifyCharId == null) throw Exception('FF01 not found');
    print('BLE: services done ${DateTime.now().difference(t0).inMilliseconds}ms');

    await _enableNotify();
    print('BLE: notify done ${DateTime.now().difference(t0).inMilliseconds}ms');

    // 等待 BLE 缓冲区旧数据排出，避免被误判为型号响应
    await Future.delayed(const Duration(milliseconds: 300));

    // 重试取型号，直到加载到有效协议
    ProtocolDataBundle? bundle;
    String? protocolId;
    for (int i = 1; i <= 3; i++) {
      final t1 = DateTime.now();
      protocolId = await _sendModelCommandAndRead();
      print('BLE: model try$i ${protocolId} ${DateTime.now().difference(t1).inMilliseconds}ms');
      if (protocolId != null && protocolId.isNotEmpty) {
        bundle = await ProtocolRepository.instance.loadProtocol(protocolId);
        if (bundle != null) break;
      }
      if (i < 3) await Future.delayed(const Duration(milliseconds: 300));
    }
    if (bundle == null) throw Exception('model fail');
    print('BLE: model done ${DateTime.now().difference(t0).inMilliseconds}ms');

    // 监听断连
    _connStateSub?.cancel();
    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        onDisconnected?.call();
      }
    });

    protocolBundle = bundle;
    print('BLE: total ${DateTime.now().difference(t0).inMilliseconds}ms');
    return ConnectionResult(protocolId: protocolId!, bundle: bundle);
  }

  // ──────── 启用 Notify ────────

  Future<void> _enableNotify() async {
    if (_notifyCharCached == null) throw Exception('Notify char not cached');
    await _notifyCharCached!.setNotifyValue(true);
    _notifySub?.cancel();
    _notifySub = _notifyCharCached!.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        _notifyController.add(Crc16Utils.bytesToHex(value));
      }
    });
  }

  // ──────── 取型号：先订阅再发送（与原始 _sendModelCommand 逻辑一致）────────

  Future<String?> _sendModelCommandAndRead() async {
    final completer = Completer<String?>();
    late StreamSubscription<String> sub;
    late Timer timer;

    // 先订阅，再发送
    sub = notifyHex.listen((hex) {
      if (completer.isCompleted) return;
      final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
      if (clean.length < 10) return;
      final dataPart = clean.substring(0, clean.length - 4);
      if (Crc16Utils.calculate(dataPart) != clean.substring(clean.length - 4)) return;
      final funcCode = int.parse(clean.substring(2, 4), radix: 16);
      if (funcCode & 0x80 != 0) { completer.complete(''); return; }
      if (funcCode != 0x03) return;
      completer.complete(clean.substring(6, clean.length - 4).substring(0, 4));
    });

    timer = Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) completer.complete('');
    });

    try {
      // 发送命令（用缓存的 FF02 对象，不调 discoverServices 以免打断 Notify 流）
      final cmd = Crc16Utils.append('000300000003');
      final bytes = Uint8List.fromList(Crc16Utils.hexToBytes(cmd));
      if (_writeCharCached == null) throw Exception('FF02未缓存');
      await _writeCharCached!.write(bytes, withoutResponse: true);

      final result = await completer.future;
      return (result != null && result.isNotEmpty) ? result : null;
    } finally {
      sub.cancel();
      timer.cancel();
    }
  }

  // ──────── 写命令（供轮询/按需读取/写入使用）────────

  Future<void> writeCommand(String hexWithCrc) async {
    final bytes = Uint8List.fromList(Crc16Utils.hexToBytes(hexWithCrc));
    if (_writeCharCached == null) throw Exception('FF02未缓存');
    await _writeCharCached!.write(bytes, withoutResponse: true);
  }

  // ──────── 断开 ────────

  Future<void> disconnect() async {
    _notifySub?.cancel();
    _connStateSub?.cancel();
    try { await _device?.disconnect(); } catch (_) {}
    _device = null;
    _writeCharId = null;
    _notifyCharId = null;
    _writeCharCached = null;
    _notifyCharCached = null;
    protocolBundle = null;
  }

  List<DeviceModel> get devices => _devices.values.toList();

  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    _deviceController.close();
    _notifyController.close();
  }
}

/// 连接结果
class ConnectionResult {
  final String protocolId;
  final ProtocolDataBundle bundle;

  const ConnectionResult({required this.protocolId, required this.bundle});
}
