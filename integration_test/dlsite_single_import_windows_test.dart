import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/dlsite_service.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/core/utils/proxy_client.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:hgame_manager/ui/pages/games/games_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const sourceUrl =
      'https://www.dlsite.com/maniax/work/=/product_id/RJ100001.html';
  const importLabel = '导入选中';
  late HttpServer server;
  late HttpOverrides? previousHttpOverrides;
  late _LoopbackHttpOverrides httpOverrides;
  late List<int> publicImageBytes;
  late List<int> savedImageBytes;
  late Directory temporary;
  late Directory folder;
  late Database database;
  late GameRepository repository;
  late TagRepository tagRepository;
  late AppSettings settings;
  late FilePickerPlatform previousPicker;
  late _DirectoryPicker picker;
  late _DlsiteService service;
  var publicImageStatus = HttpStatus.ok;
  var publicImageRequests = 0;

  String getImageUrl() => 'http://127.0.0.1:${server.port}/cover.png';

  setUpAll(() async {
    sqfliteFfiInit();
    publicImageBytes = await _png(AppTheme.successColor);
    savedImageBytes = await _png(AppTheme.warningColor);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/cover.png') {
        publicImageRequests++;
        request.response.statusCode = publicImageStatus;
        if (publicImageStatus == HttpStatus.ok) {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(publicImageBytes);
        }
      } else {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      }
      await request.response.close();
    });
    previousHttpOverrides = HttpOverrides.current;
    httpOverrides = _LoopbackHttpOverrides(server.port);
    HttpOverrides.global = httpOverrides;
  });

  tearDownAll(() async {
    closeAllClients();
    httpOverrides.close();
    HttpOverrides.global = previousHttpOverrides;
    await server.close(force: true);
  });

  setUp(() async {
    closeAllClients();
    publicImageStatus = HttpStatus.ok;
    publicImageRequests = 0;
    temporary = await Directory.systemTemp.createTemp('hgm_dlsite_single_');
    folder = Directory(path.join(temporary.path, 'RJ100001'));
    await GameDataPaths.ensureDataDir(folder.path);
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createForTesting(database);
    repository = GameRepository(database: database);
    tagRepository = TagRepository(database: database);
    settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    await settings.setString('proxy_mode', 'none');
    await settings.setString('metadata_translation', '{"enabled":false}');
    await settings.setString(AppSettings.scrapeModeConfigsKey, '{}');
    service = _DlsiteService(GameInfo(
      title: 'Public title',
      sourceUrl: sourceUrl,
      isDlsiteUserOnly: true,
      screenshots: [getImageUrl()],
      tags: ['ADV', 'Public genre'],
      maker: 'Public maker',
    ));
    previousPicker = FilePickerPlatform.instance;
    picker = _DirectoryPicker(folder.path);
    FilePickerPlatform.instance = picker;
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  tearDown(() async {
    FilePickerPlatform.instance = previousPicker;
    closeAllClients();
    await settings.flush();
    AppSettings.invalidateCache();
    await database.close();
    imageCache.clear();
    imageCache.clearLiveImages();
    final resolved = path.normalize(path.absolute(temporary.path));
    if (!path.isWithin(path.normalize(path.absolute(Directory.systemTemp.path)),
            resolved) ||
        !path.basename(resolved).startsWith('hgm_dlsite_single_')) {
      throw StateError('拒绝清理测试临时目录以外的路径');
    }
    await temporary.delete(recursive: true);
  });

  Future<Map<String, dynamic>> savePreviousMetadata() async {
    final images = await GameDataPaths.ensureImagesDir(folder.path);
    final image = File(path.join(images.path, 'manual_1.png'));
    await image.writeAsBytes(savedImageBytes, flush: true);
    final imagePath = image.path.replaceAll('\\', '/');
    final metadata = <String, dynamic>{
      'title': 'Saved title',
      'intro': 'Saved translated description',
      'intro_html': '<p>Saved translated description</p><img src="$imagePath">',
      'source_url': sourceUrl,
      'translation': {
        'provider': 'google',
        'original': {
          'title': 'Saved original title',
          'intro': 'Saved original description',
          'intro_html': '<p>Saved original description</p>',
          'tags': ['Original genre'],
        },
      },
    };
    await GameDataPaths.metadataFile(folder.path)
        .writeAsString(jsonEncode(metadata), flush: true);
    await GameDataPaths.sourceUrlFile(folder.path)
        .writeAsString(sourceUrl, flush: true);
    return metadata;
  }

  Future<void> importThroughUi(WidgetTester tester,
      {Future<void> Function()? handleImageCleanup}) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1440, 1000));
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      await tester.pump();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(settings),
        gameRepositoryProvider.overrideWithValue(repository),
        tagRepositoryProvider.overrideWithValue(tagRepository),
        dlsiteServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: const Scaffold(body: GamesPage()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(await repository.getStoredGameByPath(folder.path), isNull);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    Finder inside(Finder target) =>
        find.descendant(of: dialog, matching: target);
    await tester.tap(inside(find.byIcon(Icons.folder_open)));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(inside(find.text(folder.path)), findsOneWidget);
    await tester.enterText(inside(find.byType(TextField)), 'RJ100001');
    await tester.tap(inside(find.byIcon(Icons.search)));
    final result = inside(find.widgetWithText(ListTile, 'ID: RJ100001'));
    await _waitFor(tester, () => result.evaluate().isNotEmpty);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pump();
    final importButton =
        inside(find.widgetWithText(ElevatedButton, importLabel));
    expect(importButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(importButton).onPressed, isNotNull);
    await tester.tap(importButton);
    await tester.pump();
    await handleImageCleanup?.call();
    await _waitFor(
        tester,
        () =>
            service.requestedIds.isNotEmpty &&
            (dialog.evaluate().isEmpty ||
                (importButton.evaluate().isNotEmpty &&
                    tester.widget<ElevatedButton>(importButton).onPressed !=
                        null)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(service.requestedIds, ['RJ100001']);
    expect(publicImageRequests, greaterThan(0));
    expect(tester.takeException(), isNull);
  }

  Future<Game> expectImported(String intro) async {
    expect(await database.query('games'), hasLength(1));
    final game = (await repository.getStoredGameByPath(folder.path))!;
    expect(game.title, 'Public title');
    expect(game.intro, intro);
    expect(game.sourceUrl, sourceUrl);
    expect(game.tags.map((tag) => tag.name),
        containsAll(['ADV', 'Public genre', 'Public maker']));
    expect(game.images, hasLength(1));
    final image = File(game.images.single.imagePath);
    expect(path.isWithin(folder.path, image.path), isTrue);
    expect(path.basename(image.path), 'scrape_1.png');
    expect(await image.readAsBytes(), publicImageBytes);
    expect(await GameDataPaths.sourceUrlFile(folder.path).readAsString(),
        sourceUrl);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    return game;
  }

  testWidgets('单个添加受限作品图片失败时回滚并保留对话框', (tester) async {
    await savePreviousMetadata();
    final metadataFile = GameDataPaths.metadataFile(folder.path);
    final original = await metadataFile.readAsBytes();
    publicImageStatus = HttpStatus.serviceUnavailable;

    await importThroughUi(tester);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, importLabel), findsOneWidget);
    expect(await database.query('games'), isEmpty);
    expect(await database.query('game_images'), isEmpty);
    expect(await metadataFile.readAsBytes(), original);
    final metadata = jsonDecode(await metadataFile.readAsString());
    expect(metadata.containsKey(ScrapeApplyService.scrapedAtKey), isFalse);
    expect(metadata.containsKey(GameInfo.dlsiteRestrictionKey), isFalse);
    expect(await GameDataPaths.sourceUrlFile(folder.path).readAsString(),
        sourceUrl);
    final images = await GameDataPaths.imagesDir(folder.path).list().toList();
    expect(images, hasLength(1));
    expect(path.basename(images.single.path), 'manual_1.png');
    expect(await File(images.single.path).readAsBytes(), savedImageBytes);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('单个添加受限作品保留旧简介与翻译原文并更新图库', (tester) async {
    final previous = await savePreviousMetadata();

    await importThroughUi(tester);

    expect(find.byType(Dialog), findsNothing);
    await expectImported(previous['intro'] as String);
    final metadata = jsonDecode(
        await GameDataPaths.metadataFile(folder.path).readAsString());
    expect(metadata['intro'], previous['intro']);
    expect(metadata['intro_html'], previous['intro_html']);
    final translation = metadata['translation'] as Map;
    final original = translation['original'] as Map;
    final previousOriginal =
        (previous['translation'] as Map)['original'] as Map;
    expect(
        translation['provider'], (previous['translation'] as Map)['provider']);
    expect(original['intro'], previousOriginal['intro']);
    expect(original['intro_html'], previousOriginal['intro_html']);
    expect(original['title'], 'Public title');
    expect(original['tags'], ['ADV', 'Public genre']);
    expect(metadata['image_urls'], [getImageUrl()]);
    expect(metadata[GameInfo.dlsiteRestrictionKey], 'user_only');
    expect(ScrapeApplyService.isScrapedMetadata(metadata), isTrue);
    final oldImage = File(
        path.join(GameDataPaths.imagesDir(folder.path).path, 'manual_1.png'));
    expect(await oldImage.readAsBytes(), savedImageBytes);
    expect(find.textContaining(GameInfo.dlsiteUserOnlyNotice), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('单个添加普通作品仍通过共享管线成功导入', (tester) async {
    service.candidate = GameInfo(
      title: 'Public title',
      description: 'Current description',
      descriptionHtml: '<p>Current description</p>',
      sourceUrl: sourceUrl,
      screenshots: [getImageUrl()],
      tags: ['ADV', 'Public genre'],
      maker: 'Public maker',
    );

    await importThroughUi(tester);

    expect(find.byType(Dialog), findsNothing);
    await expectImported('Current description');
    final metadata = jsonDecode(
        await GameDataPaths.metadataFile(folder.path).readAsString());
    expect(metadata['intro'], 'Current description');
    expect(metadata['intro_html'], '<p>Current description</p>');
    expect(metadata['image_urls'], [getImageUrl()]);
    expect(metadata.containsKey(GameInfo.dlsiteRestrictionKey), isFalse);
    expect(ScrapeApplyService.isScrapedMetadata(metadata), isTrue);
    expect(find.textContaining(GameInfo.dlsiteUserOnlyNotice), findsNothing);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  for (final allMissing in [false, true]) {
    for (final deleteOld in [false, true]) {
      testWidgets(
          '单个添加${allMissing ? '全部缺图' : '取得新图'}后确认${deleteOld ? '删除' : '保留'}旧图',
          (tester) async {
        final imagesDir = await GameDataPaths.ensureImagesDir(folder.path);
        final oldImage = File(path.join(imagesDir.path, 'scrape_2.png'));
        await oldImage.writeAsBytes(savedImageBytes);
        if (allMissing) publicImageStatus = HttpStatus.notFound;

        await importThroughUi(tester, handleImageCleanup: () async {
          await _waitFor(tester, () => find.text('保留旧图').evaluate().isNotEmpty);
          expect(await oldImage.readAsBytes(), savedImageBytes);
          await tester.tap(find.text(deleteOld ? '删除旧图' : '保留旧图'));
          await tester.pump();
        });

        expect(find.byType(Dialog), findsNothing);
        final game = (await repository.getStoredGameByPath(folder.path))!;
        expect(game.images.map((image) => path.basename(image.imagePath)), [
          if (!allMissing) 'scrape_1.png',
          if (!deleteOld) 'scrape_2.png',
        ]);
        expect(await oldImage.exists(), !deleteOld);
        if (!deleteOld) {
          expect(await oldImage.readAsBytes(), savedImageBytes);
        }
        final metadata = jsonDecode(
            await GameDataPaths.metadataFile(folder.path).readAsString());
        expect(ScrapeApplyService.isScrapedMetadata(metadata), isTrue);
        expect(tester.takeException(), isNull);
      }, skip: !Platform.isWindows);
    }
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: '等待单个添加界面操作完成超时');
}

Future<List<int>> _png(Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class _DlsiteService extends DlsiteService {
  GameInfo candidate;
  final requestedIds = <String>[];

  _DlsiteService(this.candidate);

  @override
  Future<GameInfo?> fetchById(String id) async {
    requestedIds.add(id);
    expect(id, 'RJ100001');
    return candidate;
  }
}

class _DirectoryPicker extends FilePickerPlatform {
  final String folder;
  int calls = 0;

  _DirectoryPicker(this.folder);

  @override
  Future<String?> getDirectoryPath(
      {String? dialogTitle,
      bool lockParentWindow = false,
      String? initialDirectory}) async {
    calls++;
    return folder;
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {
  final int port;
  final _clients = <HttpClient>[];

  _LoopbackHttpOverrides(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => uri.host == '127.0.0.1' && uri.port == port
        ? 'DIRECT'
        : 'PROXY 127.0.0.1:$port';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if ((proxyHost ?? uri.host) != '127.0.0.1' ||
          (proxyPort ?? uri.port) != port) {
        throw StateError('测试禁止连接非本地服务器');
      }
      return Socket.startConnect(InternetAddress.loopbackIPv4, port);
    };
    _clients.add(client);
    return client;
  }

  void close() {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
