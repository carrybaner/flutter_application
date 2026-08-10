import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

const _channel = MethodChannel('com.example.flutter_application/app');

Future<String> _getAppLabel() async {
  try {
    final label = await _channel.invokeMethod<String>('getAppLabel');
    return label ?? '畅烁锂电';
  } catch (_) {
    return '畅烁锂电';
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appLabel = await _getAppLabel();
  runApp(ProviderScope(child: BmsApp(title: appLabel)));
}
