import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

class LocaleNotifier extends StateNotifier<AppStrings> {
  LocaleNotifier() : super(AppStrings.zh) { _load(); }

  static const _key = 'app_locale';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_key) ?? 'zh';
    state = key == 'en' ? AppStrings.en : AppStrings.zh;
  }

  Future<void> setLocale(AppLocale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.name);
    state = locale == AppLocale.en ? AppStrings.en : AppStrings.zh;
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppStrings>((ref) => LocaleNotifier());
