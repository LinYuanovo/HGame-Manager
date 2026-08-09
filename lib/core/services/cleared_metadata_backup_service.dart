import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/models.dart';
import '../utils/app_paths.dart';

/// 保存通关游戏的全局元数据，不复制游戏本体。
class ClearedMetadataBackupService {
  final String? backupDirectory;

  ClearedMetadataBackupService({this.backupDirectory});

  Future<File> _fileFor(Game game) async {
    if (game.id == null) {
      throw StateError('通关元数据备份需要游戏 ID');
    }
    final filePath = backupDirectory == null
        ? await AppPaths.clearedMetadataBackupFile(game.id!)
        : path.join(backupDirectory!, '${game.id}.json');
    return File(filePath);
  }

  Future<File?> find(Game game) async {
    if (game.id == null) return null;
    final file = await _fileFor(game);
    return await file.exists() ? file : null;
  }

  Future<File> save(Game game) async {
    final file = await _fileFor(game);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'game': game.toMap(),
        'tags': game.tags.map((tag) => tag.toMap()).toList(),
        'images': game.images.map((image) => image.toMap()).toList(),
      }),
      flush: true,
    );
    return file;
  }

  Future<File> refresh(Game game) => save(game);

  Future<void> delete(Game game) async {
    final file = await find(game);
    if (file != null) await file.delete();
  }
}
