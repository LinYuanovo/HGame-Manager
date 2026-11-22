import 'dart:io';
import '../repositories/game_repository.dart';
import '../utils/game_data_paths.dart';
import '../utils/path_reference_rewriter.dart';
import 'app_logger.dart';
import 'folder_move_progress.dart';
import 'folder_transfer_service.dart';

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
    required int? gameId,
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
    required int? gameId,
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
    required int? gameId,
    required String oldPath,
    required String newPath,
  }) async {
    final metadata = await GameDataPaths.existingMetadataFile(newPath);
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final staged = File('${metadata.path}.move-$suffix.tmp');
    final original = File('${metadata.path}.move-original-$suffix.tmp');
    var metadataChanged = false;
    var committed = false;
    try {
      if (await metadata.exists()) {
        final content = await metadata.readAsString();
        final updated =
            PathReferenceRewriter.replaceRequired(content, {oldPath: newPath});
        if (updated != content) {
          await staged.writeAsString(updated, flush: true);
          metadataChanged = true;
        }
      }
      Future<void> replaceMetadata() async {
        if (!metadataChanged) return;
        await metadata.rename(original.path);
        await staged.rename(metadata.path);
      }

      if (gameId == null) {
        await replaceMetadata();
      } else {
        await _gameRepository.moveGameRecords(
          gameId: gameId,
          oldPath: oldPath,
          newPath: newPath,
          beforeCommit: replaceMetadata,
        );
      }
      committed = true;
    } catch (error, stackTrace) {
      if (await original.exists()) {
        try {
          if (await metadata.exists()) await metadata.delete();
          await original.rename(metadata.path);
        } catch (restoreError) {
          throw FolderMoveException(
            '移动记录提交失败，元数据恢复失败：$restoreError；'
            '原文件保存在 ${original.path}',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      // 清理失败不能撤销已提交的搬运，否则数据库和目录会重新分离。
      for (final file in [staged, if (committed) original]) {
        try {
          if (await file.exists()) await file.delete();
        } catch (error) {
          AppLogger.instance.warning(_logTag, '移动临时文件清理失败：${file.path}，$error');
        }
      }
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
