import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/concurrent_image_downloader.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/widgets/game_list_widget.dart';

class _ImageRepository extends GameRepository {
  _ImageRepository(this.game);

  Game game;
  int nextImageId = 1;

  @override
  Future<Game?> getGameById(int id) async => game;

  @override
  Future<void> updateGame(Game updated) async => game = updated;

  @override
  Future<void> setGameImages(int gameId, List<GameImage> images) async {
    game = game.copyWith(
      images: images
          .map((image) => GameImage(
                id: nextImageId++,
                gameId: gameId,
                imagePath: image.imagePath,
                sortOrder: image.sortOrder,
              ))
          .toList(),
    );
  }
}

Future<List<int>> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawPaint(Paint());
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _expectCover(WidgetTester tester, int width, int height) async {
  final covers = find.descendant(
    of: find.byType(GameListWidget),
    matching: find.byType(RawImage),
  );
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final rendered = tester.widgetList<RawImage>(covers);
    if (rendered.any((cover) =>
        cover.image?.width == width && cover.image?.height == height)) {
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('列表封面未更新为 $width×$height');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final sharedApply in [true, false]) {
    testWidgets(sharedApply ? '共享刮削发布同路径图片后刷新可见封面' : '导入下载器 429 重试覆盖图片后刷新可见封面',
        (tester) async {
      final temporary =
          await Directory.systemTemp.createTemp('hgm_image_refresh_');
      final prefs = await AppSettings.loadFromFileForTest(
          path.join(temporary.path, 'settings.json'));
      final original = await _png(240, 160);
      final replacement = await _png(160, 100);
      var replaced = false;
      var retried = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (!sharedApply && replaced && !retried) {
          retried = true;
          request.response.statusCode = 429;
        } else {
          request.response.add(replaced ? replacement : original);
        }
        await request.response.close();
      });
      final repo =
          _ImageRepository(Game(id: 1, path: temporary.path, title: '封面刷新'));
      final url = 'http://127.0.0.1:${server.port}/cover.png';
      Future<void> download() async {
        if (sharedApply) {
          await ScrapeApplyService.downloadAndApplyImages(
              game: repo.game, repo: repo, imageUrls: [url], sourceUrl: url);
        } else {
          final paths = await ConcurrentImageDownloader.downloadAll(
              imageUrls: [url], saveDir: temporary.path);
          expect(paths, hasLength(1));
          await repo
              .setGameImages(1, [GameImage(gameId: 1, imagePath: paths[url]!)]);
        }
      }

      Widget view() => ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
            child: MaterialApp(
                home: Scaffold(body: GameListWidget(games: [repo.game]))),
          );
      try {
        await download();
        final originalPath = repo.game.images.single.imagePath;
        await tester.pumpWidget(view());
        await _expectCover(tester, 240, 160);
        replaced = true;
        await download();
        expect(repo.game.images.single.imagePath, originalPath);
        await tester.pumpWidget(view());
        await _expectCover(tester, 160, 100);
        if (!sharedApply) expect(retried, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await server.close(force: true);
        await prefs.flush();
        AppSettings.invalidateCache();
        imageCache.clear();
        imageCache.clearLiveImages();
        await temporary.delete(recursive: true);
      }
    }, skip: !Platform.isWindows);
  }
}
