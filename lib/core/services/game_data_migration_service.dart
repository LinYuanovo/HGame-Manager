import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/models.dart';
import '../repositories/game_repository.dart';
import '../utils/game_data_paths.dart';
import '../utils/path_reference_rewriter.dart';
import 'app_logger.dart';

class GameDataMigrationResult {
  final bool changed;
  final Map<String, String> imagePathMap;
  final bool gameDirectoryExists;

  const GameDataMigrationResult({
    required this.changed,
    required this.imagePathMap,
    this.gameDirectoryExists = true,
  });

  static const none = GameDataMigrationResult(
    changed: false,
    imagePathMap: {},
    gameDirectoryExists: false,
  );
}

class GameDataMigrationService {
  static const String _logTag = 'GameDataMigration';

  final GameRepository? _gameRepository;
  final AppLogger _log = AppLogger.instance;

  GameDataMigrationService({GameRepository? gameRepository})
      : _gameRepository = gameRepository;

  Future<GameDataMigrationResult> migrateGameDirectory(
    String gamePath, {
    int? gameId,
    bool logNoop = true,
  }) async {
    final gameDir = Directory(gamePath);
    if (!await gameDir.exists()) {
      _log.warning(
        _logTag,
        '游戏目录不存在，跳过迁移检查: id=${gameId ?? '-'}, path=$gamePath',
      );
      return GameDataMigrationResult.none;
    }

    if (logNoop) {
      _log.info(
        _logTag,
        '检查旧版工作目录: id=${gameId ?? '-'}, path=$gamePath',
      );
    }

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
    if (imagePathMap.isNotEmpty ||
        await _hasLegacyImageReferences(gamePath, gameId)) {
      await _addInferredLegacyImageMappings(gamePath, imagePathMap);
    }

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

    if (changed || logNoop) {
      _log.info(
        _logTag,
        '旧版工作目录检查完成: id=${gameId ?? '-'}, changed=$changed, '
        'imageMappings=${imagePathMap.length}, path=$gamePath',
      );
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
      } catch (e, stackTrace) {
        _log.error(_logTag, '迁移失败: ${game.path}', e, stackTrace);
      }
    }
  }

  Future<bool> hasLegacyGameData(String gamePath) async {
    if (await GameDataPaths.legacyMetadataFile(gamePath).exists()) return true;
    if (await GameDataPaths.legacySourceUrlFile(gamePath).exists()) {
      return true;
    }
    if (await GameDataPaths.legacyImagesDir(gamePath).exists()) return true;
    if (await GameDataPaths.legacySingularImageDir(gamePath).exists()) {
      return true;
    }
    if (await GameDataPaths.legacyBackupDir(gamePath).exists()) return true;
    return false;
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
      _log.info(_logTag, '已更新数据库图片引用: gameId=$gameId');
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
      _log.info(_logTag, '已更新数据库正文路径引用: gameId=$gameId');
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
    _log.info(_logTag, '已更新 metadata 引用: ${metadataFile.path}');
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

  Future<bool> _hasLegacyImageReferences(String gamePath, int? gameId) async {
    final markers = _legacyImageReferenceMarkers(gamePath);
    var metadataText = '';
    final metadataFile = GameDataPaths.metadataFile(gamePath);
    if (await metadataFile.exists()) {
      metadataText = await metadataFile.readAsString();
      if (_containsAnyMarker(metadataText, markers)) return true;
    }

    final repo = _gameRepository;
    if (repo == null || gameId == null) return false;

    final game = await repo.getGameById(gameId);
    if (game == null) return false;
    if (_containsAnyMarker(game.intro, markers) ||
        _containsAnyMarker(game.features, markers) ||
        _containsAnyMarker(game.changelog, markers) ||
        _containsAnyMarker(game.guide, markers)) {
      return true;
    }
    for (final image in game.images) {
      if (_containsAnyMarker(image.imagePath, markers)) return true;
    }
    return false;
  }

  List<String> _legacyImageReferenceMarkers(String gamePath) {
    final legacyPaths = [
      GameDataPaths.legacyImagesDir(gamePath).path,
      GameDataPaths.legacySingularImageDir(gamePath).path,
    ];
    final markers = <String>{};
    for (final legacyPath in legacyPaths) {
      markers.add(legacyPath);
      markers.add(legacyPath.replaceAll('\\', '/'));
      markers.add(legacyPath.replaceAll('\\', '\\\\'));
    }
    return markers.toList();
  }

  bool _containsAnyMarker(String? value, List<String> markers) {
    if (value == null || value.isEmpty) return false;
    return markers.any(value.contains);
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
      _log.info(_logTag, '移动旧版文件: ${source.path} -> ${target.path}');
      await source.rename(target.path);
      return true;
    }

    final sourceStat = await source.stat();
    final targetStat = await target.stat();
    if (sourceStat.modified.isAfter(targetStat.modified)) {
      final legacyTarget = await _nextLegacyPath(target.path);
      _log.info(
        _logTag,
        '旧版文件较新，保留当前文件为 legacy: ${target.path} -> $legacyTarget',
      );
      await target.rename(legacyTarget);
      _log.info(_logTag, '移动旧版文件: ${source.path} -> ${target.path}');
      await source.rename(target.path);
    } else {
      final legacyTarget = await _nextLegacyPath(target.path);
      _log.info(
        _logTag,
        '当前文件较新，旧版文件改名保留: ${source.path} -> $legacyTarget',
      );
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

    _log.info(_logTag, '合并旧版目录: ${source.path} -> ${target.path}');

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
