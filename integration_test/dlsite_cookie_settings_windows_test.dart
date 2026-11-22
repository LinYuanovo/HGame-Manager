import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/services/dlsite_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/proxy_client.dart';
import 'package:hgame_manager/ui/pages/settings/settings_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late AppSettings settings;
  final cookieField = find.byWidgetPredicate((widget) =>
      widget is TextField &&
      widget.decoration?.hintText == '登录 www.dlsite.com 后复制作品页请求的 Cookie');

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hgm_dlsite_cookie_ui_');
    settings = await AppSettings.loadFromFileForTest(
        '${temporary.path}/settings.json');
    await settings.setString('cookie_dlsite', 'session=saved');
    await settings.flush();
  });

  tearDown(() async {
    await settings.flush();
    AppSettings.invalidateCache();
    await temporary.delete(recursive: true);
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(cookieField);
    await tester.pumpAndSettle();
  }

  Future<void> saveSettings(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, '保存'));
    for (var attempt = 0;
        attempt < 100 &&
            find.byType(SettingsDialogContent).evaluate().isNotEmpty;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(SettingsDialogContent), findsNothing);
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}设置保存、取消、重开及清空 DLsite 登录态',
        (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 1000));
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cookies = <String?>[];
      final service = DlsiteService(
          clientFactory: () async => MockClient((request) async {
                cookies.add(request.headers['cookie']);
                return http.Response('', 200);
              }));
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
        child: MaterialApp(
          theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showSettingsDialog(context, ref, targetItem: 'Cookie设置'),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await openSettings(tester);
      expect(tester.widget<TextField>(cookieField).controller!.text,
          'session=saved');
      await tester.enterText(cookieField, 'session=cancelled');
      await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
      await tester.pumpAndSettle();
      expect(settings.getString('cookie_dlsite'), 'session=saved');

      await openSettings(tester);
      await tester.enterText(cookieField, '  session=updated==  ');
      await saveSettings(tester);
      expect(settings.getString('cookie_dlsite'), 'session=updated==');
      await service.search('test');
      expect(cookies.last, contains('session=updated=='));
      expect(
          (await buildScrapeImageHeaders('https://www.dlsite.com/'))['Cookie'],
          'session=updated==');

      await openSettings(tester);
      expect(tester.widget<TextField>(cookieField).controller!.text,
          'session=updated==');
      await tester.enterText(cookieField, '');
      await saveSettings(tester);
      await service.search('test');
      expect(cookies.last, 'adultchecked=1; locale=zh_CN');
      settings = await AppSettings.loadFromFileForTest(
          '${temporary.path}/settings.json');
      expect(settings.getString('cookie_dlsite'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
