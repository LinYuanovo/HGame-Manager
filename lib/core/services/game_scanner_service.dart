import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../utils/app_settings.dart';
import '../utils/game_data_paths.dart';
import 'app_logger.dart';
import 'game_data_migration_service.dart';
import 'cleared_metadata_backup_service.dart';

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
  final bool isCleared;
  final String? guide;
  final String metadataFingerprint;
  final bool migrationChecked;

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
    this.isCleared = false,
    this.guide,
    required this.metadataFingerprint,
    required this.migrationChecked,
  });
}

class GameScannerService {
  final _log = AppLogger.instance;
  final GameRepository _gameRepository;
  final ClearedMetadataBackupService _clearedMetadataBackupService;

  void Function()? onGameProcessed;
  void Function(int processed, int total)? onProgress;
  bool Function()? shouldCancel;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  GameScannerService({
    GameRepository? gameRepository,
    TagRepository? tagRepository,
    ClearedMetadataBackupService? clearedMetadataBackupService,
    this.onGameProcessed,
    this.onProgress,
    this.shouldCancel,
  })  : _gameRepository = gameRepository ?? GameRepository(),
        _clearedMetadataBackupService =
            clearedMetadataBackupService ?? ClearedMetadataBackupService();

  GameDataMigrationService get _migrationService =>
      GameDataMigrationService(gameRepository: _gameRepository);

  Future<void> scanGameLibrary(String libraryPath,
      {List<String> ignoreFolders = const [],
      List<String> blacklistPaths = const []}) async {
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
      final normalizedBlacklist = blacklistPaths
          .map((p) => p.replaceAll('/', '\\').toLowerCase())
          .toSet();
      final filteredFolders = allFolders.where((f) {
        final normalized = f.replaceAll('/', '\\').toLowerCase();
        return !normalizedBlacklist.contains(normalized);
      }).toList();

      final prefs = await AppSettings.load();
      final scanFingerprints = _loadScanMetadataFingerprints(prefs);
      final migratedIds =
          prefs.getStringList(AppSettings.startupMigratedGameIdsKey)?.toSet() ??
              <String>{};
      var scanFingerprintsDirty = false;
      var migratedIdsDirty = false;

      final existingGames = await _gameRepository.getAllGames();
      final gamePathMap = <String, Game>{};
      for (final g in existingGames) {
        gamePathMap[g.path] = g;
      }

      final foldersToProcess = <String>[];
      for (final folder in filteredFolders) {
        if (shouldCancel?.call() == true) break;
        final existing = gamePathMap[folder];
        final metadataFile = await GameDataPaths.existingMetadataFile(folder);
        final fingerprint = await _metadataFingerprint(metadataFile);
        final folderKey = _normalizedPathKey(folder);

        // 如果游戏已存在
        if (existing != null) {
          if (fingerprint != null) {
            final cachedFingerprint = scanFingerprints[folderKey];
            if (cachedFingerprint == fingerprint) {
              continue;
            }

            // 兼容旧数据：没有扫描缓存时，仍沿用 addedTime 的跳过逻辑，
            // 同时补齐缓存，避免后续扫描重复比较到旧字段。
            if (cachedFingerprint == null && existing.addedTime != null) {
              final stat = await metadataFile.stat();
              if (!stat.modified.isAfter(existing.addedTime!)) {
                scanFingerprints[folderKey] = fingerprint;
                scanFingerprintsDirty = true;
                continue;
              }
            }
          } else if (existing.addedTime == null) {
            continue;
          } else {
            if (!await metadataFile.exists()) {
              continue;
            }
          }
        }
        foldersToProcess.add(folder);
      }

      if (scanFingerprintsDirty) {
        await _saveScanMetadataFingerprints(prefs, scanFingerprints);
      }

      final skippedCount = filteredFolders.length - foldersToProcess.length;
      _log.info('Scan',
          'Phase 1 done: ${filteredFolders.length} total, ${foldersToProcess.length} to process, $skippedCount skipped');
      if (kDebugMode) {
        debugPrint(
            '[Scan] Phase 1: ${filteredFolders.length} folders found, ${foldersToProcess.length} need processing, $skippedCount skipped (unchanged)');
      }

      if (foldersToProcess.isEmpty) {
        // Still need to clean up missing folders
        await _removeStaleEntries(existingGames, libraryPath);
        _log.info('Scan', 'Scan Complete: nothing to process');
        return;
      }

      onProgress?.call(0, foldersToProcess.length);

      // ── Phase 2: Parse metadata in small batches to avoid disk I/O spikes ──
      _log.info('Scan', 'Phase 2: Parsing metadata...');
      final parsedGames = <_ParsedGameData>[];
      const parseBatchSize = 8;
      for (int i = 0; i < foldersToProcess.length; i += parseBatchSize) {
        if (shouldCancel?.call() == true) break;

        final batch = foldersToProcess.skip(i).take(parseBatchSize).toList();
        final results = await Future.wait(batch.map((f) => _parseFolder(
              f,
              gamePathMap,
              migratedIds,
            )));
        for (final r in results) {
          if (r == null) continue;
          parsedGames.add(r);
          scanFingerprints[_normalizedPathKey(r.folderPath)] =
              r.metadataFingerprint;
          final id = r.existingGameId;
          if (id != null &&
              r.migrationChecked &&
              !migratedIds.contains(id.toString())) {
            migratedIds.add(id.toString());
            migratedIdsDirty = true;
          }
        }
        scanFingerprintsDirty =
            scanFingerprintsDirty || results.any((r) => r != null);

        onProgress?.call(i + batch.length, foldersToProcess.length);
        onGameProcessed?.call();
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      _log.info('Scan', 'Phase 2 done: parsed ${parsedGames.length} games');

      if (parsedGames.isEmpty) {
        if (scanFingerprintsDirty) {
          await _saveScanMetadataFingerprints(prefs, scanFingerprints);
        }
        if (migratedIdsDirty) {
          await _saveMigratedIds(prefs, migratedIds);
        }
        await _removeStaleEntries(existingGames, libraryPath);
        _log.info('Scan', 'Scan Complete: no valid metadata found');
        return;
      }

      // ── Phase 3: Batch DB write in a single transaction ──
      _log.info('Scan', 'Phase 3: Writing to database...');
      await _batchWriteToDatabase(parsedGames, gamePathMap);
      if (scanFingerprintsDirty) {
        await _saveScanMetadataFingerprints(prefs, scanFingerprints);
      }
      if (migratedIdsDirty) {
        await _saveMigratedIds(prefs, migratedIds);
      }

      // Clean up missing folders
      await _removeStaleEntries(existingGames, libraryPath);

      _log.info('Scan',
          'Scan Complete: processed ${parsedGames.length}/${foldersToProcess.length}, skipped $skippedCount (unchanged)');
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
      await scanGameLibrary(libraryPath,
          ignoreFolders: ignoreFolders, blacklistPaths: blacklistPaths);
    }
  }

  Map<String, String> _loadScanMetadataFingerprints(AppSettings prefs) {
    final raw = prefs.getString(AppSettings.scanMetadataFingerprintsKey) ?? '';
    if (raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      _log.warning('Scan', '扫描缓存解析失败，将重建缓存: $e');
      return <String, String>{};
    }
  }

  Future<void> _saveScanMetadataFingerprints(
    AppSettings prefs,
    Map<String, String> fingerprints,
  ) async {
    await prefs.setString(
      AppSettings.scanMetadataFingerprintsKey,
      jsonEncode(fingerprints),
    );
    await prefs.flush();
  }

  Future<void> _saveMigratedIds(
    AppSettings prefs,
    Set<String> migratedIds,
  ) async {
    final sortedIds = migratedIds.toList()
      ..sort((left, right) {
        final leftId = int.tryParse(left);
        final rightId = int.tryParse(right);
        if (leftId != null && rightId != null) {
          return leftId.compareTo(rightId);
        }
        return left.compareTo(right);
      });
    await prefs.setStringList(AppSettings.startupMigratedGameIdsKey, sortedIds);
    await prefs.flush();
  }

  Future<String?> _metadataFingerprint(File metadataFile) async {
    if (!await metadataFile.exists()) return null;
    final stat = await metadataFile.stat();
    return '${stat.modified.millisecondsSinceEpoch}:${stat.size}';
  }

  String _normalizedPathKey(String value) =>
      path.normalize(value).replaceAll('/', '\\').toLowerCase();

  Future<List<String>> _scanGameFolders(
      String rootPath, List<String> ignoreFolders) async {
    final folders = <String>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return folders;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);
        final folderNameLower = folderName.toLowerCase();
        // 忽略用户设置的文件夹、Cleared目录（已通关）和Backup目录（已通关备份）
        if (ignoreFolders.any((f) => f.toLowerCase() == folderNameLower) ||
            folderNameLower == GameDataPaths.dataDirName.toLowerCase() ||
            folderNameLower == 'backup' ||
            folderNameLower == 'cleared') {
          continue;
        }
        final metadataFile =
            await GameDataPaths.existingMetadataFile(entity.path);
        if (await metadataFile.exists()) {
          folders.add(entity.path);
        } else {
          folders.addAll(await _scanGameFolders(entity.path, ignoreFolders));
        }
      }
    }
    return folders;
  }

  Future<_ParsedGameData?> _parseFolder(
    String folderPath,
    Map<String, Game> existingGameMap,
    Set<String> migratedIds,
  ) async {
    try {
      final existingGame = existingGameMap[folderPath];
      final existingId = existingGame?.id;
      final migrationAlreadyDone =
          existingId != null && migratedIds.contains(existingId.toString());
      final hasLegacyGameData =
          await _migrationService.hasLegacyGameData(folderPath);
      var migrationChecked = migrationAlreadyDone;
      if (hasLegacyGameData) {
        final result = await _migrationService.migrateGameDirectory(
          folderPath,
          gameId: existingId,
          logNoop: false,
        );
        migrationChecked = result.gameDirectoryExists;
        if (result.changed) {
          _log.info(
            'Scan',
            '迁移旧版工作目录后继续解析: id=${existingId ?? '-'}, path=$folderPath',
          );
        }
      }

      final metadataFile = await GameDataPaths.existingMetadataFile(folderPath);
      final fingerprint = await _metadataFingerprint(metadataFile);
      if (fingerprint == null) return null;

      Map<String, dynamic>? metadata;
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        metadata = jsonDecode(content) as Map<String, dynamic>;
      }

      final sourceUrlFile =
          await GameDataPaths.existingSourceUrlFile(folderPath);
      String? sourceUrl;
      if (await sourceUrlFile.exists()) {
        sourceUrl = (await sourceUrlFile.readAsString()).trim();
      }

      final imageDir = await GameDataPaths.existingImagesDir(folderPath);
      final List<String> imagePaths = [];
      if (await imageDir.exists()) {
        await for (final entity in imageDir.list(followLinks: false)) {
          if (entity is File) {
            final ext = path.extension(entity.path).toLowerCase();
            if (ext == '.jpg' ||
                ext == '.jpeg' ||
                ext == '.png' ||
                ext == '.gif' ||
                ext == '.webp') {
              imagePaths.add(entity.path);
            }
          }
        }
        imagePaths.sort();
      }

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
        isCleared: existingGame?.isCleared ?? false,
        guide: metadata?['guide'] as String?,
        metadataFingerprint: fingerprint,
        migrationChecked: migrationChecked,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Scan] Error parsing $folderPath: $e');
      return null;
    }
  }

  Future<void> _batchWriteToDatabase(List<_ParsedGameData> parsedGames,
      Map<String, Game> existingGameMap) async {
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
        await txn.insert(
            'tags',
            {
              'name': entry.value,
              'type': parts[0],
              'display_name': entry.value,
              'is_favorite': 0,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
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
          'is_cleared': data.isCleared ? 1 : 0,
          'guide': data.guide,
        };

        int gameId;
        if (existing != null) {
          // 更新游戏时保留原有的 added_time
          await txn.update('games', gameMap,
              where: 'id = ?', whereArgs: [existing.id]);
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
            await txn.insert(
                'game_tag_relation',
                {
                  'game_id': gameId,
                  'tag_id': tagId,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (data.seriesName != null && data.seriesName!.isNotEmpty) {
          final tagId = tagIdMap['${Tag.typeSeries}:${data.seriesName}'];
          if (tagId != null) {
            await txn.insert(
                'game_tag_relation',
                {
                  'game_id': gameId,
                  'tag_id': tagId,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        // Batch insert game images
        // 保留外部图片（URL图片/应用存储目录图片，非游戏目录下的图片）
        final sep = Platform.pathSeparator;
        final gameImagesDir1 =
            '${GameDataPaths.imagesDir(data.folderPath).path}$sep';
        final gameImagesDir2 =
            '${GameDataPaths.legacyImagesDir(data.folderPath).path}$sep';
        final gameImagesDir3 =
            '${GameDataPaths.legacySingularImageDir(data.folderPath).path}$sep';
        final externalImages = await txn.query(
          'game_images',
          where:
              'game_id = ? AND image_path NOT LIKE ? AND image_path NOT LIKE ? AND image_path NOT LIKE ?',
          whereArgs: [
            gameId,
            '$gameImagesDir1%',
            '$gameImagesDir2%',
            '$gameImagesDir3%'
          ],
        );

        // 删除所有图片
        await txn
            .delete('game_images', where: 'game_id = ?', whereArgs: [gameId]);

        // 合并本地图片和外部图片，按原有 sort_order 排序后插入
        final allImages = <Map<String, dynamic>>[];
        for (int i = 0; i < data.imagePaths.length; i++) {
          allImages.add({'image_path': data.imagePaths[i], 'sort_order': i});
        }
        for (final img in externalImages) {
          allImages.add({
            'image_path': img['image_path'],
            'sort_order': img['sort_order']
          });
        }
        allImages.sort((a, b) =>
            (a['sort_order'] as int).compareTo(b['sort_order'] as int));

        if (allImages.isNotEmpty) {
          final batch = txn.batch();
          for (final img in allImages) {
            batch.insert('game_images', {
              'game_id': gameId,
              'image_path': img['image_path'],
              'sort_order': img['sort_order'],
            });
          }
          await batch.commit(noResult: true);
        }
      }
    });
  }

  Future<void> _removeStaleEntries(
    List<Game> existingGames,
    String libraryPath,
  ) async {
    final normalizedLibraryPath = _normalizedPathKey(libraryPath);

    for (final game in existingGames) {
      try {
        final storedPath = game.id == null
            ? game.path
            : await _gameRepository.getStoredGamePath(game.id!) ?? game.path;
        final storedGame =
            storedPath == game.path ? game : game.copyWith(path: storedPath);
        final dir = Directory(storedPath);
        if (game.isCleared) {
          if (!await dir.exists() && game.id != null) {
            await _clearedMetadataBackupService.refresh(storedGame);
            final backupPath =
                await _gameRepository.findBackupPathForGame(storedGame);
            if (backupPath != null) {
              await _gameRepository.updateGamePath(game.id!, backupPath);
            }
            final refreshed = await _gameRepository.getGameById(game.id!);
            if (refreshed != null) {
              await _clearedMetadataBackupService.refresh(refreshed);
            }
            if (kDebugMode) {
              debugPrint(backupPath == null
                  ? '[Scan] Kept cleared metadata for missing folder: $storedPath'
                  : '[Scan] Switched cleared game to Backup: $backupPath');
            }
          }
          continue;
        }

        if (!_normalizedPathKey(storedPath).startsWith(normalizedLibraryPath)) {
          continue;
        }

        if (!await dir.exists()) {
          await _gameRepository.deleteGame(game.id!);
          if (kDebugMode) {
            debugPrint(
                '[Scan] Removed DB entry for missing folder: $storedPath');
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Scan] Error checking game folder: $e');
      }
    }
  }
}
