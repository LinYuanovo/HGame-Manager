import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;

import 'app_logger.dart';
import 'folder_move_progress.dart';

class _ScanManifest {
  final Map<String, int> files;
  final List<String> directories;
  final int totalBytes;

  const _ScanManifest({
    required this.files,
    required this.directories,
    required this.totalBytes,
  });
}

class FolderTransferService {
  static const String _logTag = 'GameMove';
  static const int _chunkSize = 1024 * 1024;
  static const int _progressByteInterval = 4 * 1024 * 1024;
  static const Duration _progressTimeInterval = Duration(milliseconds: 100);

  final bool forceCopy;
  final List<Duration> retryDelays;
  final Future<void> Function(Directory target)? onAfterCopy;

  FolderTransferService({
    this.forceCopy = false,
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
    this.onAfterCopy,
  });

  Future<FolderMoveResult> moveDirectory({
    required Directory source,
    required Directory target,
    void Function(FolderMoveProgress progress)? onProgress,
    bool Function()? shouldCancel,
    Future<void> Function()? commit,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (!await source.exists()) {
      throw FolderMoveException('源文件夹不存在：${source.path}');
    }
    if (await target.exists()) {
      throw FolderMoveException('目标文件夹已存在：${target.path}');
    }

    final normalizedSource = path.normalize(source.absolute.path);
    final normalizedTarget = path.normalize(target.absolute.path);
    if (normalizedSource == normalizedTarget ||
        path.isWithin(normalizedSource, normalizedTarget) ||
        path.isWithin(normalizedTarget, normalizedSource)) {
      throw const FolderMoveException('目标文件夹不能与源文件夹互相包含');
    }

    onProgress?.call(const FolderMoveProgress(phase: FolderMovePhase.scanning));
    final manifest = await _scan(source);

    final filesTotal = manifest.files.length;
    final bytesTotal = manifest.totalBytes;

    onProgress?.call(FolderMoveProgress(
      phase: FolderMovePhase.scanning,
      filesTotal: filesTotal,
      bytesTotal: bytesTotal,
    ));

    if (shouldCancel?.call() == true) {
      throw const FolderMoveCancelledException();
    }

    if (!forceCopy &&
        path.rootPrefix(source.path) == path.rootPrefix(target.path)) {
      await source.rename(target.path);
      if (commit != null) {
        try {
          await commit();
        } catch (e) {
          final rollbackError = await _tryRenameBack(target, source);
          if (rollbackError != null) {
            throw FolderMoveException(
              _describeCommitError(e),
              filesMoved: true,
              cleanupWarning: '源目录未能还原，文件现在位于 ${target.path}：$rollbackError',
            );
          }
          rethrow;
        }
      }
      onProgress?.call(FolderMoveProgress(
        phase: FolderMovePhase.done,
        filesDone: filesTotal,
        filesTotal: filesTotal,
        bytesDone: bytesTotal,
        bytesTotal: bytesTotal,
      ));
      return FolderMoveResult(
        fileCount: filesTotal,
        dirCount: manifest.directories.length,
        totalBytes: bytesTotal,
        elapsed: stopwatch.elapsed,
      );
    }

    var filesDone = 0;
    var bytesDone = 0;
    var reportedBytes = 0;
    var lastEmitTime = DateTime.now();
    var bytesAtLastEmit = 0;

    void emitCopying({String? currentFile, bool force = false}) {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastEmitTime) < _progressTimeInterval &&
          bytesDone - bytesAtLastEmit < _progressByteInterval) {
        return;
      }
      lastEmitTime = now;
      bytesAtLastEmit = bytesDone;
      reportedBytes = math.max(reportedBytes, bytesDone);
      onProgress?.call(FolderMoveProgress(
        phase: FolderMovePhase.copying,
        filesDone: filesDone,
        filesTotal: filesTotal,
        bytesDone: math.min(reportedBytes, bytesTotal),
        bytesTotal: bytesTotal,
        currentFile: currentFile,
      ));
    }

    try {
      await target.create(recursive: true);
      for (final directory in manifest.directories) {
        if (shouldCancel?.call() == true) {
          throw const FolderMoveCancelledException();
        }
        await Directory(_resolve(target.path, directory))
            .create(recursive: true);
      }

      for (final entry in manifest.files.entries) {
        if (shouldCancel?.call() == true) {
          throw const FolderMoveCancelledException();
        }
        final relativePath = entry.key;
        final expectedBytes = entry.value;
        final sourceFile = File(_resolve(source.path, relativePath));
        final targetFile = File(_resolve(target.path, relativePath));
        var attempt = 0;

        while (true) {
          var attemptBytes = 0;
          try {
            await _copyFileChunks(
              sourceFile: sourceFile,
              targetFile: targetFile,
              shouldCancel: shouldCancel,
              onChunk: (bytes) {
                attemptBytes += bytes;
                bytesDone += bytes;
                emitCopying(currentFile: relativePath);
              },
            );
            filesDone++;
            emitCopying(currentFile: relativePath, force: true);
            break;
          } catch (e) {
            if (e is FolderMoveCancelledException) rethrow;
            bytesDone -= attemptBytes;
            bytesAtLastEmit = math.min(bytesAtLastEmit, bytesDone);
            await _deleteFileQuietly(targetFile);
            if (attempt >= retryDelays.length) {
              throw FolderMoveException(
                '复制文件失败：${_describeError(e)}',
                relativePath: relativePath,
                bytesWritten: attemptBytes,
                expectedBytes: expectedBytes,
              );
            }
            await Future<void>.delayed(retryDelays[attempt]);
            attempt++;
          }
        }
      }

      final afterCopy = onAfterCopy;
      if (afterCopy != null) {
        await afterCopy(target);
      }

      onProgress?.call(FolderMoveProgress(
        phase: FolderMovePhase.verifying,
        filesDone: filesDone,
        filesTotal: filesTotal,
        bytesDone: math.min(reportedBytes, bytesTotal),
        bytesTotal: bytesTotal,
      ));
      await _verify(target, manifest);
      if (shouldCancel?.call() == true) {
        throw const FolderMoveCancelledException();
      }
    } catch (e) {
      final cleanupError = await _deleteDirectory(target);
      if (cleanupError != null) {
        final cleanupWarning = '目标残留清理失败，请手动删除 ${target.path}：$cleanupError';
        AppLogger.instance.warning(_logTag, cleanupWarning);
        if (e is FolderMoveException) {
          throw FolderMoveException(
            e.message,
            relativePath: e.relativePath,
            bytesWritten: e.bytesWritten,
            expectedBytes: e.expectedBytes,
            cleanupWarning: cleanupWarning,
          );
        }
        if (e is FolderMoveCancelledException) {
          throw FolderMoveCancelledException(
            cleanupWarning: cleanupWarning,
          );
        }
      }
      rethrow;
    }

    if (commit != null) {
      try {
        await commit();
      } catch (e) {
        final cleanupError = await _deleteDirectory(target);
        if (cleanupError != null) {
          final cleanupWarning = '目标残留清理失败，请手动删除 ${target.path}：$cleanupError';
          AppLogger.instance.warning(_logTag, cleanupWarning);
          throw FolderMoveException(
            _describeCommitError(e),
            filesMoved: true,
            cleanupWarning: cleanupWarning,
          );
        }
        rethrow;
      }
    }

    onProgress?.call(FolderMoveProgress(
      phase: FolderMovePhase.cleaning,
      filesDone: filesTotal,
      filesTotal: filesTotal,
      bytesDone: bytesTotal,
      bytesTotal: bytesTotal,
    ));

    String? warning;
    try {
      await source.delete(recursive: true);
    } catch (e) {
      warning = '原目录删除失败，源文件可能仍然残留：${_describeError(e)}';
      AppLogger.instance.warning(
        _logTag,
        '删除源目录失败: ${source.path}, ${_describeError(e)}',
      );
    }

    onProgress?.call(FolderMoveProgress(
      phase: FolderMovePhase.done,
      filesDone: filesTotal,
      filesTotal: filesTotal,
      bytesDone: bytesTotal,
      bytesTotal: bytesTotal,
    ));

    return FolderMoveResult(
      fileCount: filesTotal,
      dirCount: manifest.directories.length,
      totalBytes: bytesTotal,
      elapsed: stopwatch.elapsed,
      warning: warning,
    );
  }

  Future<_ScanManifest> _scan(Directory source) async {
    final files = <String, int>{};
    final directories = <String>[];
    var totalBytes = 0;

    try {
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        final relativePath = _relativePath(entity.path, source.path);
        if (entity is Link) {
          throw FolderMoveException(
            '暂不支持含符号链接的目录',
            relativePath: relativePath,
          );
        }
        if (entity is File) {
          final length = await entity.length();
          files[relativePath] = length;
          totalBytes += length;
        } else if (entity is Directory) {
          directories.add(relativePath);
        }
      }
    } on FolderMoveException {
      rethrow;
    } on FileSystemException catch (e) {
      throw FolderMoveException('扫描源目录失败：${_describeError(e)}');
    }

    return _ScanManifest(
      files: files,
      directories: directories,
      totalBytes: totalBytes,
    );
  }

  Future<void> _copyFileChunks({
    required File sourceFile,
    required File targetFile,
    required bool Function()? shouldCancel,
    required void Function(int bytes) onChunk,
  }) async {
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await sourceFile.open();
      output = await targetFile.open(mode: FileMode.write);
      while (true) {
        if (shouldCancel?.call() == true) {
          throw const FolderMoveCancelledException();
        }
        final chunk = await input.read(_chunkSize);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
        onChunk(chunk.length);
      }
      await output.flush();
    } finally {
      if (input != null) {
        try {
          await input.close();
        } catch (_) {}
      }
      if (output != null) {
        try {
          await output.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _verify(Directory target, _ScanManifest manifest) async {
    if (!await target.exists()) {
      throw const FolderMoveException('目标目录不存在');
    }

    final targetFiles = <String, int>{};
    final targetDirectories = <String>{};
    final extraEntries = <String>[];

    await for (final entity in target.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = _relativePath(entity.path, target.path);
      if (entity is File) {
        targetFiles[relativePath] = await entity.length();
      } else if (entity is Directory) {
        targetDirectories.add(relativePath);
      } else {
        extraEntries.add(relativePath);
      }
    }

    for (final entry in manifest.files.entries) {
      final relativePath = entry.key;
      final expectedBytes = entry.value;
      final writtenBytes = targetFiles[relativePath];
      if (writtenBytes == null) {
        throw FolderMoveException(
          '目标文件缺失：$relativePath',
          relativePath: relativePath,
          bytesWritten: 0,
          expectedBytes: expectedBytes,
        );
      }
      if (writtenBytes != expectedBytes) {
        throw FolderMoveException(
          '校验文件大小不一致：$relativePath（已写入 $writtenBytes / 预期 $expectedBytes 字节）',
          relativePath: relativePath,
          bytesWritten: writtenBytes,
          expectedBytes: expectedBytes,
        );
      }
    }

    for (final directory in manifest.directories) {
      if (!targetDirectories.contains(directory)) {
        throw FolderMoveException(
          '目标目录缺失：$directory',
          relativePath: directory,
        );
      }
    }

    for (final relativePath in targetFiles.keys) {
      if (!manifest.files.containsKey(relativePath)) {
        throw FolderMoveException(
          '目标目录存在多余文件：$relativePath',
          relativePath: relativePath,
        );
      }
    }

    if (extraEntries.isNotEmpty) {
      throw FolderMoveException(
        '目标目录存在多余条目：${extraEntries.first}',
        relativePath: extraEntries.first,
      );
    }
  }

  String _relativePath(String entityPath, String rootPath) {
    return path.relative(entityPath, from: rootPath).replaceAll('\\', '/');
  }

  String _resolve(String rootPath, String relativePath) {
    return path.joinAll([rootPath, ...relativePath.split('/')]);
  }

  String _describeError(Object error) {
    if (error is FileSystemException && error.message.isNotEmpty) {
      return error.message;
    }
    return error.toString();
  }

  Future<void> _deleteFileQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  String _describeCommitError(Object error) {
    if (error is FolderMoveException) return error.message;
    return '数据库记录更新失败：$error';
  }

  Future<String?> _tryRenameBack(Directory target, Directory source) async {
    try {
      await target.rename(source.path);
      return null;
    } catch (e) {
      return _describeError(e);
    }
  }

  Future<String?> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return null;
    } catch (e) {
      return _describeError(e);
    }
  }
}
