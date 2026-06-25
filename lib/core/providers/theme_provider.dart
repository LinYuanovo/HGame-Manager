import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/theme_mode.dart';
import '../utils/app_settings.dart';
import 'providers.dart';

/// 主题模式 Provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

/// 将 AppThemeMode 转换为 Flutter ThemeMode
final flutterThemeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(themeModeProvider);
  return switch (mode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };
});

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  final AppSettings _prefs;

  ThemeModeNotifier(this._prefs) : super(_loadInitialMode(_prefs));

  static AppThemeMode _loadInitialMode(AppSettings prefs) {
    final modeStr = prefs.getString(AppSettings.themeModeKey);
    if (modeStr == null || modeStr.isEmpty) {
      return AppThemeMode.system;
    }
    return AppThemeMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    await _prefs.setString(AppSettings.themeModeKey, mode.name);
  }
}
