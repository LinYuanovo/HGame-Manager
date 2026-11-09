import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hgame_manager/core/models/theme_mode.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';

void main() {
  testWidgets('浅深色主色按钮前景对比度达标', (tester) async {
    for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
      late BuildContext themedContext;
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(builder: (context) {
            themedContext = context;
            return const SizedBox();
          })));
      final background =
          AppTheme.getPrimaryColor(themedContext).computeLuminance();
      final foreground =
          AppTheme.getOnPrimaryColor(themedContext).computeLuminance();
      final ratio =
          (background > foreground ? background + 0.05 : foreground + 0.05) /
              (background > foreground ? foreground + 0.05 : background + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('图片失败占位随主题切换且不出现浅色固定底色', (tester) async {
    for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
      late BuildContext themedContext;
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(builder: (context) {
            themedContext = context;
            return AppTheme.imageErrorBuilder(
                context, StateError('missing'), StackTrace.current);
          })));
      final placeholder =
          tester.widget<Container>(find.byType(Container).first);
      expect(placeholder.color, AppTheme.getInputFillColor(themedContext));
      final icon = tester.widget<Icon>(find.byIcon(Icons.broken_image));
      expect(icon.color, AppTheme.getTextSecondary(themedContext));
    }
  });

  group('AppThemeMode', () {
    test('should have two modes', () {
      expect(AppThemeMode.values.length, 2);
      expect(AppThemeMode.light.name, 'light');
      expect(AppThemeMode.dark.name, 'dark');
    });

    test('should have correct labels', () {
      expect(AppThemeMode.light.label, '浅色');
      expect(AppThemeMode.dark.label, '深色');
    });

    test('should convert to ThemeMode correctly', () {
      // 测试 light 转换
      expect(
        switch (AppThemeMode.light) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        ThemeMode.light,
      );

      // 测试 dark 转换
      expect(
        switch (AppThemeMode.dark) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        ThemeMode.dark,
      );
    });
  });
}
