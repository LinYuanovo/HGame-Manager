import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import 'app_logger.dart';

class GameScannerService {
  final _log = AppLogger.instance;
  final GameRepository _gameRepository;
  final TagRepository _tagRepository;

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
  })  : _gameRepository = gameRepository ?? GameRepository(),
        _tagRepository = tagRepository ?? TagRepository();

  Future<void> scanGameLibrary(String libraryPath, {List<String> ignoreFolders = const []}) async {
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

      final List<String> gameFolders = [];

      gameFolders.addAll(await _scanGameFolders(libraryPath, ignoreFolders));

      if (kDebugMode) {
        debugPrint('[Scan] Found ${gameFolders.length} game folders');
      }

      final existingGames = await _gameRepository.getAllGames();
      final gamePathMap = <String, Game>{};
      for (final g in existingGames) {
        gamePathMap[g.path] = g;
      }

      int processedCount = 0;
      final totalFolders = gameFolders.length;
      onProgress?.call(0, totalFolders);

      for (final folderPath in gameFolders) {
        if (shouldCancel?.call() == true) break;

        try {
          await _processGameFolder(folderPath, gamePathMap);
          processedCount++;
        } catch (e) {
          if (kDebugMode) debugPrint('[Scan] Error processing $folderPath: $e');
        }

        onProgress?.call(processedCount, totalFolders);
        if (processedCount % 5 == 0) {
          onGameProcessed?.call();
        }
      }

      onGameProcessed?.call();

      // Remove games whose folders no longer exist
      for (final game in existingGames) {
        try {
          final dir = Directory(game.path);
          if (!await dir.exists()) {
            await _gameRepository.deleteGame(game.id!);
            if (kDebugMode) debugPrint('[Scan] Removed DB entry for missing folder: ${game.path}');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Scan] Error checking game folder: $e');
        }
      }

      _log.info('Scan', 'Game Scan Complete, processed $processedCount/$totalFolders');
    } catch (e, stackTrace) {
      _log.error('Scan', 'FATAL ERROR in Game Scan', e, stackTrace);
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  Future<List<String>> _scanGameFolders(String rootPath, List<String> ignoreFolders) async {
    final folders = <String>[];
    final dir = Directory(rootPath);
    if (!await dir.exists()) return folders;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);
        if (ignoreFolders.contains(folderName)) {
          continue; // Skip ignored folders
        }
        if (await File(path.join(entity.path, 'source_url.txt')).exists() ||
            await File(path.join(entity.path, 'metadata.json')).exists()) {
          folders.add(entity.path);
        } else {
          folders.addAll(await _scanGameFolders(entity.path, ignoreFolders));
        }
      }
    }
    return folders;
  }

  Future<void> _processGameFolder(
    String folderPath,
    Map<String, Game> existingGameMap,
  ) async {
    // Read source_url.txt
    final sourceUrlFile = File(path.join(folderPath, 'source_url.txt'));
    String? sourceUrl;
    if (await sourceUrlFile.exists()) {
      sourceUrl = (await sourceUrlFile.readAsString()).trim();
    }

    // Read metadata.json if exists
    final metadataFile = File(path.join(folderPath, 'metadata.json'));
    Map<String, dynamic>? metadata;
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        metadata = jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        if (kDebugMode) debugPrint('[Scan] Warning: Failed to parse metadata.json in $folderPath: $e');
      }
    }

    // Scan images from images/ or image/ subdirectory
    var imageDir = Directory(path.join(folderPath, 'images'));
    if (!await imageDir.exists()) {
      imageDir = Directory(path.join(folderPath, 'image'));
    }
    final List<String> imagePaths = [];
    if (await imageDir.exists()) {
      await for (final entity in imageDir.list(followLinks: false)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') {
            imagePaths.add(entity.path);
          }
        }
      }
      imagePaths.sort();
    }

    final existingGame = existingGameMap[folderPath];

    // Check if metadata has been modified since last scan
    if (existingGame != null && await metadataFile.exists()) {
      final stat = await metadataFile.stat();
      final metadataModified = stat.modified;
      final gameAddedTime = existingGame.addedTime;
      if (gameAddedTime != null && !metadataModified.isAfter(gameAddedTime)) {
        // Metadata hasn't changed since last scan, but still update images
        // in case the game folder was moved
        await _updateImages(existingGame.id!, folderPath);
        return;
      }
    }

    final folderName = path.basename(folderPath);

    String? title = metadata?['title'] as String?;
    if (title == null || title.isEmpty) {
      title = folderName;
    }

    final game = Game(
      id: existingGame?.id,
      path: folderPath,
      title: title,
      version: metadata?['version'] as String?,
      intro: metadata?['intro'] as String?,
      features: metadata?['features'] as String?,
      changelog: metadata?['changelog'] as String?,
      downloadUrl: metadata?['download_url'] as String?,
      sourceUrl: sourceUrl ?? metadata?['source_url'] as String?,
      playCount: existingGame?.playCount ?? 0,
      lastPlayedTime: existingGame?.lastPlayedTime,
      addedTime: existingGame?.addedTime,
      isFavorite: existingGame?.isFavorite ?? false,
      isPlayed: existingGame?.isPlayed ?? false,
    );

    int gameId;
    if (existingGame != null) {
      await _gameRepository.updateGame(game);
      gameId = existingGame.id!;
    } else {
      gameId = await _gameRepository.insertGame(game);
    }

    // Save images
    if (imagePaths.isNotEmpty) {
      final images = imagePaths.asMap().entries.map((e) => GameImage(
        gameId: gameId,
        imagePath: e.value,
        sortOrder: e.key,
      )).toList();
      await _gameRepository.setGameImages(gameId, images);
    }

    // Process tags from metadata
    if (metadata != null) {
      final tags = metadata['tags'] as List<dynamic>?;
      if (tags != null) {
        for (final tagName in tags) {
          if (tagName is String && tagName.isNotEmpty) {
            final tagId = await _tagRepository.insertOrGetTag(tagName, Tag.typeCustom);
            await _gameRepository.addTagToGame(gameId, tagId);
          }
        }
      }

      final series = metadata['series'] as String?;
      if (series != null && series.isNotEmpty) {
        final tagId = await _tagRepository.insertOrGetTag(series, Tag.typeSeries);
        await _gameRepository.addTagToGame(gameId, tagId);
      }
    }
  }

  Future<void> _updateImages(int gameId, String folderPath) async {
    // Scan images from images/ or image/ subdirectory
    var imageDir = Directory(path.join(folderPath, 'images'));
    if (!await imageDir.exists()) {
      imageDir = Directory(path.join(folderPath, 'image'));
    }
    final List<String> imagePaths = [];
    if (await imageDir.exists()) {
      await for (final entity in imageDir.list(followLinks: false)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') {
            imagePaths.add(entity.path);
          }
        }
      }
      imagePaths.sort();
    }

    if (imagePaths.isNotEmpty) {
      final images = imagePaths.asMap().entries.map((e) => GameImage(
        gameId: gameId,
        imagePath: e.value,
        sortOrder: e.key,
      )).toList();
      await _gameRepository.setGameImages(gameId, images);
    }
  }
}
