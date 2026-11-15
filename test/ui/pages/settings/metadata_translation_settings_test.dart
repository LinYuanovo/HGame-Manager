import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/services/metadata_translation_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/settings/metadata_translation_settings.dart';
import 'package:hgame_manager/ui/pages/settings/settings_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:http/http.dart' as http;

void main() {
  final enabled = find.byKey(const ValueKey('metadata-translation-enabled'));
  final provider = find.byKey(const ValueKey('metadata-translation-provider'));
  final testButton = find.byKey(const ValueKey('metadata-translation-test'));
  Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label);

  Future<void> selectService(WidgetTester tester, String label) async {
    await tester.ensureVisible(provider);
    await tester.tap(provider);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}内联设置按开关与服务展开，保留已填提示词', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var config = const MetadataTranslationConfig();
      const font = '测试应用字体';
      await tester.pumpWidget(MaterialApp(
        theme: dark
            ? AppTheme.darkTheme(fontFamily: font)
            : AppTheme.lightTheme(fontFamily: font),
        home: Scaffold(
            body: SingleChildScrollView(
                child: StatefulBuilder(
          builder: (context, setState) => MetadataTranslationSettings(
            config: config,
            onChanged: (value) => setState(() => config = value),
          ),
        ))),
      ));
      await tester.pumpAndSettle();
      expect(provider, findsNothing);
      expect(testButton, findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(enabled);
      await tester.pumpAndSettle();
      expect(provider, findsOneWidget);
      expect(field('接口地址'), findsNothing);
      await selectService(tester, 'LLM（OpenAI 兼容接口）');
      expect(field('接口地址'), findsOneWidget);
      final prompt = field('翻译 Prompt（留空使用默认）');
      expect(tester.widget<TextField>(prompt).decoration!.hintText,
          MetadataTranslationConfig.defaultPrompt);
      expect(tester.widget<TextField>(prompt).style!.fontFamily, font);
      await tester.enterText(field('接口地址'), 'https://example.test/v1');
      await tester.enterText(field('模型名称'), 'test');
      await tester.enterText(prompt, '使用自然的中文，保留人名。');
      await tester.pump();
      expect(config.prompt, '使用自然的中文，保留人名。');
      await selectService(tester, 'Google 翻译');
      expect(prompt, findsNothing);
      await selectService(tester, 'LLM（OpenAI 兼容接口）');
      expect(tester.widget<TextField>(prompt).controller!.text, config.prompt);
      await tester.ensureVisible(enabled);
      await tester.tap(enabled);
      await tester.pumpAndSettle();
      expect(provider, findsNothing);
      expect(prompt, findsNothing);
      await tester.tap(enabled);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(prompt).controller!.text, config.prompt);
      await tester.enterText(prompt, '');
      await tester.pumpAndSettle();
      expect(config.effectivePrompt, MetadataTranslationConfig.defaultPrompt);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('测试连接明确提示 20 秒，到时关闭请求并恢复按钮', (tester) async {
    final client = _PendingClient();
    const config = MetadataTranslationConfig(enabled: true);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
          body: MetadataTranslationSettings(
              config: config,
              onChanged: (_) {},
              service: MetadataTranslationService(
                  clientFactory: () async => client))),
    ));
    await tester.tap(testButton);
    await tester.pump();
    expect(find.text('正在测试连接，最多等待 20 秒…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(testButton).onPressed, isNull);
    await tester.pump(const Duration(seconds: 19));
    expect(client.closed, isFalse);
    expect(find.text('正在测试连接，最多等待 20 秒…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(client.closed, isTrue);
    expect(find.text('连接测试超时（20 秒），请检查网络或稍后重试'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(testButton).onPressed, isNotNull);
  });

  testWidgets('切换配置取消旧测试，旧结果不覆盖新服务', (tester) async {
    var config = const MetadataTranslationConfig(enabled: true);
    final client = _PendingClient();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(),
      home: Scaffold(
          body: SingleChildScrollView(
              child: StatefulBuilder(
                  builder: (context, setState) => MetadataTranslationSettings(
                      config: config,
                      onChanged: (value) => setState(() => config = value),
                      service: MetadataTranslationService(
                          clientFactory: () async => client))))),
    ));
    await tester.tap(testButton);
    await tester.pump();
    await selectService(tester, 'LLM（OpenAI 兼容接口）');
    expect(client.closed, isTrue);
    expect(find.textContaining('连接测试超时'), findsNothing);
    expect(find.textContaining('连接成功'), findsNothing);
    expect(tester.widget<OutlinedButton>(testButton).onPressed, isNotNull);
    expect(field('接口地址'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页直接显示开关，切换分类保留草稿且不提前保存', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = _MemorySettings();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
      child: MaterialApp(
          theme: AppTheme.lightTheme(),
          home: const Scaffold(body: SettingsDialogContent())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刮削').first);
    await tester.pumpAndSettle();
    expect(enabled, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(enabled);
    await tester.pumpAndSettle();
    await selectService(tester, 'LLM（OpenAI 兼容接口）');
    await tester.enterText(field('模型名称'), '保留草稿');
    await tester.tap(find.text('通用').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('刮削').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field('模型名称')).controller!.text, '保留草稿');
    expect(MetadataTranslationConfig.fromSettings(settings).enabled, isFalse);
    await tester.tap(find.widgetWithText(ElevatedButton, '保存').last);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialogContent), findsOneWidget);
    expect(find.text('请填写有效的 LLM 接口地址和模型名称'), findsOneWidget);
    expect(MetadataTranslationConfig.fromSettings(settings).enabled, isFalse);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义字体与放大文字下字号预览独立换行', (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(_MemorySettings())],
      child: MaterialApp(theme: AppTheme.darkTheme(fontFamily: 'MapleMonoNL-NF-CN'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.25)),
          child: child!),
        home: const Scaffold(body: SettingsDialogContent())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('预览 AaBbCc 中文 123'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

class _PendingClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;

  @override
  void close() {
    closed = true;
    if (!response.isCompleted) response.completeError(StateError('请求已关闭'));
  }
}

class _MemorySettings implements AppSettings {
  final values = <String, Object?>{
    MetadataTranslationConfig.settingsKey:
        jsonEncode(const MetadataTranslationConfig().toMap()),
  };

  @override
  String? getString(String key) => values[key] as String?;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  double? getDouble(String key) => values[key] as double?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  Object? get(String key) => values[key];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
