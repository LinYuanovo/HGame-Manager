import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/settings/metadata_translation_settings.dart';
import 'package:hgame_manager/ui/pages/settings/settings_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色放大文字' : '浅色'}内联翻译设置保存、重开与连接反馈', (tester) async {
      final temporary =
          await Directory.systemTemp.createTemp('hgm_inline_translation_');
      final settingsPath = path.join(temporary.path, 'settings.json');
      final settings = await AppSettings.loadFromFileForTest(settingsPath);
      await settings.setBool('guide_window_hotkeys_enabled', false);
      await settings.setString('proxy_mode', 'none');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var stalled = false;
      var requests = 0;
      final prompts = <String>[];
      server.listen((request) async {
        requests++;
        if (stalled) return;
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        prompts.add(body['messages'][0]['content'] as String);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'content': jsonEncode({
                  'texts': ['连接测试成功']
                })
              }
            }
          ]
        }));
        await request.response.close();
      });
      final captureKey = GlobalKey();
      const evidence = String.fromEnvironment('UI_REFINEMENT_EVIDENCE');
      final toggle = find.byKey(const ValueKey('metadata-translation-enabled'));
      final provider =
          find.byKey(const ValueKey('metadata-translation-provider'));
      final testButton =
          find.byKey(const ValueKey('metadata-translation-test'));
      Finder field(String label) => find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == label);

      Future<void> capture(String name) async {
        if (evidence.isEmpty) return;
        await tester.pumpAndSettle();
        final boundary = captureKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path.join(
                  evidence, 'translation-${dark ? 'dark' : 'light'}-$name.png'))
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      Future<void> open() async {
        await tester.binding.setSurfaceSize(const Size(1600, 1100));
        await tester.tap(find.text('打开设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('刮削').first);
        await tester.pumpAndSettle();
        if (dark) await tester.binding.setSurfaceSize(const Size(1100, 1100));
        await tester.pumpAndSettle();
      }

      Future<void> select(String label) async {
        await tester.ensureVisible(provider);
        await tester.tap(provider);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      try {
        await tester.binding.setSurfaceSize(const Size(1600, 1100));
        await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
            child: MaterialApp(
              theme: dark
                  ? AppTheme.darkTheme(fontFamily: 'MapleMonoNL-NF-CN')
                  : AppTheme.lightTheme(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(dark ? 1.25 : 1)),
                  child: child!),
              home: Scaffold(
                  body: Consumer(
                      builder: (context, ref, child) => TextButton(
                          onPressed: () => showSettingsDialog(context, ref),
                          child: const Text('打开设置')))),
            ),
          ),
        ));
        await open();
        expect(find.byType(MetadataTranslationSettings), findsOneWidget);
        expect(provider, findsNothing);
        await capture('off');
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(provider, findsOneWidget);
        expect(field('接口地址'), findsNothing);
        await capture('google');
        await select('LLM（OpenAI 兼容接口）');
        await tester.enterText(
            field('接口地址'), 'http://127.0.0.1:${server.port}/v1');
        await tester.enterText(field('模型名称'), 'native-test');
        await tester.enterText(field('翻译 Prompt（留空使用默认）'), '使用自然的中文，保留人名。');
        await tester.pumpAndSettle();
        await tester.ensureVisible(field('模型名称'));
        await capture('llm');
        await tester.ensureVisible(testButton);
        await tester.tap(testButton);
        for (var attempt = 0;
            attempt < 80 && find.textContaining('连接成功').evaluate().isEmpty;
            attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining('连接成功（LLM）'), findsOneWidget);
        expect(requests, 1);
        expect(prompts.single, startsWith('使用自然的中文'));
        await capture('connected');
        await select('Google 翻译');
        expect(field('接口地址'), findsNothing);
        await select('LLM（OpenAI 兼容接口）');
        expect(tester.widget<TextField>(field('模型名称')).controller!.text,
            'native-test');
        expect(
            MetadataTranslationConfig.fromSettings(settings).enabled, isFalse);
        await tester.tap(find.widgetWithText(ElevatedButton, '保存').last);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsDialogContent), findsNothing);
        final stored = jsonDecode(await File(settingsPath).readAsString());
        final config = MetadataTranslationConfig.fromMap(
            jsonDecode(stored[MetadataTranslationConfig.settingsKey]));
        expect(config.enabled, isTrue);
        expect(config.provider, 'llm');
        expect(config.prompt, '使用自然的中文，保留人名。');
        await open();
        expect(tester.widget<TextField>(field('模型名称')).controller!.text,
            'native-test');

        if (!dark) {
          stalled = true;
          await tester.ensureVisible(testButton);
          final elapsed = Stopwatch()..start();
          await tester.tap(testButton);
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('正在测试连接，最多等待 20 秒…'), findsOneWidget);
          for (var attempt = 0;
              attempt < 60 && find.textContaining('连接测试超时').evaluate().isEmpty;
              attempt++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(find.text('连接测试超时（20 秒），请检查网络或稍后重试'), findsOneWidget);
          expect(elapsed.elapsed.inSeconds, inInclusiveRange(19, 28));
          expect(requests, 2);
          await capture('timeout');
        }
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(provider, findsNothing);
        await tester.tap(find.widgetWithText(OutlinedButton, '取消').last);
        await tester.pumpAndSettle();
        expect(
            MetadataTranslationConfig.fromSettings(settings).enabled, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
        await settings.flush();
        AppSettings.invalidateCache();
        await server.close(force: true);
        await temporary.delete(recursive: true);
      }
    });
  }
}
