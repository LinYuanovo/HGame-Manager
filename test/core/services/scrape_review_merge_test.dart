import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/models/scrape_review_item.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/cleared_metadata_backup_service.dart';
import 'package:hgame_manager/core/services/game_tag_edit_service.dart';
import 'package:hgame_manager/core/services/scrape_review_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporary;
  late Database database;
  late GameRepository repository;
  late ScrapeReviewService service;
  late AppSettings settings;
  const configs = ScrapeModeConfigs(configs: {});

  WidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hgm_merge_regression_');
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createForTesting(database);
    repository = GameRepository(database: database);
    service = ScrapeReviewService(
        repository: repository,
        tagRepository: TagRepository(database: database));
    settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    await settings.setString('proxy_mode', 'none');
  });

  tearDown(() async {
    await settings.flush();
    AppSettings.invalidateCache();
    await database.close();
    await temporary.delete(recursive: true);
  });

  Future<Game> createGame({bool stored = true, bool cleared = false}) async {
    final folder = path.join(temporary.path, 'game');
    await GameDataPaths.ensureDataDir(folder);
    await GameDataPaths.metadataFile(folder)
        .writeAsString(jsonEncode({'title': '原资料', 'intro': '原简介'}));
    final game = Game(
        path: folder,
        title: '原资料',
        intro: '原简介',
        isCleared: cleared,
        playDuration: 60,
        isFavorite: true,
        rating: 4);
    return stored ? game.copyWith(id: await repository.insertGame(game)) : game;
  }

  ScrapeReviewItem candidate(Game game) => ScrapeReviewItem(
      game: game,
      mode: ScrapeMode.batchAdd,
      candidate: GameInfo(
          title: '候选标题',
          description: '候选简介',
          sourceUrl: 'https://example.test/game'))
    ..decision = ScrapeReviewDecision.keep;

  test('新游戏在确认前已由其他入口入库时保留已有资料并拒绝覆盖', () async {
    final game = await createGame(stored: false);
    final item = candidate(game);
    final id = await repository.insertGame(game.copyWith(title: '同期入库'));
    final original = await GameDataPaths.metadataFile(game.path).readAsString();
    await expectLater(service.apply(item, configs),
        throwsA(isA<GameAlreadyExistsException>()));
    expect((await repository.getGameById(id))!.title, '同期入库');
    expect(
        await GameDataPaths.metadataFile(game.path).readAsString(), original);
    expect(item.applied, isFalse);
  });

  test('已入库游戏路径变化后要求重新确认，旧候选不写入新目录', () async {
    final game = await createGame();
    final item = candidate(game);
    final destination = path.join(temporary.path, 'moved');
    await Directory(game.path).rename(destination);
    await repository.updateGamePath(game.id!, destination);
    await expectLater(service.apply(item, configs), throwsA(isA<StateError>()));
    expect((await repository.getGameById(game.id!))!.title, '原资料');
    expect(
        jsonDecode(await GameDataPaths.metadataFile(destination)
            .readAsString())['title'],
        '原资料');
  });

  test('审核保存跳过 404 和 410，缺图后的配图与正文仍然对应', () async {
    final game = await createGame(stored: false);
    final item = candidate(game);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      switch (request.uri.path) {
        case '/missing.jpg':
          request.response.statusCode = 404;
        case '/gone.jpg':
          request.response.statusCode = 410;
        default:
          request.response.add([request.uri.path == '/first.jpg' ? 1 : 4]);
      }
      await request.response.close();
    });
    final urls = ['first', 'missing', 'gone', 'last']
        .map((name) => 'http://127.0.0.1:${server.port}/$name.jpg')
        .toList();
    item.candidate!
      ..screenshots = urls
      ..description = '[图片:${urls.last}]';
    await service.apply(item, configs);

    expect(item.applied, isTrue);
    final saved = (await repository.getGameByPath(game.path))!;
    final files = saved.images.map((image) => File(image.imagePath)).toList();
    expect(files.map((file) => path.basename(file.path)),
        ['scrape_1.jpg', 'scrape_4.jpg']);
    expect(await files.first.readAsBytes(), [1]);
    expect(await files.last.readAsBytes(), [4]);
    final metadata =
        jsonDecode(await GameDataPaths.metadataFile(game.path).readAsString());
    expect(metadata['scraped_at'], isNotEmpty);
    expect(metadata['intro'], '[图片:${files.last.path}]');
    expect(saved.intro, metadata['intro']);
    expect(item.notices.any((notice) => notice.contains('跳过')), isTrue);
  });

  test('图片返回 503 时恢复旧资料、标签和文件，保留同期游玩时长', () async {
    final game = await createGame();
    final item = candidate(game);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await database.update('games', {'play_duration': 120},
          where: 'id = ?', whereArgs: [game.id]);
      request.response.statusCode =
          request.uri.path == '/missing.png' ? 404 : 503;
      await request.response.close();
    });
    item.candidate!.screenshots = [
      'http://127.0.0.1:${server.port}/missing.png',
      'http://127.0.0.1:${server.port}/unavailable.png',
    ];
    final original = await GameDataPaths.metadataFile(game.path).readAsString();
    await expectLater(service.apply(item, configs), throwsA(isA<StateError>()));
    final current = (await repository.getGameById(game.id!))!;
    expect(current.title, '原资料');
    expect(current.playDuration, 120);
    expect(current.isFavorite, isTrue);
    expect(
        await GameDataPaths.metadataFile(game.path).readAsString(), original);
  });

  test('标签编辑使用旧视图时保留同期游玩状态', () async {
    final game = await createGame();
    await database.update('games', {'play_duration': 120, 'play_count': 3},
        where: 'id = ?', whereArgs: [game.id]);
    final updated = await GameTagEditService(repository: repository)
        .saveTags(game, [Tag(name: '新增标签', type: Tag.typeCustom)]);
    expect(updated.playDuration, 120);
    expect(updated.playCount, 3);
    expect(updated.tags.map((tag) => tag.name), contains('新增标签'));
  });

  test('删除本体后编辑资料同步通关备份展示，原文快照仍保留', () async {
    final game = await createGame(cleared: true);
    final backup = ClearedMetadataBackupService(
        backupDirectory: path.join(temporary.path, 'backups'));
    await GameDataPaths.metadataFile(game.path).writeAsString(jsonEncode({
      'title': '原资料',
      'intro': '原简介',
      'intro_html': '<p>原简介</p>',
      'translation': {
        'original': {'title': 'Original', 'intro': 'Original body'}
      }
    }));
    await backup.save(game);
    await Directory(game.path).delete(recursive: true);
    await GameTagEditService(
            repository: repository, clearedMetadataBackupService: backup)
        .saveTags(game.copyWith(title: '编辑标题', intro: '编辑简介'), [],
            metadataChanges: {
          'title': '编辑标题',
          'intro': '编辑简介',
          'intro_html': '<p>编辑简介</p>'
        });
    final metadata = (await backup.loadMetadata(game))!;
    expect(metadata['title'], '编辑标题');
    expect(metadata['intro_html'], '<p>编辑简介</p>');
    expect(metadata['translation']['original']['title'], 'Original');
  });

  test('通关详情使用图片备份目录展示时，编辑保持原数据库路径', () async {
    final game = await createGame(cleared: true);
    final imageBackup =
        await Directory(path.join(temporary.path, 'Backup', 'game'))
            .create(recursive: true);
    await database.update('games', {'cleared_backup_path': imageBackup.path},
        where: 'id = ?', whereArgs: [game.id]);
    final backup = ClearedMetadataBackupService(
        backupDirectory: path.join(temporary.path, 'backups'));
    await backup.save(game);
    await Directory(game.path).delete(recursive: true);
    final displayed = (await repository.getGameById(game.id!))!;
    expect(displayed.path, imageBackup.path);
    await GameTagEditService(
            repository: repository, clearedMetadataBackupService: backup)
        .saveTags(displayed.copyWith(title: '备份显示后编辑'), [],
            metadataChanges: {'title': '备份显示后编辑'});
    expect(await repository.getStoredGamePath(game.id!), game.path);
    expect((await backup.loadMetadata(game))!['title'], '备份显示后编辑');
    expect(await imageBackup.list().isEmpty, isTrue);
  });
}
