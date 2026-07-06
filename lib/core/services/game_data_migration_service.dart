import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../utils/game_data_paths.dart';
import '../utils/path_reference_rewriter.dart';

class GameDataMigrationResult {
  final bool changed;
  final Map<String, String> imagePathMap;

  const GameDataMigrationResult({
    required this.changed,
    required this.imagePathMap,
  });

  static const none = GameDataMigrationResult(changed: false, imagePathMap: {});
}

class GameDataMigrationService {
  final GameRepository? _gameRepository;

  GameDataMigrationService({GameRepository? gameRepository})
      : _gameRepository = gameRepository;

  Future<GameDataMigrationResult> migrateGameDirectory(
    String gamePath, {
    int? gameId,
  }) async {
    final gameDir = Directory(gamePath);
    if (!await gameDir.exists()) return GameDataMigrationResult.none;

    var changed = false;
    final imagePathMap = <String, String>{};

    await GameDataPaths.ensureDataDir(gamePath);

    changed |= await _moveFileWithConflict(
      GameDataPaths.legacyMetadataFile(gamePath),
      GameDataPaths.metadataFile(gamePath),
    );
    changed |= await _moveFileWithConflict(
      GameDataPaths.legacySourceUrlFile(gamePath),
      GameDataPaths.sourceUrlFile(gamePath),
    );

    final imageTarget = await GameDataPaths.ensureImagesDir(gamePath);
    changed |= await _mergeDirectory(
      GameDataPaths.legacyImagesDir(gamePath),
      imageTarget,
      imagePathMap: imagePathMap,
    );
    changed |= await _mergeDirectory(
      GameDataPaths.legacySingularImageDir(gamePath),
      imageTarget,
      imagePathMap: imagePathMap,
    );
    await _addInferredLegacyImageMappings(gamePath, imagePathMap);

    final backupTarget = GameDataPaths.backupDir(gamePath);
    changed |= await _mergeDirectory(
      GameDataPaths.legacyBackupDir(gamePath),
      backupTarget,
    );

    if (imagePathMap.isNotEmpty) {
      changed |= await _updateMetadataReferences(gamePath, imagePathMap);
      if (gameId != null && _gameRepository != null) {
        changed |= await _updateDatabaseReferences(gameId, imagePathMap);
      }
    }

    return GameDataMigrationResult(
      changed: changed,
      imagePathMap: Map.unmodifiable(imagePathMap),
    );
  }

  Future<void> migrateExistingGames(List<Game> games) async {
    for (final game in games) {
      if (game.id == null) continue;
      try {
        await migrateGameDirectory(game.path, gameId: game.id);
      } catch (e) {
        debugPrint('[GameDataMigration] 迁移失败: ${game.path}, $e');
      }
    }
  }

  Future<bool> rewriteGamePathReferences({
    required int gameId,
    required String oldPath,
    required String newPath,
  }) async {
    var changed = false;
    final repo = _gameRepository;
    final replacements = {oldPath: newPath};

    if (repo != null) {
      final game = await repo.getGameById(gameId);
      if (game != null) {
        final updatedIntro =
            PathReferenceRewriter.replace(game.intro, replacements);
        final updatedFeatures =
            PathReferenceRewriter.replace(game.features, replacements);
        final updatedChangelog =
            PathReferenceRewriter.replace(game.changelog, replacements);
        final updatedGuide =
            PathReferenceRewriter.replace(game.guide, replacements);
        if (updatedIntro != game.intro ||
            updatedFeatures != game.features ||
            updatedChangelog != game.changelog ||
            updatedGuide != game.guide) {
          await repo.updateGame(game.copyWith(
            intro: updatedIntro,
            features: updatedFeatures,
            changelog: updatedChangelog,
            guide: updatedGuide,
          ));
          changed = true;
        }
      }
    }

    final metadataFile = await GameDataPaths.existingMetadataFile(newPath);
    if (await metadataFile.exists()) {
      final content = await metadataFile.readAsString();
      final updated =
          PathReferenceRewriter.replaceRequired(content, replacements);
      if (updated != content) {
        await metadataFile.writeAsString(updated, flush: true);
        changed = true;
      }
    }

    return changed;
  }

  Future<bool> _updateDatabaseReferences(
    int gameId,
    Map<String, String> imagePathMap,
  ) async {
    final repo = _gameRepository;
    if (repo == null) return false;

    final images = await repo.getGameImages(gameId);
    var changed = false;
    final updatedImages = images.map((img) {
      final newPath = _lookupMovedPath(imagePathMap, img.imagePath);
      if (newPath == null) return img;
      changed = true;
      return GameImage(
        id: img.id,
        gameId: img.gameId,
        imagePath: newPath,
        sortOrder: img.sortOrder,
      );
    }).toList();

    if (changed) {
      await repo.setGameImages(gameId, updatedImages);
    }

    final game = await repo.getGameById(gameId);
    if (game == null) return changed;

    final updatedIntro = _replaceMovedPathReferences(
      game.intro,
      imagePathMap,
    );
    final updatedFeatures = _replaceMovedPathReferences(
      game.features,
      imagePathMap,
    );
    final updatedChangelog = _replaceMovedPathReferences(
      game.changelog,
      imagePathMap,
    );
    final updatedGuide = _replaceMovedPathReferences(
      game.guide,
      imagePathMap,
    );

    final textChanged = updatedIntro != game.intro ||
        updatedFeatures != game.features ||
        updatedChangelog != game.changelog ||
        updatedGuide != game.guide;

    if (textChanged) {
      await repo.updateGame(game.copyWith(
        intro: updatedIntro,
        features: updatedFeatures,
        changelog: updatedChangelog,
        guide: updatedGuide,
      ));
      changed = true;
    }
    return changed;
  }

  Future<bool> _updateMetadataReferences(
    String gamePath,
    Map<String, String> imagePathMap,
  ) async {
    final metadataFile = GameDataPaths.metadataFile(gamePath);
    if (!await metadataFile.exists()) return false;

    final original = await metadataFile.readAsString();
    final updated =
        PathReferenceRewriter.replaceRequired(original, imagePathMap);
    if (updated == original) return false;

    await metadataFile.writeAsString(updated);
    return true;
  }

  String? _replaceMovedPathReferences(String? value, Map<String, String> map) =>
      PathReferenceRewriter.replace(value, map);

  Future<void> _addInferredLegacyImageMappings(
    String gamePath,
    Map<String, String> imagePathMap,
  ) async {
    final imageDir = GameDataPaths.imagesDir(gamePath);
    if (!await imageDir.exists()) return;

    await for (final entity in imageDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relativePath = path.relative(entity.path, from: imageDir.path);
      imagePathMap.putIfAbsent(
        path.join(GameDataPaths.legacyImagesDir(gamePath).path, relativePath),
        () => entity.path,
      );
      imagePathMap.putIfAbsent(
        path.join(
          GameDataPaths.legacySingularImageDir(gamePath).path,
          relativePath,
        ),
        () => entity.path,
      );
    }
  }

  String? _lookupMovedPath(Map<String, String> movedPaths, String oldPath) {
    final exact = movedPaths[oldPath];
    if (exact != null) return exact;

    final normalizedOld = path.normalize(oldPath).toLowerCase();
    for (final entry in movedPaths.entries) {
      if (path.normalize(entry.key).toLowerCase() == normalizedOld) {
        return entry.value;
      }
    }
    return null;
  }

  Future<bool> _moveFileWithConflict(File source, File target) async {
    if (!await source.exists()) return false;

    final parent = Directory(path.dirname(target.path));
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    if (!await target.exists()) {
      await source.rename(target.path);
      return true;
    }

    final sourceStat = await source.stat();
    final targetStat = await target.stat();
    if (sourceStat.modified.isAfter(targetStat.modified)) {
      final legacyTarget = await _nextLegacyPath(target.path);
      await target.rename(legacyTarget);
      await source.rename(target.path);
    } else {
      final legacyTarget = await _nextLegacyPath(target.path);
      await source.rename(legacyTarget);
    }
    return true;
  }

  Future<bool> _mergeDirectory(
    Directory source,
    Directory target, {
    Map<String, String>? imagePathMap,
  }) async {
    if (!await source.exists()) return false;

    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    var changed = false;
    await for (final entity in source.list(followLinks: false)) {
      final targetPath = await _nextAvailablePath(
        path.join(target.path, path.basename(entity.path)),
      );

      if (entity is File) {
        await entity.rename(targetPath);
        imagePathMap?[entity.path] = targetPath;
        changed = true;
      } else if (entity is Directory) {
        await _moveDirectoryContents(
            entity, Directory(targetPath), imagePathMap);
        changed = true;
      }
    }

    await _deleteIfEmpty(source);
    return changed;
  }

  Future<void> _moveDirectoryContents(
    Directory source,
    Directory target,
    Map<String, String>? imagePathMap,
  ) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    await for (final entity in source.list(followLinks: false)) {
      final targetPath = await _nextAvailablePath(
        path.join(target.path, path.basename(entity.path)),
      );
      if (entity is File) {
        await entity.rename(targetPath);
        imagePathMap?[entity.path] = targetPath;
      } else if (entity is Directory) {
        await _moveDirectoryContents(
            entity, Directory(targetPath), imagePathMap);
      }
    }

    await _deleteIfEmpty(source);
  }

  Future<void> _deleteIfEmpty(Directory dir) async {
    if (!await dir.exists()) return;
    if (!await dir.list(followLinks: false).isEmpty) return;
    await dir.delete();
  }

  Future<String> _nextLegacyPath(String targetPath) async {
    var candidate = '$targetPath.legacy';
    var index = 1;
    while (
        await File(candidate).exists() || await Directory(candidate).exists()) {
      candidate = '$targetPath.legacy.$index';
      index++;
    }
    return candidate;
  }

  Future<String> _nextAvailablePath(String targetPath) async {
    if (!await File(targetPath).exists() &&
        !await Directory(targetPath).exists()) {
      return targetPath;
    }

    final dir = path.dirname(targetPath);
    final extension = path.extension(targetPath);
    final baseName = path.basenameWithoutExtension(targetPath);
    var index = 1;
    while (true) {
      final candidate = path.join(dir, '$baseName ($index)$extension');
      if (!await File(candidate).exists() &&
          !await Directory(candidate).exists()) {
        return candidate;
      }
      index++;
    }
  }
}
