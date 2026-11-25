import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/models/scrape_review_item.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/scrape_review_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/ui/pages/scraper/scrape_review_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色窄窗' : '浅色宽窗'}确认刮削先保留放弃再保存，关闭重开保持决定',
        (tester) async {
      final temporary =
          await Directory.systemTemp.createTemp('hgm_review_native_');
      sqfliteFfiInit();
      final database =
          await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await database.execute('PRAGMA foreign_keys = ON');
      await DatabaseHelper.createForTesting(database);
      final repository = GameRepository(database: database);
      final service = ScrapeReviewService(
          repository: repository,
          tagRepository: TagRepository(database: database));
      final settings = await AppSettings.loadFromFileForTest(
          path.join(temporary.path, 'settings.json'));
      await settings.setString('proxy_mode', 'none');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });
      late File oldImage;
      final items = <ScrapeReviewItem>[];
      final originals = <String, String>{};
      for (var index = 0; index < 2; index++) {
        final folder = path.join(temporary.path, 'game$index');
        await GameDataPaths.ensureDataDir(folder);
        final metadata = jsonEncode({'title': '原游戏$index', 'intro': '原简介'});
        await GameDataPaths.metadataFile(folder).writeAsString(metadata);
        originals[folder] = metadata;
        final game = Game(
            path: folder,
            title: '原游戏$index',
            intro: '原简介',
            isFavorite: true,
            playDuration: 60);
        final stored = game.copyWith(id: await repository.insertGame(game));
        if (index == 0) {
          final images = await GameDataPaths.ensureImagesDir(folder);
          oldImage = File(path.join(images.path, 'scrape_1.png'));
          await oldImage.writeAsBytes(base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+c1XcAAAAASUVORK5CYII='));
          await repository.setGameImages(stored.id!, [
            GameImage(gameId: stored.id!, imagePath: oldImage.path),
          ]);
        }
        items.add(ScrapeReviewItem(
            game: stored,
            candidate: GameInfo(
                title: '候选游戏$index',
                description: '候选简介',
                screenshots: index == 0
                    ? ['http://127.0.0.1:${server.port}/missing.png']
                    : [],
                sourceUrl: 'https://example.test/game$index',
                tags: ['新增标签'])));
      }
      final captureKey = GlobalKey();
      const evidencePath = String.fromEnvironment('RELEASE_REVIEW_EVIDENCE');
      Future<void> capture(String state) async {
        if (evidencePath.isEmpty) return;
        await tester.pump(const Duration(milliseconds: 300));
        final boundary = captureKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path.join(
                  evidencePath, 'review-${dark ? 'dark' : 'light'}-$state.png'))
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      try {
        await windowManager.ensureInitialized();
        await windowManager
            .setSize(dark ? const Size(900, 1100) : const Size(1440, 1000));
        await tester.binding.setSurfaceSize(
            dark ? const Size(760, 1000) : const Size(1440, 1000));
        await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(dark ? 1.25 : 1)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => Center(
                        child: TextButton(
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => ScrapeReviewDialog(
                                    items: items,
                                    configs:
                                        const ScrapeModeConfigs(configs: {}),
                                    service: service)),
                            child: const Text('打开确认'))))),
          ),
        ));
        await tester.tap(find.text('打开确认'));
        await tester.pumpAndSettle();
        final dialogSize = tester.getSize(find.byType(ScrapeReviewDialog));
        expect(dialogSize.width, dark ? 760 : 1440);
        for (final entry in originals.entries) {
          expect(await GameDataPaths.metadataFile(entry.key).readAsString(),
              entry.value);
        }
        await tester.tap(find.byKey(const ValueKey('keep-review-item')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('discard-review-item')));
        await tester.pumpAndSettle();
        await capture('decisions');
        await tester.tap(find.text('稍后继续'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开确认'));
        await tester.pumpAndSettle();
        expect(items[0].decision, ScrapeReviewDecision.keep);
        expect(items[1].decision, ScrapeReviewDecision.discard);
        for (final item in items) {
          expect((await repository.getGameById(item.game.id!))!.title,
              item.originalGame.title);
        }
        await tester.tap(find.byKey(const ValueKey('save-reviewed-results')));
        for (var attempt = 0;
            attempt < 100 && find.text('保留旧图').evaluate().isEmpty;
            attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('保留旧图'), findsOneWidget);
        expect(await oldImage.exists(), isTrue);
        await capture('old-images');
        await tester.tap(find.text(dark ? '保留旧图' : '删除旧图'));
        for (var attempt = 0;
            attempt < 100 && !items.first.applied;
            attempt++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(items.first.applied, isTrue);
        expect(items.last.applied, isFalse);
        final saved = (await repository.getGameById(items.first.game.id!))!;
        expect(saved.title, '候选游戏0');
        expect(saved.isFavorite, isTrue);
        expect(saved.playDuration, 60);
        expect(saved.tags.map((tag) => tag.name), contains('新增标签'));
        expect(await oldImage.exists(), dark);
        expect(saved.images.map((image) => image.imagePath),
            dark ? [oldImage.path] : <String>[]);
        expect(
            await GameDataPaths.metadataFile(items.last.game.path)
                .readAsString(),
            originals[items.last.game.path]);
        await capture('saved');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
        await server.close(force: true);
        await settings.flush();
        AppSettings.invalidateCache();
        await database.close();
        await temporary.delete(recursive: true);
      }
    });
  }
}
