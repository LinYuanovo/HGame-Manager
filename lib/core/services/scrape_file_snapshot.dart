import 'dart:io';

import 'package:path/path.dart' as path;

import '../utils/game_data_paths.dart';

class ScrapeRecoveryException implements Exception {
  final String recoveryPath;
  final List<Object> failures;

  ScrapeRecoveryException(this.recoveryPath, this.failures);

  @override
  String toString() => '保存失败且自动恢复未完成，请保留恢复文件夹 $recoveryPath：'
      '${failures.join('；')}';
}

/// 确认保存失败时恢复共享刮削管线会改动的文件，不复制存档备份。
class ScrapeFileSnapshot {
  final String gamePath;
  final Directory backup;
  final Map<String, String> _copies;
  final bool _hadDataDirectory;
  final bool _hadImagesDirectory;

  ScrapeFileSnapshot._(this.gamePath, this.backup, this._copies,
      this._hadDataDirectory, this._hadImagesDirectory);

  static Future<ScrapeFileSnapshot> capture(String gamePath) async {
    final backup = await Directory.systemTemp.createTemp('hgm_scrape_restore_');
    final snapshot = ScrapeFileSnapshot._(
        gamePath,
        backup,
        {},
        await GameDataPaths.dataDir(gamePath).exists(),
        await GameDataPaths.imagesDir(gamePath).exists());
    try {
      for (final file in await snapshot._files()) {
        final copy =
            path.join(backup.path, path.relative(file.path, from: gamePath));
        await File(copy).parent.create(recursive: true);
        await file.copy(copy);
        snapshot._copies[file.path] = copy;
      }
      await File(path.join(backup.path, '恢复说明.txt'))
          .writeAsString('原游戏目录：$gamePath\n此目录按原相对路径保留确认前的元数据和图片。\n');
      return snapshot;
    } catch (_) {
      await backup.delete(recursive: true);
      rethrow;
    }
  }

  Future<List<File>> _files() async {
    final files = <File>[];
    for (final file in [
      GameDataPaths.metadataFile(gamePath),
      GameDataPaths.sourceUrlFile(gamePath),
    ]) {
      if (await file.exists()) files.add(file);
    }
    final images = GameDataPaths.imagesDir(gamePath);
    if (await images.exists()) {
      await for (final entity in images.list(followLinks: false)) {
        if (entity is File) files.add(entity);
      }
    }
    return files;
  }

  Future<void> restore() async {
    for (final file in await _files()) {
      if (!_copies.containsKey(file.path)) await file.delete();
    }
    for (final entry in _copies.entries) {
      final target = File(entry.key);
      await target.parent.create(recursive: true);
      await File(entry.value).copy(entry.key);
    }
    for (final directory in [
      if (!_hadImagesDirectory) GameDataPaths.imagesDir(gamePath),
      if (!_hadDataDirectory) GameDataPaths.dataDir(gamePath),
    ]) {
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    }
  }

  Future<void> dispose() => backup.delete(recursive: true);
}
