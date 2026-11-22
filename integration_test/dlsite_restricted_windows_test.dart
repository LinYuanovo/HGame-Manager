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
  late List<String> requestedTranslationTexts;
  late List<String> returnedTranslationTexts;
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
    requestedTranslationTexts = [];
    returnedTranslationTexts = [];
    server.listen((request) async {
      if (request.uri.path == '/cover.png') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(imageBytes);
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/chat/completions') {
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        final texts =
            (jsonDecode(body['messages'][1]['content'])['texts'] as List)
                .cast<String>();
        requestedTranslationTexts.addAll(texts);
        const translations = {
          'Public title': 'Translated public title',
          'Public genre': 'Localized category',
        };
        final translatedTexts =
            texts.map((text) => translations[text] ?? text).toList();
        returnedTranslationTexts.addAll(translatedTexts);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'content': jsonEncode({'texts': translatedTexts})
              },
            },
          ],
        }));
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

  testWidgets('受限导入遇到独立来源文件中的另一作品时保留原目录', (tester) async {
    final folder = path.join(temporary.path, 'unregistered');
    await GameDataPaths.ensureDataDir(folder);
    final source = GameDataPaths.sourceUrlFile(folder);
    final otherWork = sourceUrl.replaceFirst('RJ100001', 'RJ100002');
    await source.writeAsString(otherWork);
    final metadata = GameDataPaths.metadataFile(folder);
    await metadata
        .writeAsString(jsonEncode({'intro': 'Description for the other work'}));
    final before = await metadata.readAsBytes();

    await expectLater(
        apply(Game(path: folder), restricted(), ScrapeMode.singleAdd),
        throwsStateError);
    expect(await source.readAsString(), otherWork);
    expect(await metadata.readAsBytes(), before);
    expect(await repository.getGameByPath(folder), isNull);
  });

  testWidgets('受限重刮保留仅由磁盘特色或更新日志引用的图片', (tester) async {
    final game = await createGame();
    final images = GameDataPaths.imagesDir(game.path);
    final metadata = GameDataPaths.metadataFile(game.path);
    final previous =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    final oldBytes = {
      'features': [1, 2, 3],
      'changelog': [4, 5, 6]
    };
    for (final entry in oldBytes.entries.indexed) {
      final image = File(path.join(images.path, 'scrape_${entry.$1 + 1}.png'));
      await image.writeAsBytes(entry.$2.value);
      previous[entry.$2.key] = image.path;
    }
    await metadata.writeAsString(jsonEncode(previous));

    await apply(game, restricted(), ScrapeMode.rescrape);
    final saved =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    for (final entry in oldBytes.entries) {
      expect(await File(saved[entry.key] as String).readAsBytes(), entry.value,
          reason: entry.key);
    }
  });

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

  testWidgets('受限重刮保留翻译原文及独占图片', (tester) async {
    await settings.setString(
        'metadata_translation', jsonEncode({'enabled': false}));
    var game = await createGame();
    final images = GameDataPaths.imagesDir(game.path);
    final originalImage = File(path.join(images.path, 'scrape_7.png'));
    final originalImageBytes = [7, 8, 9];
    await originalImage.writeAsBytes(originalImageBytes);
    game = game.copyWith(intro: 'Translated description');
    await repository.updateGame(game);
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString(
        jsonEncode({
          'source_url': sourceUrl,
          'intro': 'Translated description',
          'intro_html': '<p>Translated description</p>',
          'translation': {
            'original': {
              'source_url': sourceUrl,
              'intro': 'Original description',
              'intro_html': '<p>Original description</p>'
                  '<img src="${originalImage.path.replaceAll('\\', '/')}">',
            },
            'provider': 'llm',
            'target_language': 'zh-CN',
            'translated_at': '2026-11-16T00:00:00.000',
          },
        }),
        flush: true);

    final result = await apply(game, restricted(), ScrapeMode.rescrape);
    final metadata =
        jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    expect(metadata['intro'], 'Translated description');
    expect(metadata['intro_html'], '<p>Translated description</p>');
    expect(metadata[GameInfo.dlsiteRestrictionKey], 'user_only');
    expect(metadata['translation'], isA<Map>());
    final translation = metadata['translation'] as Map<String, dynamic>;
    expect(translation['provider'], 'llm');
    expect(translation['target_language'], 'zh-CN');
    expect(translation['translated_at'], '2026-11-16T00:00:00.000');
    expect(translation['original'], isA<Map>());
    final original = translation['original'] as Map<String, dynamic>;
    expect(original['intro'], 'Original description');
    final preserved = await images
        .list()
        .where((entity) =>
            entity is File &&
            GameDataPaths.parseScrapeImageIndex(entity.path) == null)
        .toList();
    expect(preserved, hasLength(1));
    final preservedImage = preserved.single as File;
    expect(
        path.basenameWithoutExtension(preservedImage.path),
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')));
    expect(original['intro_html'],
        '<p>Original description</p><img src="${preservedImage.path.replaceAll('\\', '/')}">');
    expect(await preservedImage.readAsBytes(), originalImageBytes);
    expect(await originalImage.exists(), isFalse);
    expect(result.intro, 'Translated description');
    expect(result.images, hasLength(1));
    expect(
        await File(result.images.single.imagePath).readAsBytes(), imageBytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('受限重刮仅翻译新增公开字段并保留正文原文', (tester) async {
    await settings.setString(
        'metadata_translation',
        jsonEncode({
          'enabled': true,
          'provider': 'llm',
          'base_url': 'http://127.0.0.1:${server.port}/v1',
          'model': 'test',
        }));
    final game = (await createGame()).copyWith(
      title: 'Saved translated title',
      intro: 'Translated description',
      features: 'Translated features',
      changelog: 'Translated changelog',
    );
    await repository.updateGame(game);
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString(
        jsonEncode({
          'source_url': sourceUrl,
          'title': 'Saved translated title',
          'tags': ['Saved translated genre'],
          'intro': 'Translated description',
          'intro_html': '<p>Translated description</p>',
          'features': 'Translated features',
          'changelog': 'Translated changelog',
          'translation': {
            'original': {
              'source_url': sourceUrl,
              'title': 'Saved original title',
              'tags': ['Saved original genre'],
              'intro': 'Original description',
              'intro_html': '<p>Original description</p>',
              'features': 'Original features',
              'changelog': 'Original changelog',
            },
            'provider': 'llm',
            'target_language': 'zh-CN',
            'translated_at': '2026-11-16T00:00:00.000',
          },
        }),
        flush: true);
    final info = restricted()..tags = ['Public genre'];

    final result = await apply(game, info, ScrapeMode.rescrape);
    expect(requestedTranslationTexts,
        unorderedEquals(['Public title', 'Public genre']));
    expect(returnedTranslationTexts,
        unorderedEquals(['Translated public title', 'Localized category']));
    expect(result.title, 'Translated public title');
    expect(result.tags.map((tag) => tag.name), ['Localized category']);
    expect(result.intro, 'Translated description');
    expect(result.features, 'Translated features');
    expect(result.changelog, 'Translated changelog');
    final metadata = jsonDecode(await metadataFile.readAsString());
    expect(metadata['title'], 'Translated public title');
    expect(metadata['tags'], ['Localized category']);
    expect(metadata['intro'], 'Translated description');
    expect(metadata['intro_html'], '<p>Translated description</p>');
    expect(metadata[GameInfo.dlsiteRestrictionKey], 'user_only');
    final translation = metadata['translation'] as Map<String, dynamic>;
    expect(translation['provider'], 'llm');
    final original = translation['original'] as Map<String, dynamic>;
    expect(original['title'], 'Public title');
    expect(original['tags'], ['Public genre']);
    expect(original['intro'], 'Original description');
    expect(original['intro_html'], '<p>Original description</p>');
    expect(original['features'], 'Original features');
    expect(original['changelog'], 'Original changelog');
    expect(tester.takeException(), isNull);
  });

  testWidgets('受限刮削拒绝更换作品并保留已有数据', (tester) async {
    final game = await createGame();
    final tagId =
        await tagRepository.insertOrGetTag('Saved tag', Tag.typeCustom);
    await repository.addTagToGame(game.id!, tagId);
    final images = GameDataPaths.imagesDir(game.path);
    final originalImage = File(game.images.single.imagePath);
    final originalImageBytes = await originalImage.readAsBytes();
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString(
        jsonEncode({
          'title': game.title,
          'source_url': sourceUrl,
          'intro': game.intro,
          'intro_html': '<p>Saved description</p>'
              '<img src="${originalImage.path.replaceAll('\\', '/')}">',
        }),
        flush: true);
    final originalMetadata = await metadataFile.readAsBytes();
    final sourceFile = GameDataPaths.sourceUrlFile(game.path);
    final originalSource = await sourceFile.readAsBytes();
    final originalRecords = <String, Object>{};
    for (final table in ['games', 'tags', 'game_tag_relation', 'game_images']) {
      originalRecords[table] = await database.query(table);
    }
    final info = restricted()
      ..sourceUrl =
          'https://www.dlsite.com/maniax/work/=/product_id/RJ100002.html';

    await expectLater(
        apply(game, info, ScrapeMode.quickScrape), throwsA(isA<StateError>()));
    for (final entry in originalRecords.entries) {
      expect(await database.query(entry.key), entry.value, reason: entry.key);
    }
    expect(await metadataFile.readAsBytes(), originalMetadata);
    expect(await sourceFile.readAsBytes(), originalSource);
    final remainingImages = await images.list().toList();
    expect(remainingImages, hasLength(1));
    expect(remainingImages.single.path, originalImage.path);
    expect(await originalImage.readAsBytes(), originalImageBytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('受限重刮校验已有翻译原文的作品来源', (tester) async {
    const changedSource =
        'https://www.dlsite.com/maniax/work/=/product_id/RJ100002.html';
    final game = (await createGame()).copyWith(sourceUrl: changedSource);
    await repository.updateGame(game);
    final metadataFile = GameDataPaths.metadataFile(game.path);
    await metadataFile.writeAsString(jsonEncode({
      'source_url': changedSource,
      'intro': 'Translated description',
      'translation': {
        'original': {
          'source_url': sourceUrl,
          'intro': 'Original description',
        },
      },
    }));
    final before = await metadataFile.readAsBytes();
    final info = restricted()..sourceUrl = changedSource;
    await expectLater(
        apply(game, info, ScrapeMode.rescrape), throwsA(isA<StateError>()));
    expect(await metadataFile.readAsBytes(), before);
    expect((await repository.getGameById(game.id!))!.sourceUrl, changedSource);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同作品协议及语言参数变化仍可受限重刮', (tester) async {
    var game = await createGame();
    for (final alternateSourceUrl in [
      'http://www.dlsite.com/maniax/work/=/product_id/RJ100001.html?locale=en_US',
      'https://www.dlsite.com/maniax/work/=/product_id/RJ100001.html/?locale=ja_JP',
    ]) {
      final info = restricted()..sourceUrl = alternateSourceUrl;
      game = await apply(game, info, ScrapeMode.quickScrape);
      final metadata = jsonDecode(
          await GameDataPaths.metadataFile(game.path).readAsString());
      expect(game.sourceUrl, alternateSourceUrl);
      expect(game.intro, 'Saved description');
      expect(metadata['source_url'], alternateSourceUrl);
      expect(metadata['intro_html'], '<p>Saved description</p>');
      expect(metadata[GameInfo.dlsiteRestrictionKey], 'user_only');
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
      const proxyUrl = String.fromEnvironment('DLSITE_LIVE_PROXY');
      if (proxyUrl.isNotEmpty) {
        await settings.setString('proxy_mode', 'custom');
        await settings.setString('proxy_url', proxyUrl);
      }
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
