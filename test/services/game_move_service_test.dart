import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/folder_move_progress.dart';
import 'package:hgame_manager/core/services/folder_transfer_service.dart';
import 'package:hgame_manager/core/services/game_move_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';

class _FakeGameRepository extends GameRepository {
  _FakeGameRepository({this.game});

  Game? game;
  String? path;
  int updateGamePathCalls = 0;
  int updateImagePathsCalls = 0;
  String? imagesOldPrefix;
  String? imagesNewPrefix;
  int updateGameLauncherCalls = 0;
  String? launcherValue;
  bool? launcherLockedValue;
  int updateSavePathCalls = 0;
  String? savePathValue;
  int updateGameCalls = 0;
  Game? storedGameByPath;
  bool failUpdatePath = false;
  int failUpdatePathTimes = 0;
  bool failAfterMetadata = false;
  String failMessage = 'UNIQUE constraint failed: games.path';
  bool? sourceExistedDuringCommit;

  @override
  Future<Game?> getGameById(int id) async => game;

  @override
  Future<Game?> getStoredGameByPath(String path) async => storedGameByPath;

  @override
  Future<void> moveGameRecords({
    required int gameId,
    required String oldPath,
    required String newPath,
    Future<void> Function()? beforeCommit,
  }) async {
    final current = game!;
    sourceExistedDuringCommit = await Directory(current.path).exists();
    if (failUpdatePath || failUpdatePathTimes > 0) {
      if (failUpdatePathTimes > 0) failUpdatePathTimes--;
      throw Exception(failMessage);
    }
    await beforeCommit?.call();
    if (failAfterMetadata) throw Exception('模拟事务提交失败');
    path = newPath;
    updateGamePathCalls++;
    updateImagePathsCalls++;
    imagesOldPrefix = oldPath;
    imagesNewPrefix = newPath;
    if (current.gameLauncher?.startsWith(oldPath) == true) {
      updateGameLauncherCalls++;
      launcherValue =
          '$newPath${current.gameLauncher!.substring(oldPath.length)}';
      launcherLockedValue = current.launcherLocked;
    }
    if (current.savePath?.startsWith(oldPath) == true) {
      updateSavePathCalls++;
      savePathValue = '$newPath${current.savePath!.substring(oldPath.length)}';
    }
    game = current.copyWith(
        path: newPath,
        gameLauncher: launcherValue ?? current.gameLauncher,
        savePath: savePathValue ?? current.savePath);
  }
}

Future<void> _writeSampleFiles(Directory source) async {
  await source.create(recursive: true);
  await File(path.join(source.path, 'a.txt')).writeAsString('hello');
  await File(path.join(source.path, 'b.txt')).writeAsString('world!');
}

Future<Database> _createMoveDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''CREATE TABLE games (
    id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, title TEXT,
    intro TEXT, features TEXT, changelog TEXT, guide TEXT,
    game_launcher TEXT, save_path TEXT, launcher_locked INTEGER,
    is_favorite INTEGER, rating REAL, play_count INTEGER
  )''');
  await db.execute('''CREATE TABLE game_images (
    id INTEGER PRIMARY KEY, game_id INTEGER NOT NULL, image_path TEXT NOT NULL,
    sort_order INTEGER DEFAULT 0
  )''');
  await db.execute('''CREATE TABLE tags (
    id INTEGER PRIMARY KEY, name TEXT, type TEXT
  )''');
  await db.execute('''CREATE TABLE game_tag_relation (
    game_id INTEGER, tag_id INTEGER
  )''');
  return db;
}

Future<void> _insertMoveGame(Database db, String sourcePath) async {
  final image = path.join(sourcePath, 'HGMDatas', 'images', 'scrape_1.jpg');
  await db.insert('games', {
    'id': 7,
    'path': sourcePath,
    'title': '测试游戏',
    'intro': '[图片:$image]',
    'features': '示例路径：$image',
    'changelog': '<img src="$image">',
    'guide': '[攻略图片:$image]',
    'game_launcher': path.join(sourcePath, 'Game.exe'),
    'save_path': path.join(sourcePath, 'saves'),
    'launcher_locked': 1,
    'is_favorite': 1,
    'rating': 4.5,
    'play_count': 12,
  });
  await db.insert('game_images', {
    'id': 9,
    'game_id': 7,
    'image_path': image,
    'sort_order': 0,
  });
}

void main() {
  setUpAll(sqfliteFfiInit);
  group('GameMoveService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hgm_move_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('同卷移动成功后更新路径、图片、启动器与存档路径', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'target');
      final repo = _FakeGameRepository(
        game: Game(
          id: 7,
          path: source.path,
          gameLauncher: path.join(source.path, 'Game.exe'),
          launcherLocked: true,
          savePath: path.join(source.path, 'saves'),
        ),
      );
      final service = GameMoveService(gameRepository: repo);

      final result = await service.moveGameFolderCrossDrive(
        gameId: 7,
        oldPath: source.path,
        newPath: newPath,
      );

      expect(result, isA<FolderMoveResult>());
      expect(result.fileCount, 2);
      expect(await source.exists(), isFalse);
      expect(await Directory(newPath).exists(), isTrue);
      expect(
        await File(path.join(newPath, 'a.txt')).readAsString(),
        'hello',
      );
      expect(repo.path, newPath);
      expect(repo.updateGamePathCalls, 1);
      expect(repo.updateImagePathsCalls, 1);
      expect(repo.imagesOldPrefix, source.path);
      expect(repo.imagesNewPrefix, newPath);
      expect(repo.updateGameLauncherCalls, 1);
      expect(repo.launcherValue, path.join(newPath, 'Game.exe'));
      expect(repo.launcherLockedValue, isTrue);
      expect(repo.updateSavePathCalls, 1);
      expect(repo.savePathValue, path.join(newPath, 'saves'));
    });

    test('目标目录已存在时抛错且不写数据库', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'occupied');
      await Directory(newPath).create(recursive: true);
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path));
      final service = GameMoveService(gameRepository: repo);

      await expectLater(
        service.moveGameFolderCrossDrive(
          gameId: 7,
          oldPath: source.path,
          newPath: newPath,
        ),
        throwsA(isA<Exception>()),
      );

      expect(repo.path, isNull);
      expect(repo.updateGamePathCalls, 0);
      expect(repo.updateImagePathsCalls, 0);
      expect(repo.updateGameLauncherCalls, 0);
      expect(repo.updateSavePathCalls, 0);
      expect(repo.updateGameCalls, 0);
    });

    test('传输校验失败时抛错且不写数据库、保留源目录', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'broken');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path));
      final transfer = FolderTransferService(
        forceCopy: true,
        retryDelays: const [],
        onAfterCopy: (directory) async {
          await File(path.join(directory.path, 'a.txt')).writeAsBytes(
            const [],
          );
        },
      );
      final service = GameMoveService(
        gameRepository: repo,
        transfer: transfer,
      );

      await expectLater(
        service.moveGameFolderCrossDrive(
          gameId: 7,
          oldPath: source.path,
          newPath: newPath,
        ),
        throwsA(isA<FolderMoveException>()),
      );

      expect(await source.exists(), isTrue);
      expect(await File(path.join(source.path, 'a.txt')).exists(), isTrue);
      expect(await Directory(newPath).exists(), isFalse);
      expect(repo.path, isNull);
      expect(repo.updateGamePathCalls, 0);
      expect(repo.updateImagePathsCalls, 0);
      expect(repo.updateGameCalls, 0);
    });

    test('目标路径已被其他游戏占用时拒绝移动且源目录不变', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'occupied_by_other');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path))
        ..storedGameByPath = Game(id: 9, path: newPath);
      final service = GameMoveService(gameRepository: repo);

      await expectLater(
        service.moveGameFolderCrossDrive(
          gameId: 7,
          oldPath: source.path,
          newPath: newPath,
        ),
        throwsA(
          isA<FolderMoveException>().having(
            (e) => e.message,
            'message',
            contains('已被其他游戏占用'),
          ),
        ),
      );

      expect(await source.exists(), isTrue);
      expect(await Directory(newPath).exists(), isFalse);
      expect(repo.updateGamePathCalls, 0);
    });

    test('写库失败时自动回滚，源目录保持原样', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'db_fail');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path))
        ..failUpdatePath = true;
      final service = GameMoveService(gameRepository: repo);

      Object? error;
      try {
        await service.moveGameFolderCrossDrive(
          gameId: 7,
          oldPath: source.path,
          newPath: newPath,
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<FolderMoveException>());
      final failure = error as FolderMoveException;
      expect(failure.filesMoved, isFalse, reason: '回滚成功后文件仍在源目录');
      expect(failure.message, contains('数据库记录更新失败'));
      expect(await source.exists(), isTrue, reason: '源目录必须保留');
      expect(
        await File(path.join(source.path, 'a.txt')).readAsString(),
        'hello',
      );
      expect(await Directory(newPath).exists(), isFalse, reason: '目标副本必须清理');
      expect(repo.updateGamePathCalls, 0);
    });

    test('跨卷复制时写库发生在删除源目录之前', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'target');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path));
      final service = GameMoveService(
        gameRepository: repo,
        transfer: FolderTransferService(forceCopy: true),
      );

      await service.moveGameFolderCrossDrive(
        gameId: 7,
        oldPath: source.path,
        newPath: newPath,
      );

      expect(repo.sourceExistedDuringCommit, isTrue,
          reason: '写库时源目录必须仍然存在，才能保证失败可回滚');
      expect(await source.exists(), isFalse);
    });

    test('数据库瞬时锁定会重试后成功', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'retry_target');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path))
        ..failUpdatePathTimes = 1
        ..failMessage = 'database is locked';
      final service = GameMoveService(gameRepository: repo);

      await service.moveGameFolderCrossDrive(
        gameId: 7,
        oldPath: source.path,
        newPath: newPath,
      );

      expect(repo.updateGamePathCalls, 1);
      expect(repo.path, newPath);
      expect(await Directory(newPath).exists(), isTrue);
      expect(await source.exists(), isFalse);
    });

    test('取消移动时抛取消异常且不写数据库、保留源目录', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'cancelled');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path));
      final service = GameMoveService(
        gameRepository: repo,
        transfer: FolderTransferService(forceCopy: true),
      );

      await expectLater(
        service.moveGameFolderCrossDrive(
          gameId: 7,
          oldPath: source.path,
          newPath: newPath,
          shouldCancel: () => true,
        ),
        throwsA(isA<FolderMoveCancelledException>()),
      );

      expect(await source.exists(), isTrue);
      expect(
        await File(path.join(source.path, 'a.txt')).readAsString(),
        'hello',
      );
      expect(await Directory(newPath).exists(), isFalse);
      expect(repo.path, isNull);
      expect(repo.updateGamePathCalls, 0);
      expect(repo.updateImagePathsCalls, 0);
      expect(repo.updateGameCalls, 0);
    });

    test('启动器与存档路径不在旧目录下时不做改写', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      final newPath = path.join(tempDir.path, 'target');
      final repo = _FakeGameRepository(
        game: Game(
          id: 7,
          path: source.path,
          gameLauncher: r'C:\Elsewhere\Game.exe',
          launcherLocked: false,
          savePath: r'D:\Elsewhere\saves',
        ),
      );
      final service = GameMoveService(gameRepository: repo);

      await service.moveGameFolderCrossDrive(
        gameId: 7,
        oldPath: source.path,
        newPath: newPath,
      );

      expect(repo.updateGamePathCalls, 1);
      expect(repo.updateGameLauncherCalls, 0);
      expect(repo.launcherValue, isNull);
      expect(repo.launcherLockedValue, isNull);
      expect(repo.updateSavePathCalls, 0);
      expect(repo.savePathValue, isNull);
    });

    test('元数据替换后的提交失败会恢复原文件，再由搬运层恢复源目录', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      await GameDataPaths.ensureDataDir(source.path);
      final metadata = GameDataPaths.metadataFile(source.path);
      final original = jsonEncode({'intro': '[图片:${source.path}/cover.jpg]'});
      await metadata.writeAsString(original, flush: true);
      final target = path.join(tempDir.path, 'target');
      final repo = _FakeGameRepository(game: Game(id: 7, path: source.path))
        ..failAfterMetadata = true;

      await expectLater(
          GameMoveService(gameRepository: repo).moveGameFolderCrossDrive(
              gameId: 7, oldPath: source.path, newPath: target),
          throwsA(isA<FolderMoveException>()));

      expect(await source.exists(), isTrue);
      expect(await Directory(target).exists(), isFalse);
      expect(await metadata.readAsString(), original);
      expect(repo.game!.path, source.path);
      expect(repo.updateGamePathCalls, 0);
      expect(await GameDataPaths.dataDir(source.path).list().length, 1);
    });

    test('真实 SQLite 同卷移动完整更新引用，并保留收藏评分和游玩状态', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      await GameDataPaths.ensureDataDir(source.path);
      final metadata = GameDataPaths.metadataFile(source.path);
      await metadata.writeAsString(
          jsonEncode({
            'intro_html':
                '<img src="${source.path}/HGMDatas/images/scrape_1.jpg">',
            'translation': {
              'original': {'intro': source.path}
            },
          }),
          flush: true);
      final db = await _createMoveDatabase();
      addTearDown(db.close);
      await _insertMoveGame(db, source.path);
      final target = path.join(tempDir.path, 'target');

      await GameMoveService(gameRepository: GameRepository(database: db))
          .moveGameFolderCrossDrive(
              gameId: 7, oldPath: source.path, newPath: target);

      final saved = (await db.query('games')).single;
      expect(saved['path'], target);
      for (final field in ['intro', 'features', 'changelog', 'guide']) {
        expect(saved[field], contains(target));
        expect(saved[field], isNot(contains(source.path)));
      }
      expect(saved['game_launcher'], path.join(target, 'Game.exe'));
      expect(saved['save_path'], path.join(target, 'saves'));
      expect(saved['launcher_locked'], 1);
      expect(saved['is_favorite'], 1);
      expect(saved['rating'], 4.5);
      expect(saved['play_count'], 12);
      expect((await db.query('game_images')).single['image_path'],
          path.join(target, 'HGMDatas', 'images', 'scrape_1.jpg'));
      final updated =
          jsonDecode(await GameDataPaths.metadataFile(target).readAsString());
      expect(updated['intro_html'], contains(target));
      expect(updated['translation']['original']['intro'], target);
      expect(await source.exists(), isFalse);
      expect(await GameDataPaths.dataDir(target).list().length, 1);
    });

    for (final copy in [false, true]) {
      test('真实 SQLite 后段图片更新失败撤销记录与文件（${copy ? '跨卷复制' : '同卷移动'}）', () async {
        final source = Directory(path.join(tempDir.path, 'source'));
        await _writeSampleFiles(source);
        await GameDataPaths.ensureDataDir(source.path);
        final metadata = GameDataPaths.metadataFile(source.path);
        final original = jsonEncode({'intro': source.path});
        await metadata.writeAsString(original, flush: true);
        final db = await _createMoveDatabase();
        addTearDown(db.close);
        await _insertMoveGame(db, source.path);
        final initialGame = (await db.query('games')).single;
        final initialImages = await db.query('game_images');
        await db.execute('''CREATE TRIGGER fail_image_move
          BEFORE UPDATE ON game_images BEGIN
            SELECT RAISE(ABORT, '模拟图片记录更新失败');
          END''');
        final target = path.join(tempDir.path, 'target');

        await expectLater(
            GameMoveService(
              gameRepository: GameRepository(database: db),
              transfer: FolderTransferService(forceCopy: copy),
            ).moveGameFolderCrossDrive(
                gameId: 7, oldPath: source.path, newPath: target),
            throwsA(isA<FolderMoveException>()));

        expect((await db.query('games')).single, initialGame);
        expect(await db.query('game_images'), initialImages);
        expect(await metadata.readAsString(), original);
        expect(await File(path.join(source.path, 'a.txt')).readAsString(),
            'hello');
        expect(await Directory(target).exists(), isFalse);
        expect(await GameDataPaths.dataDir(source.path).list().length, 1);
      });
    }

    test('真实 SQLite 回调失败撤销整个事务，外部近似路径不被改写', () async {
      final db = await _createMoveDatabase();
      addTearDown(db.close);
      final source = path.join(tempDir.path, 'source');
      final target = path.join(tempDir.path, 'target');
      await _insertMoveGame(db, source);
      final outside = '${source}_other';
      await db.update('games', {
        'game_launcher': path.join(outside, 'Game.exe'),
        'save_path': path.join(outside, 'saves'),
      });
      final initial = (await db.query('games')).single;
      final repo = GameRepository(database: db);

      await expectLater(
          repo.moveGameRecords(
              gameId: 7,
              oldPath: source,
              newPath: target,
              beforeCommit: () async => throw StateError('模拟元数据替换失败')),
          throwsStateError);
      expect((await db.query('games')).single, initial);
      await repo.moveGameRecords(gameId: 7, oldPath: source, newPath: target);
      final saved = (await db.query('games')).single;
      expect(saved['game_launcher'], path.join(outside, 'Game.exe'));
      expect(saved['save_path'], path.join(outside, 'saves'));
    });

    test('真实 SQLite 在元数据替换后的 COMMIT 失败时恢复文件与全部记录', () async {
      final source = Directory(path.join(tempDir.path, 'source'));
      await _writeSampleFiles(source);
      await GameDataPaths.ensureDataDir(source.path);
      final metadata = GameDataPaths.metadataFile(source.path);
      final original = jsonEncode({'intro_html': source.path});
      await metadata.writeAsString(original, flush: true);
      final db = await _createMoveDatabase();
      addTearDown(db.close);
      await _insertMoveGame(db, source.path);
      final initial = (await db.query('games')).single;
      final initialImages = await db.query('game_images');
      await db.execute('''CREATE TABLE deferred_move_failure (
        game_id INTEGER REFERENCES games(id) DEFERRABLE INITIALLY DEFERRED
      )''');
      await db.execute('''CREATE TRIGGER fail_move_commit
        AFTER UPDATE ON game_images BEGIN
          INSERT INTO deferred_move_failure(game_id) VALUES(999);
        END''');
      final target = path.join(tempDir.path, 'target');

      await expectLater(
          GameMoveService(gameRepository: GameRepository(database: db))
              .moveGameFolderCrossDrive(
                  gameId: 7, oldPath: source.path, newPath: target),
          throwsA(isA<FolderMoveException>()));

      expect((await db.query('games')).single, initial);
      expect(await db.query('game_images'), initialImages);
      expect(await db.query('deferred_move_failure'), isEmpty);
      expect(await metadata.readAsString(), original);
      expect(await Directory(target).exists(), isFalse);
      expect(await source.exists(), isTrue);
      expect(await GameDataPaths.dataDir(source.path).list().length, 1);
    });

    test('真实 SQLite 已移动或已删除的记录不能用旧路径提交', () async {
      final db = await _createMoveDatabase();
      addTearDown(db.close);
      final source = path.join(tempDir.path, 'source');
      final target = path.join(tempDir.path, 'target');
      await _insertMoveGame(db, source);
      final repo = GameRepository(database: db);
      await db.update('games', {'path': '$source-moved'});

      await expectLater(
          repo.moveGameRecords(gameId: 7, oldPath: source, newPath: target),
          throwsStateError);
      expect((await db.query('games')).single['path'], '$source-moved');
      await db.delete('games');
      await expectLater(
          repo.moveGameRecords(gameId: 7, oldPath: source, newPath: target),
          throwsStateError);
      expect(await db.query('games'), isEmpty);
    });
  });
}
