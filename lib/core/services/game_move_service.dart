import 'dart:io';
import '../repositories/game_repository.dart';
import 'app_logger.dart';
import 'folder_move_progress.dart';
import 'folder_transfer_service.dart';
import 'game_data_migration_service.dart';

class GameMoveService {
  static const String _logTag = 'GameMove';
  static const List<Duration> _dbRetryDelays = [
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
  ];

  final GameRepository _gameRepository;
  final FolderTransferService _transfer;

  GameMoveService({
    GameRepository? gameRepository,
    FolderTransferService? transfer,
  })  : _gameRepository = gameRepository ?? GameRepository(),
        _transfer = transfer ?? FolderTransferService();

  Future<FolderMoveResult> moveGameFolderCrossDrive({
    required int gameId,
    required String oldPath,
    required String newPath,
    void Function(FolderMoveProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final oldDir = Directory(oldPath);
    final newDir = Directory(newPath);

    if (!await oldDir.exists()) {
      throw FolderMoveException('源文件夹不存在: $oldPath');
    }

    if (await newDir.exists()) {
      throw FolderMoveException('目标文件夹已存在: $newPath');
    }

    final occupied = await _gameRepository.getStoredGameByPath(newPath);
    if (occupied != null && occupied.id != gameId) {
      throw FolderMoveException('目标路径已被其他游戏占用: $newPath');
    }

    AppLogger.instance.info(_logTag, '开始移动游戏目录: $oldPath -> $newPath');

    final FolderMoveResult result;
    try {
      result = await _transfer.moveDirectory(
        source: oldDir,
        target: newDir,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
        commit: () => _updateGameRecords(
          gameId: gameId,
          oldPath: oldPath,
          newPath: newPath,
        ),
      );
    } on FolderMoveCancelledException {
      AppLogger.instance.warning(_logTag, '移动已取消: $oldPath -> $newPath');
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.instance.error(
        _logTag,
        '移动游戏目录失败: $oldPath -> $newPath',
        e,
        stackTrace,
      );
      rethrow;
    }

    if (result.warning != null) {
      AppLogger.instance.warning(_logTag, result.warning!);
    }

    AppLogger.instance.info(
      _logTag,
      '移动完成: $oldPath -> $newPath, 文件数=${result.fileCount}, '
      '字节数=${result.totalBytes}, 耗时=${result.elapsed.inMilliseconds}ms',
    );

    return result;
  }

  Future<void> _updateGameRecords({
    required int gameId,
    required String oldPath,
    required String newPath,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        await _applyGameRecords(
          gameId: gameId,
          oldPath: oldPath,
          newPath: newPath,
        );
        return;
      } catch (e, stackTrace) {
        AppLogger.instance.error(
          _logTag,
          '数据库记录更新失败（第 ${attempt + 1} 次）: $oldPath -> $newPath',
          e,
          stackTrace,
        );
        if (attempt >= _dbRetryDelays.length || !_isTransientDbError(e)) {
          throw FolderMoveException('数据库记录更新失败：${_describeDbError(e)}');
        }
        await Future<void>.delayed(_dbRetryDelays[attempt]);
        attempt++;
      }
    }
  }

  Future<void> _applyGameRecords({
    required int gameId,
    required String oldPath,
    required String newPath,
  }) async {
    await _gameRepository.updateGamePath(gameId, newPath);
    await _gameRepository.updateImagePaths(gameId, oldPath, newPath);
    await GameDataMigrationService(gameRepository: _gameRepository)
        .rewriteGamePathReferences(
      gameId: gameId,
      oldPath: oldPath,
      newPath: newPath,
    );

    final game = await _gameRepository.getGameById(gameId);
    if (game != null &&
        game.gameLauncher != null &&
        game.gameLauncher!.startsWith(oldPath)) {
      final relativeLauncher = game.gameLauncher!.substring(oldPath.length);
      final newLauncher = '$newPath$relativeLauncher';
      await _gameRepository.updateGameLauncher(
          gameId, newLauncher, game.launcherLocked);
    }

    if (game != null &&
        game.savePath != null &&
        game.savePath!.startsWith(oldPath)) {
      final relativeSave = game.savePath!.substring(oldPath.length);
      final newSave = '$newPath$relativeSave';
      await _gameRepository.updateSavePath(gameId, newSave);
    }
  }

  bool _isTransientDbError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('database is locked') ||
        text.contains('database is busy') ||
        text.contains('sqlite_busy');
  }

  String _describeDbError(Object error) {
    final text = error.toString();
    final match = RegExp(r'DatabaseException\(([^)]*)\)').firstMatch(text);
    return match?.group(1) ?? text;
  }
}
