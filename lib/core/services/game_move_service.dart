import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as path;
import '../repositories/game_repository.dart';

class GameMoveService {
  final GameRepository _gameRepository;

  GameMoveService({GameRepository? gameRepository})
      : _gameRepository = gameRepository ?? GameRepository();

  Future<String> moveGameFolder({
    required int gameId,
    required String oldPath,
    required String newPath,
  }) async {
    final oldDir = Directory(oldPath);
    final newDir = Directory(newPath);

    if (!oldDir.existsSync()) {
      throw Exception('源文件夹不存在: $oldPath');
    }

    if (newDir.existsSync()) {
      throw Exception('目标文件夹已存在: $newPath');
    }

    final parentDir = Directory(path.dirname(newPath));
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    debugPrint('[GameMove] Moving: $oldPath -> $newPath');

    await oldDir.rename(newPath);

    debugPrint('[GameMove] Folder moved successfully');

    await _gameRepository.updateGamePath(gameId, newPath);

    final game = await _gameRepository.getGameById(gameId);
    if (game != null && game.gameLauncher != null && game.gameLauncher!.startsWith(oldPath)) {
      final relativeLauncher = game.gameLauncher!.substring(oldPath.length);
      final newLauncher = '$newPath$relativeLauncher';
      await _gameRepository.updateGameLauncher(gameId, newLauncher, game.launcherLocked);
      debugPrint('[GameMove] Launcher path updated: $newLauncher');
    }

    if (game != null && game.savePath != null && game.savePath!.startsWith(oldPath)) {
      final relativeSave = game.savePath!.substring(oldPath.length);
      final newSave = '$newPath$relativeSave';
      await _gameRepository.updateSavePath(gameId, newSave);
      debugPrint('[GameMove] Save path updated: $newSave');
    }

    return newPath;
  }

  Future<String> moveGameFolderCrossDrive({
    required int gameId,
    required String oldPath,
    required String newPath,
  }) async {
    final oldDir = Directory(oldPath);
    final newDir = Directory(newPath);

    if (!oldDir.existsSync()) {
      throw Exception('源文件夹不存在: $oldPath');
    }

    if (newDir.existsSync()) {
      throw Exception('目标文件夹已存在: $newPath');
    }

    final parentDir = Directory(path.dirname(newPath));
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    debugPrint('[GameMove] Cross-drive move: $oldPath -> $newPath');

    try {
      await oldDir.rename(newPath);
      debugPrint('[GameMove] Rename succeeded');
    } catch (e) {
      debugPrint('[GameMove] Rename failed ($e), falling back to copy+delete');
      await _copyDirectory(oldDir, newDir);
      await oldDir.delete(recursive: true);
      debugPrint('[GameMove] Copy+delete succeeded');
    }

    await _gameRepository.updateGamePath(gameId, newPath);

    final game = await _gameRepository.getGameById(gameId);
    if (game != null && game.gameLauncher != null && game.gameLauncher!.startsWith(oldPath)) {
      final relativeLauncher = game.gameLauncher!.substring(oldPath.length);
      final newLauncher = '$newPath$relativeLauncher';
      await _gameRepository.updateGameLauncher(gameId, newLauncher, game.launcherLocked);
    }

    if (game != null && game.savePath != null && game.savePath!.startsWith(oldPath)) {
      final relativeSave = game.savePath!.substring(oldPath.length);
      final newSave = '$newPath$relativeSave';
      await _gameRepository.updateSavePath(gameId, newSave);
    }

    return newPath;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    await for (final entity in source.list()) {
      final newPath = path.join(destination.path, path.basename(entity.path));
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }
}
