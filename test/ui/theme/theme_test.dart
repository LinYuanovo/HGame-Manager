import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hgame_manager/core/models/theme_mode.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';

void main() {
  testWidgets('主窗口和浮窗的按钮、菜单、标题继承所选字体', (tester) async {
    const family = '指定界面字体';
    for (final theme in [AppTheme.lightTheme(fontFamily: family), AppTheme.darkTheme(fontFamily: family)]) {
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: Column(children: [
        ElevatedButton(onPressed: () {}, child: const Text('主操作')),
        FilledButton(onPressed: () {}, child: const Text('保存翻译')),
        OutlinedButton(onPressed: () {}, child: const Text('选择')),
        TextButton(onPressed: () {}, child: const Text('取消')),
      ]))));
      await tester.pumpAndSettle();
      for (final label in ['主操作', '保存翻译', '选择', '取消']) {
        final context = tester.element(find.text(label));
        final style = DefaultTextStyle.of(context).style;
        expect(style.fontFamily, family);
        expect(style.fontSize, GlassConstants.fontControl);
        expect(find.ancestor(of: find.text(label), matching: find.byType(AppControlScale)), findsOneWidget);
      }
      expect(theme.popupMenuTheme.textStyle?.fontFamily, family);
      expect(theme.appBarTheme.titleTextStyle?.fontFamily, family);
    }
  });

  test('语义实色按钮前景与背景对比度至少为 4.5', () {
    for (final color in [AppTheme.errorColor, AppTheme.successColor, AppTheme.warningColor, AppTheme.starColor, AppTheme.secondaryColor]) {
      final style = AppButtonStyles.solid(color: color);
      final background = color.computeLuminance();
      final foreground = style.foregroundColor!.resolve({})!.computeLuminance();
      final ratio = background > foreground ? (background + .05) / (foreground + .05) : (foreground + .05) / (background + .05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('共享标签和呼吸边框随主题切换使用动态主色', (tester) async {
    for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
      late BuildContext themedContext;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(body: Builder(builder: (context) {
          themedContext = context;
          return const Column(children: [
            GlassChip(label: '标签', isSelected: true),
            BreathingBorder(child: Text('边框')),
          ]);
        })),
      ));
      await tester.pumpAndSettle();
      final primary = AppTheme.getPrimaryColor(themedContext);
      expect(tester.widget<Text>(find.text('标签')).style!.color, primary);
      final borderContainer = tester.widget<Container>(find.descendant(
          of: find.byType(BreathingBorder), matching: find.byType(Container)));
      final decoration = borderContainer.decoration as BoxDecoration;
      expect((decoration.border as Border).top.color,
          primary.withValues(alpha: 0.15));
      expect(AppTheme.getTextColorOnPrimary(themedContext),
          AppTheme.getOnPrimaryColor(themedContext));
      expect(AppTheme.getLoadingIndicatorColor(themedContext),
          AppTheme.getOnPrimaryColor(themedContext));
      expect(tester.takeException(), isNull);
    }
  });

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
