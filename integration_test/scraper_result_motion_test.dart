import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/services/game_data_migration_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/scraper/scraper_page.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

class _UnavailableDirectory extends Fake implements GameDataMigrationService {
  @override
  Future<GameDataMigrationResult> migrateGameDirectory(String gamePath,
      {int? gameId, bool logNoop = true}) async {
    throw FileSystemException('测试目录读取失败', gamePath);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('连续定位不同失败目录，暂停跟随后阅读位置保留', (tester) async {
    final temp = await Directory.systemTemp.createTemp('hgame-motion-queue-');
    final library = await Directory(path.join(temp.path, 'games')).create();
    addTearDown(() async {
      AppSettings.invalidateCache();
      await temp.delete(recursive: true);
    });
    for (var index = 0; index < 12; index++) {
      final folder =
          await Directory(path.join(library.path, 'sample-$index')).create();
      await File(path.join(folder.path, 'source_url.txt'))
          .writeAsString('https://example.invalid/game/$index');
    }
    final settingsFile = File(path.join(temp.path, 'settings.json'));
    await settingsFile
        .writeAsString(jsonEncode({'library_path': library.path}));
    final settings = await AppSettings.loadFromFileForTest(settingsFile.path);
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPreferencesProvider.overrideWithValue(settings),
      gameDataMigrationServiceProvider
          .overrideWithValue(_UnavailableDirectory()),
    ], child: const MaterialApp(home: Scaffold(body: ScraperPage()))));

    Future<void> waitFor(Finder finder) async {
      for (var step = 0; step < 100 && finder.evaluate().isEmpty; step++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(finder, findsOneWidget);
    }

    await tester.tap(find.text('扫描游戏库'));
    await waitFor(find.ancestor(
        of: find.text('刮削元数据'),
        matching: find.byWidgetPredicate(
            (widget) => widget is ElevatedButton && widget.onPressed != null)));
    await tester.tap(find.byTooltip('暂停跟随日志'));
    await tester.pump();
    final logList = tester.widget<ListView>(find.byType(ListView).last);
    final readingPosition = logList.controller!.offset;
    await tester.tap(find.text('刮削元数据'));
    await waitFor(find.text('查看失败项'));
    final locate = find.text('查看失败项');
    await tester.ensureVisible(locate);
    await tester.tap(locate);
    await tester.pumpAndSettle();
    final failureDetail = find.byWidgetPredicate((widget) =>
        widget is Text && (widget.data?.startsWith(library.path) ?? false));
    await waitFor(failureDetail);
    final first = tester.widget<Text>(failureDetail).data;
    for (var step = 0; step < 6; step++) {
      await tester.tap(find.text('下一项失败'));
      await tester.pumpAndSettle();
    }
    final current = tester.widget<Text>(failureDetail).data!;
    expect(current, isNot(first));
    expect(current, contains('测试目录读取失败'));
    final target =
        find.text(path.basename(current.split(' · ').first)).hitTestable();
    expect(target, findsOneWidget);
    expect(logList.controller!.offset, closeTo(readingPosition, 1));
    await tester.tap(find.byTooltip('跟随最新日志'));
    await tester.pumpAndSettle();
    expect(logList.controller!.position.extentAfter, closeTo(0, 1));
  });
}
