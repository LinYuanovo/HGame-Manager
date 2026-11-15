import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/settings/metadata_translation_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}下 Prompt 默认提示、编辑、保存、重开和清空',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = _MemorySettings(const MetadataTranslationConfig(
        enabled: true,
        provider: 'llm',
        baseUrl: 'https://example.test/v1',
        model: 'test',
      ));
      await tester.pumpWidget(MaterialApp(
        theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            MetadataTranslationDialog(settings: settings),
                      ),
                      child: const Text('打开设置'),
                    ))),
      ));
      final prompt = find.byWidgetPredicate((widget) =>
          widget is TextField &&
          widget.decoration?.labelText == '翻译 Prompt（留空使用默认）');
      Future<void> open() async {
        await tester.tap(find.text('打开设置'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(prompt);
        await tester.pumpAndSettle();
      }

      await open();
      final field = tester.widget<TextField>(prompt);
      expect(field.controller!.text, isEmpty);
      expect(
          field.decoration!.hintText, MetadataTranslationConfig.defaultPrompt);
      expect(field.decoration!.floatingLabelBehavior,
          FloatingLabelBehavior.always);
      expect(
          find.text(MetadataTranslationConfig.defaultPrompt), findsOneWidget);
      const custom = '用自然的中文翻译。\n保留游戏角色名字。';
      await tester.enterText(prompt, custom);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(MetadataTranslationConfig.fromSettings(settings).prompt, custom);
      expect(settings.flushes, 1);
      await open();
      expect(tester.widget<TextField>(prompt).controller!.text, custom);
      await tester.enterText(prompt, '');
      await tester.pumpAndSettle();
      expect(
          find.text(MetadataTranslationConfig.defaultPrompt), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(MetadataTranslationConfig.fromSettings(settings).prompt, isEmpty);
      expect(MetadataTranslationConfig.fromSettings(settings).effectivePrompt,
          MetadataTranslationConfig.defaultPrompt);
      expect(tester.takeException(), isNull);
    });
  }
}

class _MemorySettings implements AppSettings {
  final Map<String, String> values;
  int flushes = 0;

  _MemorySettings(MetadataTranslationConfig config)
      : values = {
          MetadataTranslationConfig.settingsKey: jsonEncode(config.toMap())
        };

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<void> flush() async {
    flushes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
