import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/models/scrape_review_item.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/dlsite_service.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/services/scrape_review_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/ui/pages/games/game_detail_page.dart';
import 'package:hgame_manager/ui/pages/scraper/scrape_review_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Database database;
  late GameRepository repository;
  late TagRepository tagRepository;
  late AppSettings settings;
  late HttpServer server;
  late String imageUrl;
  const sourceUrl =
      'https://www.dlsite.com/maniax/work/=/product_id/RJ100001.html';
  final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+c1XcAAAAASUVORK5CYII=');

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hgm_dlsite_issue19_');
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createForTesting(database);
    repository = GameRepository(database: database);
    tagRepository = TagRepository(database: database);
    settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    await settings.setString('proxy_mode', 'none');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    imageUrl = 'http://127.0.0.1:${server.port}/cover.png';
    server.listen((request) async {
      if (request.uri.path == '/cover.png') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(imageBytes);
      } else {
        request.response.statusCode = 503;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await settings.flush();
    AppSettings.invalidateCache();
    await database.close();
    await temporary.delete(recursive: true);
  });

  Future<Game> createGame(
      {bool metadataOnlyIntro = false, String folderName = 'game'}) async {
    final folder = path.join(temporary.path, folderName);
    await GameDataPaths.ensureDataDir(folder);
    final images = await GameDataPaths.ensureImagesDir(folder);
    final placeholder = File(path.join(images.path, 'scrape_1.gif'));
    await placeholder.writeAsBytes([71, 73, 70, 56, 57, 97]);
    await GameDataPaths.metadataFile(folder).writeAsString(jsonEncode({
      'title': 'Saved title',
      'intro': 'Saved description',
      'intro_html': '<p>Saved description</p>',
      'image_urls': [
        'https://www.dlsite.com/images/web/home/no_img_main.gif',
      ],
      'source_url': sourceUrl,
    }));
    await GameDataPaths.sourceUrlFile(folder).writeAsString(sourceUrl);
    final game = Game(
      path: folder,
      title: 'Saved title',
      intro: metadataOnlyIntro ? null : 'Saved description',
      sourceUrl: sourceUrl,
      isFavorite: true,
      playDuration: 120,
    );
    final stored = game.copyWith(id: await repository.insertGame(game));
    await repository.setGameImages(stored.id!, [
      GameImage(gameId: stored.id!, imagePath: placeholder.path),
    ]);
    return (await repository.getGameById(stored.id!))!;
  }

  Future<Game> apply(Game game, GameInfo info, ScrapeMode mode) =>
      ScrapeApplyService.applyScrapeResult(
        game: game,
        gameInfo: info,
        mode: mode,
        repo: repository,
        tagRepo: tagRepository,
        configs: const ScrapeModeConfigs(configs: {}),
        sourceUrl: info.sourceUrl,
        requirePersistence: true,
      );

  GameInfo restricted() => GameInfo(
        title: 'Public title',
        sourceUrl: sourceUrl,
        isDlsiteUserOnly: true,
        screenshots: [imageUrl],
        tags: ['ADV', 'Public genre'],
      );

  for (final mode in ScrapeMode.values) {
    testWidgets('受限元数据保留与占位图片替换 ${mode.name}', (tester) async {
      final game = await createGame();
      final result = await apply(game, restricted(), mode);
      final metadata = jsonDecode(
          await GameDataPaths.metadataFile(game.path).readAsString());
      expect(metadata[GameInfo.dlsiteRestrictionKey], 'user_only');
      expect(ScrapeApplyService.isScrapedMetadata(metadata), isTrue);
      expect(metadata['intro'], 'Saved description');
      expect(metadata['intro_html'], '<p>Saved description</p>');
      expect(metadata['image_urls'], [imageUrl]);
      expect(result.intro, 'Saved description');
      expect(result.isFavorite, isTrue);
      expect(result.playDuration, 120);
      expect(result.tags.map((tag) => tag.name), contains('Public genre'));
      expect(result.images, hasLength(1));
      expect(
          await File(result.images.single.imagePath).readAsBytes(), imageBytes);
      expect(
          await File(path.join(
                  GameDataPaths.imagesDir(game.path).path, 'scrape_1.gif'))
              .exists(),
          isFalse);
      final reloaded = (await repository.getGameById(game.id!))!;
      expect(reloaded.intro, 'Saved description');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('元数据独有正文在下载图片后仍保留', (tester) async {
    final game = await createGame(metadataOnlyIntro: true);
    final result = await apply(game, restricted(), ScrapeMode.rescrape);
    expect(result.intro, 'Saved description');
    final metadata =
        jsonDecode(await GameDataPaths.metadataFile(game.path).readAsString());
    expect(metadata['intro_html'], '<p>Saved description</p>');
    expect(tester.takeException(), isNull);
  });

  testWidgets('正常重刮清除受限标记并替换正文', (tester) async {
    final game = await createGame();
    final partial = await apply(game, restricted(), ScrapeMode.rescrape);
    final result = await apply(
        partial,
        GameInfo(
          title: 'Normal title',
          description: 'Current description',
          descriptionHtml: '<p>Current description</p>',
          screenshots: [imageUrl],
          sourceUrl: sourceUrl,
        ),
        ScrapeMode.rescrape);
    final metadata =
        jsonDecode(await GameDataPaths.metadataFile(game.path).readAsString());
    expect(metadata.containsKey(GameInfo.dlsiteRestrictionKey), isFalse);
    expect(metadata['intro_html'], '<p>Current description</p>');
    expect(result.intro, 'Current description');
    expect(tester.takeException(), isNull);
  });

  testWidgets('仅 HTML 引用及同编号旧图保留并支持重复受限重刮', (tester) async {
    var game = await createGame();
    final images = GameDataPaths.imagesDir(game.path);
    final first = File(path.join(images.path, 'scrape_1.png'));
    final seventh = File(path.join(images.path, 'scrape_7.png'));
    await first.writeAsBytes([1, 2, 3]);
    await seventh.writeAsBytes([7, 8, 9]);
    final oldHtml = '<p>Saved description</p>'
        '<img src="${first.path.replaceAll('\\', '/')}">'
        '<img src="${seventh.path}">';
    await GameDataPaths.metadataFile(game.path).writeAsString(jsonEncode({
      'intro': 'Saved description',
      'intro_html': oldHtml,
    }));
    game = game.copyWith(
      features: '[图片:${first.path}]',
      changelog: '[图片:${seventh.path}]',
      guide: '[图片:${first.path}]',
    );
    await repository.updateGame(game);

    for (var attempt = 0; attempt < 2; attempt++) {
      game = await apply(game, restricted(), ScrapeMode.quickScrape);
      final metadata = jsonDecode(
          await GameDataPaths.metadataFile(game.path).readAsString());
      final html = metadata['intro_html'] as String;
      final preserved = await images
          .list()
          .where((entity) =>
              entity is File &&
              GameDataPaths.parseScrapeImageIndex(entity.path) == null)
          .toList();
      expect(preserved, hasLength(2));
      expect(html.contains('scrape_1.png'), isFalse);
      expect(html.contains('scrape_7.png'), isFalse);
      for (final entity in preserved) {
        expect(GameDataPaths.isManagedImageFileName(path.basename(entity.path)),
            isTrue);
        final bytes = await File(entity.path).readAsBytes();
        expect(bytes, anyOf(equals([1, 2, 3]), equals([7, 8, 9])));
        expect(html.replaceAll('\\', '/'),
            contains(entity.path.replaceAll('\\', '/')));
      }
      expect(game.features!.contains('scrape_1.png'), isFalse);
      expect(game.changelog!.contains('scrape_7.png'), isFalse);
      expect(game.guide!.contains('scrape_1.png'), isFalse);
      expect(await first.readAsBytes(), imageBytes);
      expect(await seventh.exists(), isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认直接入口失败也恢复旧图与引用', (tester) async {
    final game = await createGame();
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString(jsonEncode({
      'intro': game.intro,
      'intro_html': '<img src="${game.images.single.imagePath}">',
    }));
    final original = await metadataFile.readAsBytes();
    final info = restricted()
      ..screenshots = ['http://127.0.0.1:${server.port}/missing.png'];
    await expectLater(
        ScrapeApplyService.applyScrapeResult(
          game: game,
          gameInfo: info,
          mode: ScrapeMode.quickScrape,
          repo: repository,
          tagRepo: tagRepository,
          configs: const ScrapeModeConfigs(configs: {}),
        ),
        throwsA(isA<StateError>()));
    expect(await metadataFile.readAsBytes(), original);
    final files = await GameDataPaths.imagesDir(game.path).list().toList();
    expect(files, hasLength(1));
    expect(files.single.path, game.images.single.imagePath);
    expect((await repository.getGameById(game.id!))!.title, game.title);
    expect(tester.takeException(), isNull);
  });

  testWidgets('转义 HTML 路径保留原图而不是同编号新图', (tester) async {
    final game = await createGame(folderName: 'A&B');
    final image = File(
        path.join(GameDataPaths.imagesDir(game.path).path, 'scrape_1.png'));
    await image.writeAsBytes([3, 2, 1]);
    final escapedPath =
        const HtmlEscape().convert(image.path.replaceAll('\\', '/'));
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString(jsonEncode({
      'intro': 'Saved description',
      'intro_html': '<img src="$escapedPath">',
    }));
    await apply(game, restricted(), ScrapeMode.rescrape);
    final metadata = jsonDecode(await metadataFile.readAsString());
    final html = metadata['intro_html'] as String;
    final preserved = await GameDataPaths.imagesDir(game.path)
        .list()
        .where((entity) =>
            GameDataPaths.parseScrapeImageIndex(entity.path) == null)
        .toList();
    expect(preserved, hasLength(1));
    expect(
        html,
        contains(const HtmlEscape()
            .convert(preserved.single.path.replaceAll('\\', '/'))));
    expect(await File(preserved.single.path).readAsBytes(), [3, 2, 1]);
    expect(await image.readAsBytes(), imageBytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片失败完整恢复数据库与文件', (tester) async {
    final game = await createGame();
    final metadataFile = GameDataPaths.metadataFile(game.path);
    final original = await metadataFile.readAsBytes();
    final originalImage =
        await File(game.images.single.imagePath).readAsBytes();
    final info = restricted()
      ..screenshots = ['http://127.0.0.1:${server.port}/missing.png'];
    await expectLater(apply(game, info, ScrapeMode.scraperCenter),
        throwsA(isA<StateError>()));
    final result = (await repository.getGameById(game.id!))!;
    expect(result.title, game.title);
    expect(result.intro, game.intro);
    expect(result.images.single.imagePath, game.images.single.imagePath);
    expect(await metadataFile.readAsBytes(), original);
    expect(
        await File(game.images.single.imagePath).readAsBytes(), originalImage);
    expect(tester.takeException(), isNull);
  });

  testWidgets('元数据不可读取时不覆盖数据库或文件', (tester) async {
    final game = await createGame();
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString('invalid-json');
    await expectLater(apply(game, restricted(), ScrapeMode.rescrape),
        throwsA(isA<FormatException>()));
    expect(await metadataFile.readAsString(), 'invalid-json');
    expect((await repository.getGameById(game.id!))!.title, game.title);
    expect(tester.takeException(), isNull);
  });

  testWidgets('公开 API 失败不产生可写候选或已刮削标记', (tester) async {
    final game = await createGame();
    final metadataFile = GameDataPaths.metadataFile(game.path);
    final original = await metadataFile.readAsBytes();
    final service = DlsiteService(
        clientFactory: () async => MockClient((request) async {
              if (request.url.path.endsWith('product.json')) {
                return http.Response('unavailable', 503);
              }
              return http.Response(
                  '<h1 id="work_name">Public title</h1>'
                  '<section class="p-restricted"></section>',
                  200);
            }));
    expect(await service.fetchById('RJ100001'), isNull);
    expect(await metadataFile.readAsBytes(), original);
    expect((await repository.getGameById(game.id!))!.title, game.title);
    expect(tester.takeException(), isNull);
  });

  const responseFile = String.fromEnvironment('DLSITE_RESPONSE_FILE');
  if (const bool.fromEnvironment('DLSITE_LIVE_VERIFY') ||
      responseFile.isNotEmpty) {
    testWidgets('真实公开服务只检查结构与计数', (tester) async {
      final responses = responseFile.isEmpty
          ? <Map<String, dynamic>>[]
          : (jsonDecode(await File(responseFile).readAsString()) as List)
              .cast<Map<String, dynamic>>();
      final service = responseFile.isEmpty
          ? DlsiteService()
          : DlsiteService(
              clientFactory: () async => MockClient((request) async {
                    final id = request.url.queryParameters['workno'] ??
                        RegExp(r'(RJ\d+)')
                            .firstMatch(request.url.path)
                            ?.group(1);
                    final captured =
                        responses.singleWhere((entry) => entry['id'] == id);
                    final key = request.url.path.endsWith('product.json')
                        ? 'api'
                        : 'html';
                    return http.Response(captured[key] as String, 200,
                        headers: {'content-type': 'text/plain; charset=utf-8'});
                  }));
      for (final entry in {
        'RJ01684124': true,
        'RJ01622268': true,
        'RJ01678591': false,
      }.entries) {
        final info = await service.fetchById(entry.key);
        expect(info != null, isTrue, reason: entry.key);
        expect(info!.isDlsiteUserOnly, entry.value, reason: entry.key);
        expect(info.screenshots.isNotEmpty, isTrue, reason: entry.key);
        expect(info.tags.isNotEmpty, isTrue, reason: entry.key);
        expect(info.screenshots.any((url) => url.contains('no_img')), isFalse);
        if (entry.value) {
          expect(info.description == null, isTrue);
          expect(info.descriptionHtml == null, isTrue);
        } else {
          expect(info.description?.isNotEmpty == true, isTrue);
        }
        debugPrint('DLSITE_VERIFIED replay=${responseFile.isNotEmpty} '
            'id=${entry.key} restricted=${entry.value} '
            'images=${info.screenshots.length} tags=${info.tags.length} '
            'introLength=${info.description?.length ?? 0}');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('受限提示重开详情与确认弹窗 ${dark ? 'dark' : 'light'}', (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 1000));
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final game = await createGame();
      final updated = await apply(game, restricted(), ScrapeMode.quickScrape);
      final theme = dark ? AppTheme.darkTheme() : AppTheme.lightTheme();
      try {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(settings),
            gameRepositoryProvider.overrideWithValue(repository),
            tagRepositoryProvider.overrideWithValue(tagRepository),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(body: GameDetailDialog(game: updated)),
          ),
        ));
        final detailNotice =
            find.byKey(const ValueKey('dlsite-user-only-notice'));
        for (var attempt = 0;
            attempt < 100 && detailNotice.evaluate().isEmpty;
            attempt++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(detailNotice, findsOneWidget);
        await tester.ensureVisible(detailNotice);
        await tester.pumpAndSettle();
        final text = tester.widget<Text>(detailNotice);
        final foreground = text.style!.color!;
        final background =
            AppTheme.getSurfaceColor(tester.element(detailNotice));
        final high =
            foreground.computeLuminance() > background.computeLuminance()
                ? foreground
                : background;
        final low = high == foreground ? background : foreground;
        expect(
            (high.computeLuminance() + 0.05) / (low.computeLuminance() + 0.05),
            greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        await tester.binding.setSurfaceSize(const Size(900, 1000));
        final candidate = restricted()..screenshots = [];
        final item = ScrapeReviewItem(game: updated, candidate: candidate);
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: ScrapeReviewDialog(
            items: [item],
            configs: const ScrapeModeConfigs(configs: {}),
            service: ScrapeReviewService(
                repository: repository, tagRepository: tagRepository),
          )),
        ));
        await tester.pumpAndSettle();
        final reviewNotice = find.text(GameInfo.dlsiteUserOnlyNotice);
        expect(reviewNotice, findsOneWidget);
        await tester.ensureVisible(reviewNotice);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(reviewNotice).style?.color,
            AppTheme.getTextPrimary(tester.element(reviewNotice)));
        await tester.tap(find.byKey(const ValueKey('keep-review-item')));
        await tester.pumpAndSettle();
        expect(item.decision, ScrapeReviewDecision.keep);
        expect(item.applied, isFalse);
        expect(reviewNotice, findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}
