import 'package:flutter/material.dart';

/// 应用颜色常量
class AppColors {
  AppColors._();

  // 电池电量颜色
  static const socRed = Color(0xFFE53935);
  static const socYellow = Color(0xFFFFA726);
  static const socGreen = Color(0xFF66BB6A);

  // 主题色
  static const bmsTeal = Color(0xFF00897B);
  static const bmsTealLight = Color(0xFF4DB6AC);

  // 危险/告警
  static const dangerRed = Color(0xFFD32F2F);
  static const warningOrange = Color(0xFFF57C00);
  static const infoBlue = Color(0xFF1976D2);
  static const chargingGreen = Color(0xFF4CAF50);

  // 暗色主题背景
  static const darkBackground = Color(0xFF121220);
  static const darkSurface = Color(0xFF1A1A2E);
  static const darkCard = Color(0xFF222238);
}

/// 亮色主题
ThemeData lightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.bmsTeal,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    cardTheme: CardTheme(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: Colors.white.withOpacity(0.72),
      indicatorColor: colorScheme.primaryContainer,
    ),
    dividerColor: Colors.grey.shade300,
    brightness: Brightness.light,
  );
}

/// 暗色主题
ThemeData darkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.bmsTeal,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.darkBackground,
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      color: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: AppColors.darkSurface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: AppColors.darkSurface.withOpacity(0.9),
      indicatorColor: colorScheme.primaryContainer,
    ),
    dividerColor: Colors.white.withOpacity(0.1),
    brightness: Brightness.dark,
  );
}
