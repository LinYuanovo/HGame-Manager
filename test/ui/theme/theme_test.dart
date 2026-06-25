import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hgame_manager/core/models/theme_mode.dart';

void main() {
  group('AppThemeMode', () {
    test('should have three modes', () {
      expect(AppThemeMode.values.length, 3);
      expect(AppThemeMode.light.name, 'light');
      expect(AppThemeMode.dark.name, 'dark');
      expect(AppThemeMode.system.name, 'system');
    });

    test('should have correct labels', () {
      expect(AppThemeMode.light.label, '浅色');
      expect(AppThemeMode.dark.label, '深色');
      expect(AppThemeMode.system.label, '跟随系统');
    });

    test('should convert to ThemeMode correctly', () {
      // 测试 light 转换
      expect(
        switch (AppThemeMode.light) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        },
        ThemeMode.light,
      );

      // 测试 dark 转换
      expect(
        switch (AppThemeMode.dark) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        },
        ThemeMode.dark,
      );

      // 测试 system 转换
      expect(
        switch (AppThemeMode.system) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        },
        ThemeMode.system,
      );
    });
  });
}
