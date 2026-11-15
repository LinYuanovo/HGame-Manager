import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/scraper/parse_utils.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporary;
  late Database database;
  late GameRepository repo;
  late TagRepository tagRepo;
  late AppSettings settings;
  late HttpServer server;
  late Game game;
  late File metadataFile;
  late String original;
  late int requests;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('hgm_translation_persistence_');
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createForTesting(database);
    repo = GameRepository(database: database);
    tagRepo = TagRepository(database: database);
    settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = 0;
    server.listen((request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      final texts =
          (jsonDecode(body['messages'][1]['content'])['texts'] as List)
              .cast<String>();
      const translations = {
        'Village': '村庄',
        'Explore': '探索',
        'Adventure': '冒险'
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': jsonEncode({
                'texts':
                    texts.map((text) => translations[text] ?? text).toList()
              })
            },
          }
        ],
      }));
      await request.response.close();
    });
    await settings.setString(
        MetadataTranslationConfig.settingsKey,
        jsonEncode(
          MetadataTranslationConfig(
                  enabled: true,
                  provider: 'llm',
                  baseUrl: 'http://127.0.0.1:${server.port}/v1',
                  model: 'test')
              .toMap(),
        ));
    await settings.setString('proxy_mode', 'none');
    final initial = Game(
        path: path.join(temporary.path, 'game'),
        title: 'Village',
        intro: 'Explore',
        rating: 4);
    game = initial.copyWith(id: await repo.insertGame(initial));
    await ScrapeApplyService.syncTags(repo, tagRepo, game.id!,
        GameInfo(sourceUrl: '', tags: ['Adventure'], category: 'RPG'));
    await GameDataPaths.ensureDataDir(game.path);
    metadataFile = GameDataPaths.metadataFile(game.path);
    original = const JsonEncoder.withIndent('  ').convert({
      'title': 'Village',
      'intro': 'Explore',
      'tags': ['Adventure'],
      'series': 'RPG'
    });
    await metadataFile.writeAsString(original);
  });

  tearDown(() async {
    await server.close(force: true);
    await settings.flush();
    AppSettings.invalidateCache();
    await database.close();
    final resolved = path.normalize(path.absolute(temporary.path));
    if (!path.isWithin(path.normalize(path.absolute(Directory.systemTemp.path)),
            resolved) ||
        !path.basename(resolved).startsWith('hgm_translation_persistence_')) {
      throw StateError('临时目录超出测试范围');
    }
    await temporary.delete(recursive: true);
  });

  Future<Game> translate({List<String>? notices}) =>
      ScrapeApplyService.translateGameMetadata(
        game: game,
        repo: repo,
        tagRepo: tagRepo,
        onNotice: notices?.add,
      );

  for (final failure in ['字段更新', '标签插入']) {
    test('$failure 失败回滚文件和全部数据库变更，解除故障后可重试', () async {
      if (failure == '标签插入') {
        await database.execute(
            '''CREATE TRIGGER fail_translation BEFORE INSERT ON game_tag_relation
          WHEN (SELECT name FROM tags WHERE id = NEW.tag_id) = '冒险'
          BEGIN SELECT RAISE(ABORT, '模拟标签失败'); END''');
      } else {
        await database
            .execute('''CREATE TRIGGER fail_translation BEFORE UPDATE ON games
          WHEN NEW.title = '村庄' BEGIN SELECT RAISE(ABORT, '模拟更新失败'); END''');
      }
      final notices = <String>[];
      await translate(notices: notices);
      expect(await metadataFile.readAsString(), original);
      final unchanged = (await repo.getGameById(game.id!))!;
      expect(unchanged.title, 'Village');
      expect(unchanged.tags.map((tag) => tag.name),
          unorderedEquals(['Adventure', 'ADV', 'RPG']));
      expect(await tagRepo.getTagByNameAndType('冒险', Tag.typeCustom), isNull);
      expect(notices, isNotEmpty);
      await database.execute('DROP TRIGGER fail_translation');
      final translated = await translate();
      expect(translated.title, '村庄');
      expect(translated.tags.map((tag) => tag.name),
          unorderedEquals(['冒险', 'RPG']));
      expect(translated.rating, 4);
      expect(
          jsonDecode(await metadataFile.readAsString())['translation']
              ['original'],
          jsonDecode(original));
    });
  }

  test('文件替换后事务失败时恢复原文件和数据库，随后可重试', () async {
    final failingRepo = _FailBeforeCommitRepository(database, metadataFile);
    repo = failingRepo;
    final notices = <String>[];
    await translate(notices: notices);
    expect(failingRepo.sawTranslatedFile, isTrue);
    expect(await metadataFile.readAsString(), original);
    final unchanged = (await repo.getGameById(game.id!))!;
    expect(unchanged.title, 'Village');
    expect(unchanged.tags.map((tag) => tag.name),
        unorderedEquals(['Adventure', 'ADV', 'RPG']));
    expect(await tagRepo.getTagByNameAndType('冒险', Tag.typeCustom), isNull);
    expect(notices, isNotEmpty);
    failingRepo.failBeforeCommit = false;
    expect((await translate()).title, '村庄');
  });

  test('翻译临时文件写入失败时保留数据库和原文件', () async {
    await Directory('${metadataFile.path}.translation.tmp').create();
    final notices = <String>[];
    await translate(notices: notices);
    expect(await metadataFile.readAsString(), original);
    expect((await repo.getGameById(game.id!))!.title, 'Village');
    expect(notices, isNotEmpty);
  });

  test('翻译文件替换后的真实 COMMIT 失败恢复原文且数据库可继续使用', () async {
    await database.execute('''CREATE TABLE deferred_translation_failure (
      game_id INTEGER REFERENCES games(id) DEFERRABLE INITIALLY DEFERRED
    )''');
    await database.execute('''CREATE TRIGGER fail_translation_commit
      AFTER UPDATE ON games WHEN NEW.title = '村庄' BEGIN
        INSERT INTO deferred_translation_failure(game_id) VALUES(999);
      END''');
    final notices = <String>[];
    await translate(notices: notices);
    expect(await metadataFile.readAsString(), original);
    expect((await repo.getGameById(game.id!))!.title, 'Village');
    expect(await database.query('deferred_translation_failure'), isEmpty);
    expect(notices, isNotEmpty);
    await database.execute('DROP TRIGGER fail_translation_commit');
    expect((await translate()).title, '村庄');
  });

  test('已有译文快照时补齐数据库和标签且不再次请求翻译', () async {
    await metadataFile.writeAsString(jsonEncode({
      'title': '村庄',
      'intro': '探索',
      'tags': ['冒险'],
      'series': 'RPG',
      'translation': {'original': jsonDecode(original), 'provider': 'llm'},
    }));
    final result = await translate();
    expect(result.title, '村庄');
    expect(result.tags.map((tag) => tag.name), unorderedEquals(['冒险', 'RPG']));
    expect(requests, 0);
  });

  test('自定义 Prompt 保存到设置文件并重新加载', () async {
    const prompt = '使用自然的中文。\n保留角色名字。';
    final saved = MetadataTranslationConfig.fromSettings(settings).toMap()
      ..['prompt'] = prompt;
    await settings.setString(
        MetadataTranslationConfig.settingsKey, jsonEncode(saved));
    await settings.flush();
    settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    expect(MetadataTranslationConfig.fromSettings(settings).effectivePrompt,
        prompt);
  });
}

class _FailBeforeCommitRepository extends GameRepository {
  final File metadataFile;
  bool failBeforeCommit = true;
  bool sawTranslatedFile = false;

  _FailBeforeCommitRepository(Database database, this.metadataFile)
      : super(database: database);

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action) =>
      super.transaction((transaction) async {
        final result = await action(transaction);
        if (failBeforeCommit) {
          sawTranslatedFile =
              jsonDecode(await metadataFile.readAsString())['title'] == '村庄';
          throw StateError('模拟文件替换后的事务失败');
        }
        return result;
      });
}
