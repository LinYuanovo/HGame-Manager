import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/folder_move_progress.dart';
import 'package:hgame_manager/core/services/folder_transfer_service.dart';
import 'package:hgame_manager/core/services/game_move_service.dart';
import 'package:hgame_manager/core/utils/path_reference_rewriter.dart';
import 'package:path/path.dart' as path;

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

  @override
  Future<void> relocateGame({
    required int gameId,
    required String oldPath,
    required String newPath,
    Future<void> Function()? beforeCommit,
  }) async {
    await updateGamePath(gameId, newPath);
    await updateImagePaths(gameId, oldPath, newPath);
    final launcher = PathReferenceRewriter.relocateLocalPath(
        game?.gameLauncher, oldPath, newPath);
    if (launcher != game?.gameLauncher) {
      await updateGameLauncher(gameId, launcher, game!.launcherLocked);
    }
    final save = PathReferenceRewriter.relocateLocalPath(
        game?.savePath, oldPath, newPath);
    if (save != game?.savePath) await updateSavePath(gameId, save);
    await beforeCommit?.call();
  }

  @override
  Future<Game?> getGameById(int id) async => game;

  Game? storedGameByPath;

  @override
  Future<Game?> getStoredGameByPath(String path) async => storedGameByPath;

  bool failUpdatePath = false;
  int failUpdatePathTimes = 0;
  String failMessage = 'UNIQUE constraint failed: games.path';
  bool? sourceExistedDuringCommit;

  @override
  Future<void> updateGamePath(int id, String newPath) async {
    if (game != null) {
      sourceExistedDuringCommit = await Directory(game!.path).exists();
    }
    if (failUpdatePath || failUpdatePathTimes > 0) {
      if (failUpdatePathTimes > 0) failUpdatePathTimes--;
      throw Exception(failMessage);
    }
    path = newPath;
    updateGamePathCalls++;
  }

  @override
  Future<void> updateImagePaths(
      int gameId, String oldPrefix, String newPrefix) async {
    updateImagePathsCalls++;
    imagesOldPrefix = oldPrefix;
    imagesNewPrefix = newPrefix;
  }

  @override
  Future<void> updateGameLauncher(int id, String? launcher, bool locked) async {
    updateGameLauncherCalls++;
    launcherValue = launcher;
    launcherLockedValue = locked;
  }

  @override
  Future<void> updateSavePath(int gameId, String? savePath) async {
    updateSavePathCalls++;
    savePathValue = savePath;
  }

  @override
  Future<void> updateGame(Game game) async {
    updateGameCalls++;
    this.game = game;
  }
}

Future<void> _writeSampleFiles(Directory source) async {
  await source.create(recursive: true);
  await File(path.join(source.path, 'a.txt')).writeAsString('hello');
  await File(path.join(source.path, 'b.txt')).writeAsString('world!');
}

void main() {
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
  });
}
