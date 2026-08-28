import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/locale_provider.dart';

/// 功能密码守卫：输入一次正确密码后永久解锁（解锁标记持久化到本地）。
///
/// 密码不以明文存储：代码里只保留 SHA-256(salt+密码) 的哈希常量 [_passwordHash]，
/// 校验时对输入做同样哈希后比对。默认密码如需更换，重新生成哈希替换即可
/// （生成方式见 [_passwordHash] 注释，并同步通知使用方）。
class FeatureGuard {
  FeatureGuard._();

  static const _unlockedKey = 'feature_guard_unlocked';

  /// SHA-256('zlkj-bms-2026' + '147258') —— 默认厂商密码 147258。
  /// 更换密码：计算 sha256('zlkj-bms-2026' + '新密码')，用结果替换此常量。
  static const _passwordHash =
      'eb374404eb289338c40f0a2eb98bdf80ac98c67c7a8212b3ed25d37a18188eeb';
  static const _salt = 'zlkj-bms-2026';

  static String _hash(String input) =>
      sha256.convert(utf8.encode('$_salt$input')).toString();

  /// 是否已解锁（持久化）
  static Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_unlockedKey) ?? false;
  }

  /// 校验密码（返回是否匹配）
  static Future<bool> verify(String input) async =>
      _hash(input.trim()) == _passwordHash;

  /// 已解锁直接放行；未解锁则弹密码框，验证通过后写入解锁标记。
  /// 用户取消返回 false。
  static Future<bool> ensureUnlocked(BuildContext context) async {
    if (await isUnlocked()) return true;
    if (!context.mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UnlockDialog(),
    );
    if (ok == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_unlockedKey, true);
      return true;
    }
    return false;
  }
}

/// 密码输入弹窗（obscureText，错误重试，取消关闭）
class _UnlockDialog extends ConsumerStatefulWidget {
  const _UnlockDialog();

  @override
  ConsumerState<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends ConsumerState<_UnlockDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (await FeatureGuard.verify(_ctrl.text)) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() {
        _error = ref.read(localeProvider).shell.passwordError;
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.lock_outline, color: Colors.blue, size: 22),
        const SizedBox(width: 8),
        Text(s.shell.enterPassword),
      ]),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          hintText: s.shell.passwordHint,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.common.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(s.common.ok),
        ),
      ],
    );
  }
}
