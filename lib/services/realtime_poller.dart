import 'dart:async';
import '../models/protocol_item.dart';
import 'bluetooth_service.dart';
import 'command_builder.dart';
import 'protocol_parser.dart' show ProtocolParser;

/// 实时数据轮询器
/// 连接成功后启动，每秒顺序轮询 realtime groups
/// 每组: 发→收→parse→存 cache → 轮完即推 UI
class RealtimePoller {
  final BluetoothService _service;
  final List<ProtocolGroup> _groups;
  final Map<String, String> _commands = {};
  final Map<String, Map<String, dynamic>> cache = {};

  Timer? _timer;
  bool _polling = false;
  bool _paused = false;
  Completer<String>? _responseCompleter;
  StreamSubscription<String>? _notifySub;
  final _rxBuffer = StringBuffer();
  Timer? _rxTimer;
  void Function()? onCycleDone;

  RealtimePoller(this._service, this._groups) {
    for (final g in _groups) {
      _commands[g.groupCode] = CommandBuilder.buildReadCommand(g);
    }
  }

  void start() {
    _notifySub = _service.notifyHex.listen(_onNotify);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_paused && !_polling && _service.isConnected) _pollAll();
    });
    _pollAll(); // 立即执行第一轮
  }

  void stop() {
    _timer?.cancel();
    _rxTimer?.cancel();
    _notifySub?.cancel();
    _responseCompleter = null;
    _polling = false;
    _paused = false;
  }

  Future<void> pause() async {
    _paused = true;
    while (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  void resume() => _paused = false;

  Future<String?> sendAndWaitResponse(String command) async {
    if (!_service.isConnected) return null;
    _paused = true;
    while (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _rxBuffer.clear();
    final myCompleter = Completer<String>();
    _responseCompleter = myCompleter;
    try {
      await _service.writeCommand(command);
      return await myCompleter.future.timeout(const Duration(milliseconds: 1000));
    } on TimeoutException {
      return null;
    } finally {
      _rxTimer?.cancel();
      _responseCompleter = null;
      _paused = false;
    }
  }

  Future<void> _pollAll() async {
    _polling = true;
    for (final group in _groups) {
      if (!_service.isConnected || _paused) break;
      _rxBuffer.clear();
      _responseCompleter = Completer<String>();
      try {
        await _service.writeCommand(_commands[group.groupCode]!);
        final hex = await _responseCompleter!.future
            .timeout(const Duration(milliseconds: 1000));
        final data = ProtocolParser.parseToMap(group, hex);
        if (data != null) {
          cache[group.groupCode] = data;
        }
      } on TimeoutException {
        _responseCompleter = null;
        continue;
      } catch (_) {
        _responseCompleter = null;
        continue;
      }
    }
    _polling = false;
    onCycleDone?.call();
  }

  void _onNotify(String hex) {
    if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
      _rxBuffer.write(hex);
      _rxTimer?.cancel();
      _rxTimer = Timer(const Duration(milliseconds: 20), () {
        if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
          _responseCompleter!.complete(_rxBuffer.toString());
        }
      });
    }
  }
}
