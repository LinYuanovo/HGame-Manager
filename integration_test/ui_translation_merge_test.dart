import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/app_logger.dart';
import 'package:hgame_manager/core/services/cleared_metadata_backup_service.dart';
import 'package:hgame_manager/core/services/metadata_translation_service.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/utils/app_paths.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/ui/pages/games/game_detail_page.dart';
import 'package:hgame_manager/ui/pages/settings/metadata_translation_settings.dart';
import 'package:hgame_manager/ui/pages/settings/settings_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/game_list_widget.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('整合：五种流程保留原文和分类，浅深色切换及诊断导出', (tester) async {
    expect(Platform.isWindows, isTrue);
    final dataDirectory =
        await Directory.systemTemp.createTemp('hgm_merge_review_data_');
    AppPaths.overrideRootDirForTesting(dataDirectory.path);
    final dataRoot = await AppPaths.rootDir;
    expect(path.normalize(dataRoot), path.normalize(dataDirectory.path));
    expect(await File(await AppPaths.databaseFile).exists(), isFalse,
        reason: '验收必须使用隔离的临时数据库');
    expect(await Directory(dataRoot).list().isEmpty, isTrue,
        reason: '验收数据目录必须为空');
    final temporary =
        await Directory.systemTemp.createTemp('hgm_merge_review_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final systemPrompts = <String>[];
    server.listen((request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      systemPrompts.add(body['messages'][0]['content'] as String);
      final texts =
          (jsonDecode(body['messages'][1]['content'])['texts'] as List)
              .cast<String>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': jsonEncode({
                'texts': texts
                    .map((text) => text == 'Action' ? '动作' : '中:$text')
                    .toList(),
              }),
            },
          },
        ],
      }));
      await request.response.close();
    });
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    final logger = AppLogger.instance;
    await logger.init();
    expect(logger.logDir,
        path.join(File(Platform.resolvedExecutable).parent.path, 'logs'));
    final config = MetadataTranslationConfig(
      enabled: true,
      provider: 'llm',
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'controlled-response',
    );
    await settings.setString(
        MetadataTranslationConfig.settingsKey, jsonEncode(config.toMap()));
    await settings.setString('proxy_mode', 'none');
    final library = path.join(temporary.path, 'library');
    final sorted = path.join(temporary.path, 'sorted');
    await settings.setString('sorted_paths', jsonEncode({library: sorted}));
    final repo = GameRepository();
    final tagRepo = TagRepository();
    final configs = ScrapeModeConfigs(configs: {
      for (final mode in ScrapeMode.values)
        mode: const ScrapeModeConfig(moveToSorted: true),
    });
    const evidencePath = String.fromEnvironment('TRANSLATION_FIX_EVIDENCE');
    final captureKey = GlobalKey();
    Future<void> capture(String name) async {
      if (evidencePath.isEmpty) return;
      final boundary = captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path.join(evidencePath, '$name.png')).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
    Game? displayGame;
    try {
      for (final mode in ScrapeMode.values) {
        final folder = await Directory(path.join(library, mode.name))
            .create(recursive: true);
        final info = GameInfo(
          title: 'Village ${mode.name}',
          description: 'Explore',
          descriptionHtml: '<p>Explore</p>',
          tags: mode == ScrapeMode.quickScrape
              ? ['Action']
              : ['RPG', 'Adventure'],
          category: mode == ScrapeMode.quickScrape ? null : 'RPG',
          sourceUrl: 'https://source.example.test/game',
        );
        final notices = <String>[];
        Game game;
        if (mode == ScrapeMode.singleAdd || mode == ScrapeMode.batchAdd) {
          final initial = Game(path: folder.path, title: info.title);
          final gameId = await repo.insertGame(initial);
          await GameDataPaths.ensureDataDir(folder.path);
          await GameDataPaths.metadataFile(folder.path).writeAsString(
              jsonEncode(ScrapeApplyService.markScraped(info.toJson())));
          game = await ScrapeApplyService.translateGameMetadata(
            game: initial.copyWith(id: gameId),
            repo: repo,
            tagRepo: tagRepo,
            onNotice: notices.add,
          );
          game = await ScrapeApplyService.organizeFolder(
              game, mode, repo, configs);
        } else {
          game = await ScrapeApplyService.applyScrapeResult(
            game: Game(path: folder.path),
            gameInfo: info,
            mode: mode,
            repo: repo,
            tagRepo: tagRepo,
            configs: configs,
            onTranslationNotice: notices.add,
          );
        }
        expect(notices, isEmpty);
        expect(path.basename(path.dirname(game.path)),
            mode == ScrapeMode.quickScrape ? 'ACT' : 'RPG');
        expect(game.title, '中:${info.title}');
        expect(game.intro, '中:Explore');
        final metadata = jsonDecode(
                await GameDataPaths.metadataFile(game.path).readAsString())
            as Map<String, dynamic>;
        expect(MetadataTranslationService.originalFrom(metadata)!['intro'],
            'Explore');
        expect(ScrapeApplyService.isScrapedMetadata(metadata), isTrue);
        displayGame = game;
      }
      expect(requests, 5);
      final selectedGame = displayGame!;
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 900));
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final theme = brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme();
        await tester.pumpWidget(ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(body: GameDetailDialog(game: selectedGame)),
          ),
        ));
        for (var attempt = 0;
            attempt < 100 && find.text('查看原文').evaluate().isEmpty;
            attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('查看原文'), findsOneWidget);
        await tester.tap(find.text('查看原文'));
        await tester.pumpAndSettle();
        expect(find.text('查看译文'), findsOneWidget);
        expect(find.text(selectedGame.title!.substring(2)), findsWidgets);
        await tester.tap(find.text('查看译文'));
        await tester.pumpAndSettle();
        expect(find.text(selectedGame.title!), findsWidgets);
        expect(requests, 5);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(body: SingleChildScrollView(child: MetadataTranslationSettings(
                config: config,
                onChanged: (_) {},
            ))),
          ),
        ));
        await tester.pumpAndSettle();
        final prompt = find.byWidgetPredicate((widget) => widget is TextField &&
            widget.decoration?.labelText == '翻译 Prompt（留空使用默认）');
        await tester.ensureVisible(prompt);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(prompt).controller!.text, isEmpty);
        expect(find.text(MetadataTranslationConfig.defaultPrompt), findsOneWidget);
        await capture('prompt-${brightness.name}');
        expect(find.byKey(const ValueKey('metadata-translation-test')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      final coverFile = File(path.join(selectedGame.path, 'cover.png'));
      Future<void> writeCover(Color color) async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
            const Rect.fromLTWH(0, 0, 1536, 864), Paint()..color = color);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1536, 864);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await coverFile.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
        image.dispose();
        picture.dispose();
      }

      await writeCover(AppTheme.errorColor);
      await repo.setGameImages(selectedGame.id!, [
        GameImage(
            gameId: selectedGame.id!, imagePath: coverFile.path, sortOrder: 0),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(settings),
          allGamesProvider.overrideWith((ref) async => [
                (await repo.getGameById(selectedGame.id!))!,
              ]),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            appBar: AppBar(actions: [
              Builder(
                  builder: (context) => IconButton(
                        tooltip: '调整封面画质',
                        icon: const Icon(Icons.settings),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              const Dialog(child: SettingsDialogContent()),
                        ),
                      )),
            ]),
            body: Consumer(builder: (context, ref, child) {
              return ref.watch(allGamesProvider).when(
                    data: (games) => GameListWidget(games: games),
                    error: (error, stackTrace) => Text(error.toString()),
                    loading: () => const CircularProgressIndicator(),
                  );
            }),
          ),
        ),
      ));
      final coverFinder = find.descendant(
          of: find.byType(GameListWidget), matching: find.byType(RawImage));
      for (var attempt = 0;
          attempt < 100 &&
              (coverFinder.evaluate().isEmpty ||
                  tester.widget<RawImage>(coverFinder.first).image == null);
          attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final beforeImage = tester.widget<RawImage>(coverFinder.first).image!;
      expect(beforeImage.width, 1536, reason: '默认使用原图分辨率');
      final originalCoverBytes = await coverFile.readAsBytes();
      final beforePixels = await beforeImage.toByteData();
      for (final memorySaving in [true, false]) {
        await tester.tap(find.byTooltip('调整封面画质'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('管理'));
        await tester.pumpAndSettle();
        final qualitySwitch = find.widgetWithText(SwitchListTile, '节省封面内存');
        await tester.ensureVisible(qualitySwitch);
        await tester.pumpAndSettle();
        expect(
            tester.widget<SwitchListTile>(qualitySwitch).value, !memorySaving);
        await tester.tap(
            find.descendant(of: qualitySwitch, matching: find.byType(Switch)));
        await tester.pumpAndSettle();
        expect(
            tester.widget<SwitchListTile>(qualitySwitch).value, memorySaving);
        final saved = jsonDecode(
            await File(path.join(temporary.path, 'settings.json'))
                .readAsString());
        expect(saved[AppSettings.coverMemorySavingKey], memorySaving);
        Navigator.of(tester.element(find.byType(SettingsDialogContent))).pop();
        await tester.pumpAndSettle();
        final expectedWidth = memorySaving ? 768 : 1536;
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (coverFinder.evaluate().isNotEmpty &&
              tester.widget<RawImage>(coverFinder.first).image?.width ==
                  expectedWidth) {
            break;
          }
        }
        expect(tester.widget<RawImage>(coverFinder.first).image!.width,
            expectedWidth);
        expect(await coverFile.readAsBytes(), originalCoverBytes);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text(selectedGame.title!).first);
      await tester.pumpAndSettle();
      expect(find.byType(GameDetailDialog), findsOneWidget);
      await writeCover(AppTheme.successColor);
      Navigator.of(tester.element(find.byType(GameDetailDialog))).pop();
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final afterPixels =
          await tester.widget<RawImage>(coverFinder.first).image!.toByteData();
      expect(afterPixels!.buffer.asUint8List().take(4).toList(),
          isNot(beforePixels!.buffer.asUint8List().take(4).toList()),
          reason: '关闭详情后同一路径的新封面必须重新解码');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final cleared = (await repo.getGameById(selectedGame.id!))!.copyWith(isCleared: true);
      await repo.updateGame(cleared);
      final backupService = ClearedMetadataBackupService();
      final backupFile = await backupService.save(cleared);
      final originalMetadata = await backupService.loadMetadata(cleared);
      await GameDataPaths.metadataFile(cleared.path).delete();
      await backupService.refresh(cleared);
      expect(await backupService.loadMetadata(cleared), originalMetadata);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
            child: MaterialApp(
              theme: brightness == Brightness.light ? AppTheme.lightTheme() : AppTheme.darkTheme(),
              home: Scaffold(body: GameDetailDialog(game: cleared)),
            ),
          ),
        ));
        for (var attempt = 0; attempt < 100 && find.text('查看原文').evaluate().isEmpty; attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('查看原文'), findsOneWidget);
        await tester.tap(find.text('查看原文'));
        await tester.pumpAndSettle();
        expect(find.text(cleared.title!.substring(2)), findsWidgets);
        expect(find.text('查看译文'), findsOneWidget);
        await capture('backup-original-${brightness.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      expect(requests, 5);
      expect(systemPrompts.every((prompt) => prompt.startsWith(MetadataTranslationConfig.defaultPrompt)), isTrue);
      expect(await backupFile.exists(), isTrue);
      logger.info('MergeReview',
          'token=sample-token https://example.test/path?api_key=sample-key');
      final diagnosticPath = path.join(temporary.path, 'diagnostics.zip');
      await logger.exportDiagnostics(diagnosticPath);
      final archive =
          ZipDecoder().decodeBytes(await File(diagnosticPath).readAsBytes());
      final logs = archive
          .where((file) => file.name.endsWith('.log'))
          .map((file) => utf8.decode(file.content as List<int>))
          .join('\n');
      expect(logs, contains('MetadataTranslation'));
      expect(logs, contains('ScrapeApply'));
      expect(logs, isNot(contains('sample-token')));
      expect(logs, isNot(contains('sample-key')));
      expect(
          await (await DatabaseHelper.database)
              .rawQuery('PRAGMA integrity_check'),
          [
            {'integrity_check': 'ok'}
          ]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await DatabaseHelper.close();
      await settings.flush();
      AppSettings.invalidateCache();
      await logger.flush();
      await server.close(force: true);
      final resolvedTemporary = path.normalize(path.absolute(temporary.path));
      if (!path.isWithin(path.normalize(path.absolute(Directory.systemTemp.path)), resolvedTemporary) ||
          !path.basename(resolvedTemporary).startsWith('hgm_merge_review_')) {
        throw StateError('临时目录超出验收范围');
      }
      final resolvedDataRoot = path.normalize(path.absolute(dataRoot));
      if (!path.isWithin(
              path.normalize(path.absolute(Directory.systemTemp.path)),
              resolvedDataRoot) ||
          !path.basename(resolvedDataRoot).startsWith('hgm_merge_review_data_')) {
        throw StateError('数据目录超出验收范围');
      }
      AppPaths.overrideRootDirForTesting(null);
      await dataDirectory.delete(recursive: true);
      await temporary.delete(recursive: true);
    }
  });
}
