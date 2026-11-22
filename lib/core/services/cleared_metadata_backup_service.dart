import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/models.dart';
import '../utils/app_paths.dart';
import '../utils/game_data_paths.dart';

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

  Future<File> save(Game game,
      {Map<String, dynamic> metadataChanges = const {}}) async {
    final file = await _fileFor(game);
    var metadata = await loadMetadata(game);
    if (metadataChanges.isNotEmpty) {
      metadata = {...?metadata, ...metadataChanges};
    }
    await file.parent.create(recursive: true);
    final snapshot = await file.exists()
        ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{};
    snapshot.addAll({
      'version': 1,
      'game': game.toMap(),
      'tags': game.tags.map((tag) => tag.toMap()).toList(),
      'images': game.images.map((image) => image.toMap()).toList(),
      if (metadata != null) 'metadata': metadata,
    });
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(snapshot), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return file;
  }

  Future<File> refresh(Game game,
          {Map<String, dynamic> metadataChanges = const {}}) =>
      save(game, metadataChanges: metadataChanges);

  Future<Map<String, dynamic>?> loadMetadata(Game game) async {
    final source = await GameDataPaths.existingMetadataFile(game.path);
    if (await source.exists()) {
      return jsonDecode(await source.readAsString()) as Map<String, dynamic>;
    }
    if (!game.isCleared) return null;
    final backup = await find(game);
    if (backup == null) return null;
    final saved =
        jsonDecode(await backup.readAsString()) as Map<String, dynamic>;
    final metadata = saved['metadata'];
    return metadata is Map ? Map<String, dynamic>.from(metadata) : null;
  }

  Future<void> delete(Game game) async {
    final file = await find(game);
    if (file != null) await file.delete();
  }
}
