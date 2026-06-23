import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import 'app_logger.dart';

class _ParsedGameData {
  final String folderPath;
  final String? title;
  final String? version;
  final String? intro;
  final String? features;
  final String? changelog;
  final String? downloadUrl;
  final String? sourceUrl;
  final List<String> imagePaths;
  final List<String> tagNames;
  final String? seriesName;
  final int? existingGameId;
  final int? playCount;
  final DateTime? lastPlayedTime;
  final DateTime? addedTime;
  final bool isFavorite;
  final bool isPlayed;

  _ParsedGameData({
    required this.folderPath,
    this.title,
    this.version,
    this.intro,
    this.features,
    this.changelog,
    this.downloadUrl,
    this.sourceUrl,
    required this.imagePaths,
    required this.tagNames,
    this.seriesName,
    this.existingGameId,
    this.playCount,
    this.lastPlayedTime,
    this.addedTime,
    this.isFavorite = false,
    this.isPlayed = false,
  });
}

class GameScannerService {
  final _log = AppLogger.instance;
  final GameRepository _gameRepository;

  void Function()? onGameProcessed;
  void Function(int processed, int total)? onProgress;
  bool Function()? shouldCancel;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  GameScannerService({
    GameRepository? gameRepository,
    TagRepository? tagRepository,
    this.onGameProcessed,
    this.onProgress,
    this.shouldCancel,
  }) : _gameRepository = gameRepository ?? GameRepository();

  Future<void> scanGameLibrary(String libraryPath, {List<String> ignoreFolders = const [], List<String> blacklistPaths = const []}) async {
    if (_isScanning) {
      _log.info('Scan', 'Already scanning, skipping duplicate request');
      return;
    }
    _isScanning = true;

    _log.info('Scan', 'Starting Game Scan, libraryPath=$libraryPath');

    try {
      final scanDir = Directory(libraryPath);
      if (!await scanDir.exists()) {
        _log.warning('Scan', 'Scan directory does not exist: $libraryPath');
        return;
      }

      // ── Phase 1: Scan folders, filter by blacklist and metadata change ──
      _log.info('Scan', 'Phase 1: Scanning folders...');
      final allFolders = await _scanGameFolders(libraryPath, ignoreFolders);
      // 规范化黑名单路径进行比较（统一反斜杠、转小写）
      final normalizedBlacklist = blacklistPaths.map((p) => p.replaceAll('/', '\\').toLowerCase()).toSet();
      final filteredFolders = allFolders.where((f) {
        final normalized = f.replaceAll('/', '\\').toLowerCase();
        return !normalizedBlacklist.contains(normalized);
      }).toList();

      final existingGames = await _gameRepository.getAllGames();
      final gamePathMap = <String, Game>{};
      for (final g in existingGames) {
        gamePathMap[g.path] = g;
      }

      final foldersToProcess = <String>[];
      for (final folder in filteredFolders) {
        if (shouldCancel?.call() == true) break;
        final existing = gamePathMap[folder];
        final metadataFile = File(path.join(folder, 'metadata.json'));
        
        // 如果游戏已存在
        if (existing != null) {
          // 如果 addedTime 为空（旧数据），跳过扫描
          if (existing.addedTime == null) {
            continue;
          }
          // 如果 metadata.json 存在，检查是否被修改过
          if (await metadataFile.exists()) {
            final stat = await metadataFile.stat();
            if (!stat.modified.isAfter(existing.addedTime!)) {
              continue;
            }
          }
        }
        foldersToProcess.add(folder);
      }

      final skippedCount = filteredFolders.length - foldersToProcess.length;
      _log.info('Scan', 'Phase 1 done: ${filteredFolders.length} total, ${foldersToProcess.length} to process, $skippedCount skipped');
      if (kDebugMode) {
        debugPrint('[Scan] Phase 1: ${filteredFolders.length} folders found, ${foldersToProcess.length} need processing, $skippedCount skipped (unchanged)');
      }

      if (foldersToProcess.isEmpty) {
        // Still need to clean up missing folders
        await _removeStaleEntries(existingGames);
        _log.info('Scan', 'Scan Complete: nothing to process');
        return;
      }

      onProgress?.call(0, foldersToProcess.length);

      // ── Phase 2: Parse metadata in parallel (50 per batch) ──
      _log.info('Scan', 'Phase 2: Parsing metadata...');
      final parsedGames = <_ParsedGameData>[];
      const parseBatchSize = 50;
      for (int i = 0; i < foldersToProcess.length; i += parseBatchSize) {
        if (shouldCancel?.call() == true) break;

        final batch = foldersToProcess.skip(i).take(parseBatchSize).toList();
        final results = await Future.wait(batch.map((f) => _parseFolder(f, gamePathMap)));
        for (final r in results) {
          if (r != null) parsedGames.add(r);
        }

        onProgress?.call(i + batch.length, foldersToProcess.length);
        onGameProcessed?.call();
      }

      _log.info('Scan', 'Phase 2 done: parsed ${parsedGames.length} games');

      if (parsedGames.isEmpty) {
        await _removeStaleEntries(existingGames);
        _log.info('Scan', 'Scan Complete: no valid metadata found');
        return;
      }

      // ── Phase 3: Batch DB write in a single transaction ──
      _log.info('Scan', 'Phase 3: Writing to database...');
      await _batchWriteToDatabase(parsedGames, gamePathMap);

      // Clean up missing folders
      await _removeStaleEntries(existingGames);

      _log.info('Scan', 'Scan Complete: processed ${parsedGames.length}/${foldersToProcess.length}, skipped $skippedCount (unchanged)');
    } catch (e, stackTrace) {
      _log.error('Scan', 'FATAL ERROR in Game Scan', e, stackTrace);
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// 扫描多个游戏库目录
  Future<void> scanMultipleLibraries(
    List<String> libraryPaths, {
    List<String> ignoreFolders = const [],
    List<String> blacklistPaths = const [],
  }) async {
    for (final libraryPath in libraryPaths) {
      await scanGameLibrary(libraryPath, ignoreFolders: ignoreFolders, blacklistPaths: blacklistPaths);
    }
  }

  Future<List<String>> _scanGameFolders(String rootPath, List<String> ignoreFolders) async {
    final folders = <String>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return folders;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);
        final folderNameLower = folderName.toLowerCase();
        // 忽略用户设置的文件夹、Cleared目录（已通关）和Backup目录（已通关备份）
        if (ignoreFolders.any((f) => f.toLowerCase() == folderNameLower) || 
            folderNameLower == 'backup' || 
            folderNameLower == 'cleared') {
          continue;
        }
        if (await File(path.join(entity.path, 'metadata.json')).exists()) {
          folders.add(entity.path);
        } else {
          folders.addAll(await _scanGameFolders(entity.path, ignoreFolders));
        }
      }
    }
    return folders;
  }

  Future<_ParsedGameData?> _parseFolder(String folderPath, Map<String, Game> existingGameMap) async {
    try {
      final metadataFile = File(path.join(folderPath, 'metadata.json'));
      Map<String, dynamic>? metadata;
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        metadata = jsonDecode(content) as Map<String, dynamic>;
      }

      final sourceUrlFile = File(path.join(folderPath, 'source_url.txt'));
      String? sourceUrl;
      if (await sourceUrlFile.exists()) {
        sourceUrl = (await sourceUrlFile.readAsString()).trim();
      }

      var imageDir = Directory(path.join(folderPath, 'images'));
      if (!await imageDir.exists()) {
        imageDir = Directory(path.join(folderPath, 'image'));
      }
      final List<String> imagePaths = [];
      if (await imageDir.exists()) {
        await for (final entity in imageDir.list(followLinks: false)) {
          if (entity is File) {
            final ext = path.extension(entity.path).toLowerCase();
            if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.gif' || ext == '.webp') {
              imagePaths.add(entity.path);
            }
          }
        }
        imagePaths.sort();
      }

      final existingGame = existingGameMap[folderPath];
      final folderName = path.basename(folderPath);

      String? title = metadata?['title'] as String?;
      if (title == null || title.isEmpty) {
        title = folderName;
      }

      final tagNames = <String>[];
      final tagsList = metadata?['tags'] as List<dynamic>?;
      if (tagsList != null) {
        for (final t in tagsList) {
          if (t is String && t.isNotEmpty) tagNames.add(t);
        }
      }

      return _ParsedGameData(
        folderPath: folderPath,
        title: title,
        version: metadata?['version'] as String?,
        intro: metadata?['intro'] as String?,
        features: metadata?['features'] as String?,
        changelog: metadata?['changelog'] as String?,
        downloadUrl: metadata?['download_url'] as String?,
        sourceUrl: sourceUrl ?? metadata?['source_url'] as String?,
        imagePaths: imagePaths,
        tagNames: tagNames,
        seriesName: metadata?['series'] as String?,
        existingGameId: existingGame?.id,
        playCount: existingGame?.playCount ?? 0,
        lastPlayedTime: existingGame?.lastPlayedTime,
        addedTime: existingGame?.addedTime,
        isFavorite: existingGame?.isFavorite ?? false,
        isPlayed: existingGame?.isPlayed ?? false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Scan] Error parsing $folderPath: $e');
      return null;
    }
  }

  Future<void> _batchWriteToDatabase(List<_ParsedGameData> parsedGames, Map<String, Game> existingGameMap) async {
    final db = await DatabaseHelper.database;

    await db.transaction((txn) async {
      // Collect all unique tags
      final allTags = <String, String>{}; // key: "type:name", value: name
      for (final data in parsedGames) {
        for (final tag in data.tagNames) {
          allTags['${Tag.typeCustom}:$tag'] = tag;
        }
        if (data.seriesName != null && data.seriesName!.isNotEmpty) {
          allTags['${Tag.typeSeries}:${data.seriesName}'] = data.seriesName!;
        }
      }

      // Insert all tags (INSERT OR IGNORE)
      for (final entry in allTags.entries) {
        final parts = entry.key.split(':');
        await txn.insert('tags', {
          'name': entry.value,
          'type': parts[0],
          'display_name': entry.value,
          'is_favorite': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      // Get all tag IDs
      final tagMaps = await txn.query('tags');
      final tagIdMap = <String, int>{};
      for (final map in tagMaps) {
        tagIdMap['${map['type']}:${map['name']}'] = map['id'] as int;
      }

      // Process each game
      for (final data in parsedGames) {
        final existing = existingGameMap[data.folderPath];

        final gameMap = <String, dynamic>{
          'path': data.folderPath,
          'title': data.title,
          'version': data.version,
          'intro': data.intro,
          'features': data.features,
          'changelog': data.changelog,
          'download_url': data.downloadUrl,
          'source_url': data.sourceUrl,
          'play_count': data.playCount ?? 0,
          'last_played_time': data.lastPlayedTime?.toIso8601String(),
          'is_favorite': data.isFavorite ? 1 : 0,
          'is_played': data.isPlayed ? 1 : 0,
        };

        int gameId;
        if (existing != null) {
          // 更新游戏时保留原有的 added_time
          await txn.update('games', gameMap, where: 'id = ?', whereArgs: [existing.id]);
          gameId = existing.id!;
        } else {
          // 新游戏插入时设置 added_time
          gameMap['added_time'] = DateTime.now().toIso8601String();
          gameId = await txn.insert('games', gameMap);
        }

        // Insert game-tag relations (INSERT OR IGNORE)
        for (final tagName in data.tagNames) {
          final tagId = tagIdMap['${Tag.typeCustom}:$tagName'];
          if (tagId != null) {
            await txn.insert('game_tag_relation', {
              'game_id': gameId,
              'tag_id': tagId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (data.seriesName != null && data.seriesName!.isNotEmpty) {
          final tagId = tagIdMap['${Tag.typeSeries}:${data.seriesName}'];
          if (tagId != null) {
            await txn.insert('game_tag_relation', {
              'game_id': gameId,
              'tag_id': tagId,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        // Batch insert game images
        await txn.delete('game_images', where: 'game_id = ?', whereArgs: [gameId]);
        if (data.imagePaths.isNotEmpty) {
          final batch = txn.batch();
          for (int i = 0; i < data.imagePaths.length; i++) {
            batch.insert('game_images', {
              'game_id': gameId,
              'image_path': data.imagePaths[i],
              'sort_order': i,
            });
          }
          await batch.commit(noResult: true);
        }
      }
    });
  }

  Future<void> _removeStaleEntries(List<Game> existingGames) async {
    for (final game in existingGames) {
      try {
        final sep = Platform.pathSeparator;
        if (game.path.contains('${sep}Cleared$sep') &&
            !game.path.contains('${sep}Backup$sep')) {
          continue;
        }
        final dir = Directory(game.path);
        if (!await dir.exists()) {
          await _gameRepository.deleteGame(game.id!);
          if (kDebugMode) debugPrint('[Scan] Removed DB entry for missing folder: ${game.path}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Scan] Error checking game folder: $e');
      }
    }
  }
}
