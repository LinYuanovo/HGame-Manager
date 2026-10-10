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

    // 旧布局标记：根目录 metadata.json 是旧版管理器刮削必写的文件。
    // 只有它存在时，复数 images/ 才可能是管理器旧图片目录（允许整体迁移）；
    // 否则 images/image 目录与游戏自带资源目录同名，只能按引用证据逐文件迁移。
    final rootMetadataExisted =
        await GameDataPaths.legacyMetadataFile(gamePath).exists();
    final referenceCorpus = await _collectReferenceCorpus(gamePath, gameId);

    changed |= await _moveFileWithConflict(
      GameDataPaths.legacyMetadataFile(gamePath),
      GameDataPaths.metadataFile(gamePath),
    );
    changed |= await _moveFileWithConflict(
      GameDataPaths.legacySourceUrlFile(gamePath),
      GameDataPaths.sourceUrlFile(gamePath),
    );

    final pluralLegacyDir = GameDataPaths.legacyImagesDir(gamePath);
    if (await pluralLegacyDir.exists()) {
      // 旧布局（根目录 metadata.json 曾存在）下管理器确实写过 images/，
      // 但该目录也可能混有游戏自带资源图（旧版与管理器共用目录名）：
      // 仅迁移「被引用 ∨ 管理器命名」的文件，资源图保持原位；
      // 未被引用的纯数字图（旧刮削命名与游戏 CG 撞名）从严不迁移，
      // 由 existingImagesDir 复数兜底继续读取，无损降级
      changed |= await _moveReferencedFiles(
        pluralLegacyDir,
        gamePath,
        referenceCorpus,
        imagePathMap,
        managedNameTest: rootMetadataExisted
            ? GameDataPaths.isManagedImageFileName
            : null,
      );
    }
    // 单数 image 从未由管理器使用（游戏常见资源目录名），仅迁移被引用的文件
    changed |= await _moveReferencedFiles(
      GameDataPaths.legacySingularImageDir(gamePath),
      gamePath,
      referenceCorpus,
      imagePathMap,
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
    if (await GameDataPaths.legacyBackupDir(gamePath).exists()) return true;
    // images/image 目录与游戏自带资源目录同名：缺少根目录管理器标记
    // （metadata.json / source_url.txt）时不视为旧布局，避免为纯游戏目录
    // 触发迁移检查和 HGMDatas 空目录创建
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

  /// 收集图片路径引用语料（新旧 metadata.json 全文 + 数据库正文与图片记录），
  /// 用于判定旧版目录中的文件是否由管理器引用（路径变体：小写、正斜杠）。
  /// metadata 为 JSON 文本，路径引用含 `\\` 转义，需同时提供反转义变体
  Future<String> _collectReferenceCorpus(String gamePath, int? gameId) async {
    final parts = <String>[];

    for (final file in [
      GameDataPaths.legacyMetadataFile(gamePath),
      GameDataPaths.metadataFile(gamePath),
    ]) {
      if (await file.exists()) {
        try {
          final raw = await file.readAsString();
          parts.add(raw);
          parts.add(raw.replaceAll('\\\\', '\\'));
        } catch (_) {}
      }
    }

    final repo = _gameRepository;
    if (repo != null && gameId != null) {
      try {
        final game = await repo.getGameById(gameId);
        if (game != null) {
          parts.add(game.intro ?? '');
          parts.add(game.features ?? '');
          parts.add(game.changelog ?? '');
          parts.add(game.guide ?? '');
        }
        for (final image in await repo.getGameImages(gameId)) {
          parts.add(image.imagePath);
        }
      } catch (_) {}
    }

    return parts.join('\n').toLowerCase().replaceAll('\\', '/');
  }

  /// 仅迁移「被引用语料命中 ∨ 符合管理器命名」的文件（保留相对路径结构），
  /// 其余文件保持原位。用于无法确认目录归属时的保守迁移：
  /// 游戏自带资源目录不受影响。
  Future<bool> _moveReferencedFiles(
    Directory source,
    String gamePath,
    String referenceCorpus,
    Map<String, String> imagePathMap, {
    bool Function(String fileName)? managedNameTest,
  }) async {
    if (!await source.exists()) return false;

    final files = <File>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) files.add(entity);
    }

    var movedAny = false;
    for (final file in files) {
      final referenced = referenceCorpus.isNotEmpty &&
          referenceCorpus
              .contains(file.path.toLowerCase().replaceAll('\\', '/'));
      final managedName =
          managedNameTest != null && managedNameTest(path.basename(file.path));
      if (!referenced && !managedName) continue;

      final relativePath = path.relative(file.path, from: source.path);
      final imageTarget = await GameDataPaths.ensureImagesDir(gamePath);
      final targetPath = await _nextAvailablePath(
        path.join(imageTarget.path, relativePath),
      );
      final parent = Directory(path.dirname(targetPath));
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      _log.info(_logTag, '迁移被引用的图片: ${file.path} -> $targetPath');
      await file.rename(targetPath);
      imagePathMap[file.path] = targetPath;
      movedAny = true;
    }

    if (movedAny) {
      await _deleteIfEmptyRecursive(source);
    }
    return movedAny;
  }

  Future<void> _deleteIfEmptyRecursive(Directory dir) async {
    if (!await dir.exists()) return;
    final children = await dir.list(followLinks: false).toList();
    for (final child in children) {
      if (child is Directory) {
        await _deleteIfEmptyRecursive(child);
      }
    }
    // 递归清理后仍残留子目录或文件时保留
    if (!await dir.list(followLinks: false).isEmpty) return;
    await dir.delete();
  }

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
