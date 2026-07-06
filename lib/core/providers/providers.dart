import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../utils/app_settings.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../repositories/tool_repository.dart';
import '../services/game_scanner_service.dart';
import '../services/game_launch_service.dart';
import '../services/game_count_service.dart';
import '../services/save_path_service.dart';
import '../services/webdav_service.dart';
import '../services/backup_service.dart';
import '../services/game_move_service.dart';
import '../services/game_data_migration_service.dart';
import '../services/folder_rename_service.dart';
import '../services/dlsite_service.dart';
import '../services/steam_service.dart';
import '../services/fan2d_service.dart';
import '../services/pilipili_service.dart';
import '../models/models.dart';
import '../../scraper/parse_utils.dart';
import '../models/context_menu_config.dart';
import '../services/process_probe.dart';
import '../utils/backup_image_reference_resolver.dart';
import '../utils/cleared_game_path_utils.dart';
import '../utils/game_data_paths.dart';

final sharedPreferencesProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('AppSettings not initialized');
});

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository();
});

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository();
});

final toolRepositoryProvider = Provider<ToolRepository>((ref) {
  return ToolRepository();
});

final gameScannerServiceProvider = Provider<GameScannerService>((ref) {
  final service = GameScannerService(
    gameRepository: ref.watch(gameRepositoryProvider),
    tagRepository: ref.watch(tagRepositoryProvider),
  );
  service.onGameProcessed = () {
    ref.invalidate(allGamesProvider);
    ref.invalidate(playedGamesProvider);
    ref.invalidate(favoriteGamesProvider);
    ref.invalidate(allTagsProvider);
    ref.invalidate(allSeriesProvider);
  };
  service.onProgress = (processed, total) {
    ref.read(scanProcessedProvider.notifier).state = processed;
    ref.read(scanTotalProvider.notifier).state = total;
  };
  service.shouldCancel = () => ref.read(scanCancelProvider);
  return service;
});

final processProbeProvider = Provider<ProcessProbe>((ref) {
  return const WindowsProcessProbe();
});

final gameLaunchServiceProvider = Provider<GameLaunchService>((ref) {
  return GameLaunchService(
    gameRepository: ref.read(gameRepositoryProvider),
    toolRepository: ref.read(toolRepositoryProvider),
    savePathService: ref.read(savePathServiceProvider),
    processProbe: ref.read(processProbeProvider),
  );
});

final gameCountServiceProvider = Provider<GameCountService>((ref) {
  return GameCountService(ref);
});

final webdavServiceProvider = Provider<WebdavService>((ref) {
  return WebdavService();
});

/// 存档备份服务 Provider
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService();
});

final gameDataMigrationServiceProvider =
    Provider<GameDataMigrationService>((ref) {
  return GameDataMigrationService(
    gameRepository: ref.read(gameRepositoryProvider),
  );
});

final gameMoveServiceProvider = Provider<GameMoveService>((ref) {
  return GameMoveService(
    gameRepository: ref.read(gameRepositoryProvider),
  );
});

final folderRenameServiceProvider = Provider<FolderRenameService>((ref) {
  return FolderRenameService(
    gameRepository: ref.read(gameRepositoryProvider),
  );
});

final dlsiteServiceProvider = Provider<DlsiteService>((ref) => DlsiteService());
final steamServiceProvider = Provider<SteamService>((ref) => SteamService());
final fan2dServiceProvider = Provider<Fan2dService>((ref) => Fan2dService());
final pilipiliServiceProvider = Provider<PilipiliService>((ref) {
  return PilipiliService();
});

final allGamesProvider = FutureProvider<List<Game>>((ref) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final keepPlayed = prefs.getBool(AppSettings.keepPlayedInGamesKey) ?? false;

    if (keepPlayed) {
      return await repository.getAllGames();
    } else {
      return await repository.getUnplayedUnclearedGames();
    }
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Games: $e\n$stackTrace');
    }
    rethrow;
  }
});

final clearedGamesProvider = FutureProvider<List<Game>>((ref) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final allGames = await repository.getAllGames();

    // Read all sorted paths
    final rawSorted = prefs.getString('sorted_paths') ?? '';
    final sortedPathList = <String>[];
    if (rawSorted.startsWith('{')) {
      try {
        final decoded = jsonDecode(rawSorted) as Map<String, dynamic>;
        for (final v in decoded.values) {
          final sp = v?.toString() ?? '';
          if (sp.isNotEmpty) sortedPathList.add(sp);
        }
      } catch (_) {
        // JSON解析失败时使用空列表
      }
    }
    // Backward compatibility
    if (sortedPathList.isEmpty) {
      final oldSorted = prefs.getString('sorted_path') ?? '';
      if (oldSorted.isNotEmpty) sortedPathList.add(oldSorted);
    }

    // Read all cleared paths
    final rawCleared = prefs.getString('cleared_paths') ?? '';
    final clearedPathList = <String>[];
    if (rawCleared.startsWith('{')) {
      try {
        final decodedCleared = jsonDecode(rawCleared) as Map<String, dynamic>;
        for (final v in decodedCleared.values) {
          final cp = v?.toString() ?? '';
          if (cp.isNotEmpty) clearedPathList.add(cp);
        }
      } catch (_) {
        // JSON解析失败时使用空列表
      }
    }

    final sep = Platform.pathSeparator;
    // 旧格式：路径包含 /Cleared/ 的游戏
    final dbClearedGames = allGames
        .where((g) =>
            g.path.contains('${sep}Cleared$sep') &&
            !ClearedGamePathUtils.hasBackupSegment(g.path))
        .toList();
    // 新格式：路径在 cleared_paths 目录下的游戏
    final dbNewClearedGames = allGames.where((g) {
      final normalizedGamePath = g.path.replaceAll('\\', '/').toLowerCase();
      for (final cp in clearedPathList) {
        final normalizedCleared = cp.replaceAll('\\', '/').toLowerCase();
        if (normalizedGamePath.startsWith(normalizedCleared) &&
            !ClearedGamePathUtils.hasBackupSegment(g.path)) {
          return true;
        }
      }
      return false;
    }).toList();
    final allClearedGames = [...dbClearedGames, ...dbNewClearedGames];

    final result = <String, Game>{};
    final allGamesByPath = <String, Game>{
      for (final game in allGames) _normalizedPathKey(game.path): game,
    };

    void putPreferredResult(String key, Game game) {
      final existing = result[key];
      if (existing == null || _dataWeight(game) > _dataWeight(existing)) {
        result[key] = game;
      }
    }

    Future<void> addLocalClearedFolders(String clearedPath) async {
      final clearedDir = Directory(clearedPath);
      if (!await clearedDir.exists()) return;

      await for (final entity in clearedDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final folderName = path.basename(entity.path);
        if (folderName.toLowerCase() == 'backup') continue;

        final existingDbGame = await _resolveDbGameForDirectory(
          repository: repository,
          allGames: allGames,
          allGamesByPath: allGamesByPath,
          folderPath: entity.path,
          fallbackTitle: folderName,
        );
        final localGame = await _loadGameFromDirectory(
          entity.path,
          folderName,
          existingDbGame,
        );
        if (localGame == null) continue;

        final normalizedTitle = removeVersionFromTitle(localGame.title ?? '');
        final key = normalizedTitle.toLowerCase();
        putPreferredResult(key, localGame.copyWith(title: normalizedTitle));
      }
    }

    // 先处理本地游戏，用 metadata title 作为 key（去除版本号后比较）
    for (final game in allClearedGames) {
      final dir = Directory(game.path);
      if (await dir.exists()) {
        String title = game.title ?? path.basename(game.path);
        try {
          final metadataFile =
              await GameDataPaths.existingMetadataFile(game.path);
          if (await metadataFile.exists()) {
            final content = await metadataFile.readAsString();
            final metadata = jsonDecode(content) as Map<String, dynamic>;
            if (metadata['title'] != null &&
                (metadata['title'] as String).isNotEmpty) {
              title = metadata['title'] as String;
            }
          }
        } catch (e) {
          debugPrint('[LOCAL] metadata read error: $e');
        }
        final normalizedTitle = removeVersionFromTitle(title);
        // debugPrint('[LOCAL] final title: $title -> normalized: $normalizedTitle');
        putPreferredResult(
          normalizedTitle.toLowerCase(),
          game.copyWith(title: normalizedTitle),
        );
      }
    }

    for (final sortedPath in sortedPathList) {
      await addLocalClearedFolders('$sortedPath${sep}Cleared');
    }
    for (final clearedPath in clearedPathList) {
      await addLocalClearedFolders(clearedPath);
    }

    // 再处理 Backup 目录（旧格式：sortedPath/Cleared/Backup）
    for (final sortedPath in sortedPathList) {
      final backupDir = Directory('$sortedPath${sep}Cleared${sep}Backup');
      if (await backupDir.exists()) {
        // 先处理有 DB 记录但本地文件夹不存在的游戏
        for (final game in allClearedGames) {
          final dir = Directory(game.path);
          if (!await dir.exists()) {
            // 优先用 buildBackupFolderName 匹配新格式备份
            final backupName =
                await FolderRenameService.buildBackupFolderName(game);
            final lookupName = backupName ?? game.title;
            if (lookupName != null &&
                await _hasExistingLocalClearedGameForBackup(
                  backupDir.path,
                  allClearedGames,
                  lookupName,
                  game,
                )) {
              continue;
            }

            Game? backupGame;
            if (backupName != null) {
              backupGame = await _loadGameFromBackup(
                backupDir.path,
                backupName,
                game,
              );
            }
            // 回退到用 game.title 匹配旧格式备份
            backupGame ??= await _loadGameFromBackup(
              backupDir.path,
              game.title,
              game,
            );
            if (backupGame != null) {
              final normalizedTitle =
                  removeVersionFromTitle(backupGame.title ?? '');
              final key = normalizedTitle.toLowerCase();
              putPreferredResult(
                key,
                backupGame.copyWith(title: normalizedTitle),
              );
            }
          }
        }

        // 扫描 Backup 目录中的游戏
        await for (final entity in backupDir.list()) {
          if (entity is Directory) {
            final folderName = path.basename(entity.path);
            final backupPath = entity.path;

            if (await _hasExistingLocalClearedGameForBackup(
              backupDir.path,
              allClearedGames,
              folderName,
              null,
            )) {
              continue;
            }

            // 先检查是否有 DB 记录（通过 path 匹配，规范化路径格式）
            final existingDbGame = await _resolveDbGameForDirectory(
              repository: repository,
              allGames: allGames,
              allGamesByPath: allGamesByPath,
              folderPath: backupPath,
              fallbackTitle: folderName,
            );

            final backupGame = await _loadGameFromBackup(
              backupDir.path,
              folderName,
              existingDbGame,
            );
            if (backupGame != null) {
              final normalizedTitle =
                  removeVersionFromTitle(backupGame.title ?? '');
              final key = normalizedTitle.toLowerCase();
              putPreferredResult(
                key,
                backupGame.copyWith(title: normalizedTitle),
              );
            }
          }
        }
      }
    }

    // 处理 cleared_paths 的 Backup 目录
    for (final clearedPath in clearedPathList) {
      final backupDir = Directory('$clearedPath${sep}Backup');
      if (await backupDir.exists()) {
        // 先处理有 DB 记录但本地文件夹不存在的游戏
        for (final game in allClearedGames) {
          final dir = Directory(game.path);
          if (!await dir.exists()) {
            // 优先用 buildBackupFolderName 匹配新格式备份
            final backupName =
                await FolderRenameService.buildBackupFolderName(game);
            final lookupName = backupName ?? game.title;
            if (lookupName != null &&
                await _hasExistingLocalClearedGameForBackup(
                  backupDir.path,
                  allClearedGames,
                  lookupName,
                  game,
                )) {
              continue;
            }

            Game? backupGame;
            if (backupName != null) {
              backupGame = await _loadGameFromBackup(
                backupDir.path,
                backupName,
                game,
              );
            }
            // 回退到用 game.title 匹配旧格式备份
            backupGame ??= await _loadGameFromBackup(
              backupDir.path,
              game.title,
              game,
            );
            if (backupGame != null) {
              final normalizedTitle =
                  removeVersionFromTitle(backupGame.title ?? '');
              final key = normalizedTitle.toLowerCase();
              putPreferredResult(
                key,
                backupGame.copyWith(title: normalizedTitle),
              );
            }
          }
        }

        // 扫描 Backup 目录中的游戏
        await for (final entity in backupDir.list()) {
          if (entity is Directory) {
            final folderName = path.basename(entity.path);
            final backupPath = entity.path;

            if (await _hasExistingLocalClearedGameForBackup(
              backupDir.path,
              allClearedGames,
              folderName,
              null,
            )) {
              continue;
            }

            // 先检查是否有 DB 记录（通过 path 匹配，规范化路径格式）
            final existingDbGame = await _resolveDbGameForDirectory(
              repository: repository,
              allGames: allGames,
              allGamesByPath: allGamesByPath,
              folderPath: backupPath,
              fallbackTitle: folderName,
            );

            final backupGame = await _loadGameFromBackup(
              backupDir.path,
              folderName,
              existingDbGame,
            );
            if (backupGame != null) {
              final normalizedTitle =
                  removeVersionFromTitle(backupGame.title ?? '');
              final key = normalizedTitle.toLowerCase();
              putPreferredResult(
                key,
                backupGame.copyWith(title: normalizedTitle),
              );
            }
          }
        }
      }
    }

    return result.values.toList();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Cleared Games: $e\n$stackTrace');
    }
    rethrow;
  }
});

/// 通过备份文件夹名匹配 DB 中的游戏记录
Future<Game?> _findDbGameByBackupName(
    List<Game> allGames, String backupFolderName) async {
  final rules = await FolderRenameService.loadRules();
  for (final game in allGames) {
    final name = FolderRenameService.buildNameFromRules(rules, game);
    if (name.isNotEmpty) {
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      if (sanitized == backupFolderName) {
        return game;
      }
    }
  }
  return null;
}

Future<Game?> _resolveDbGameForDirectory({
  required GameRepository repository,
  required List<Game> allGames,
  required Map<String, Game> allGamesByPath,
  required String folderPath,
  required String fallbackTitle,
}) async {
  final pathKey = _normalizedPathKey(folderPath);
  final exact = allGamesByPath[pathKey];

  final identity = await _readDirectoryIdentity(folderPath, fallbackTitle);
  final candidates = <_LinkedGameCandidate>[];

  if (exact != null) {
    candidates.add(_LinkedGameCandidate(exact, 900));
  }

  final sourceUrlKey = _sourceUrlKey(identity.sourceUrl);
  if (sourceUrlKey != null) {
    for (final game in allGames) {
      if (game.id == exact?.id) continue;
      if (_sourceUrlKey(game.sourceUrl) == sourceUrlKey) {
        candidates.add(_LinkedGameCandidate(game, 980));
      }
    }
  }

  final backupNameMatch = await _findDbGameByBackupName(allGames, fallbackTitle);
  if (backupNameMatch != null && backupNameMatch.id != exact?.id) {
    candidates.add(_LinkedGameCandidate(
      backupNameMatch,
      940,
    ));
  }

  final identityNames = <String>{
    fallbackTitle,
    if (identity.title != null && identity.title!.isNotEmpty)
      removeVersionFromTitle(identity.title!),
  };
  for (final game in allGames) {
    if (game.id == exact?.id) continue;
    final gameNames = <String>{
      path.basename(game.path),
      if (game.title != null && game.title!.isNotEmpty)
        removeVersionFromTitle(game.title!),
    };
    for (final left in identityNames) {
      for (final right in gameNames) {
        if (ClearedGamePathUtils.isLikelySameGameName(left, right)) {
          candidates.add(_LinkedGameCandidate(game, 850));
        }
      }
    }
  }

  if (candidates.isEmpty) return null;
  final selected = _selectLinkedGameCandidate(candidates, exact);
  final best = selected.game;

  if (best.id != null) {
    final storedPath = await repository.getStoredGamePath(best.id!);
    final oldPath = storedPath ?? best.path;
    if (_normalizedPathKey(oldPath) == pathKey) return best;

    final storedPathOwner = await repository.getStoredGameByPath(folderPath);
    final pathOwner = storedPathOwner ?? allGamesByPath[pathKey];
    if (pathOwner == null || _sameGameRecord(pathOwner, best)) {
      await repository.updateGamePath(best.id!, folderPath);
      await GameDataMigrationService(gameRepository: repository)
          .rewriteGamePathReferences(
        gameId: best.id!,
        oldPath: oldPath,
        newPath: folderPath,
      );
      allGamesByPath.remove(_normalizedPathKey(oldPath));
      allGamesByPath.remove(_normalizedPathKey(best.path));
      final migrated = best.copyWith(path: folderPath);
      allGamesByPath[pathKey] = migrated;
      return migrated;
    }
    if (pathOwner.id != null && _dataWeight(best) > _dataWeight(pathOwner)) {
      final mergedBest = _mergeLinkedGameData(best, pathOwner);
      await repository.updateGame(mergedBest.copyWith(path: oldPath));
      await repository.mergeDuplicateGamePath(
        keepGameId: best.id!,
        duplicateGameId: pathOwner.id!,
        targetPath: folderPath,
      );
      await GameDataMigrationService(gameRepository: repository)
          .rewriteGamePathReferences(
        gameId: best.id!,
        oldPath: oldPath,
        newPath: folderPath,
      );
      allGamesByPath.remove(_normalizedPathKey(oldPath));
      allGamesByPath.remove(_normalizedPathKey(best.path));
      allGamesByPath.remove(pathKey);
      final migrated = mergedBest.copyWith(path: folderPath);
      allGamesByPath[pathKey] = migrated;
      return migrated;
    }
    return pathOwner;
  }

  return best;
}

_LinkedGameCandidate _selectLinkedGameCandidate(
  List<_LinkedGameCandidate> candidates,
  Game? exact,
) {
  candidates.sort((a, b) => b.score.compareTo(a.score));
  var selected = candidates.first;
  if (exact == null) return selected;

  final exactWeight = _dataWeight(exact);
  final richerCandidates = candidates
      .where((candidate) =>
          !_sameGameRecord(candidate.game, exact) &&
          _dataWeight(candidate.game) > exactWeight)
      .toList()
    ..sort((a, b) {
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      return _dataWeight(b.game).compareTo(_dataWeight(a.game));
    });

  if (richerCandidates.isEmpty) return selected;

  final richer = richerCandidates.first;
  final dataGap = _dataWeight(richer.game) - exactWeight;
  if (richer.priority >= 940 || exactWeight == 0 || dataGap >= 20) {
    selected = richer;
  }
  return selected;
}

Game _mergeLinkedGameData(Game primary, Game fallback) {
  return primary.copyWith(
    title: _preferText(primary.title, fallback.title),
    version: _preferText(primary.version, fallback.version),
    intro: _preferText(primary.intro, fallback.intro),
    features: _preferText(primary.features, fallback.features),
    changelog: _preferText(primary.changelog, fallback.changelog),
    downloadUrl: _preferText(primary.downloadUrl, fallback.downloadUrl),
    sourceUrl: _preferText(primary.sourceUrl, fallback.sourceUrl),
    playCount: primary.playCount >= fallback.playCount
        ? primary.playCount
        : fallback.playCount,
    lastPlayedTime: _latestDate(primary.lastPlayedTime, fallback.lastPlayedTime),
    addedTime: _earliestDate(primary.addedTime, fallback.addedTime),
    isFavorite: primary.isFavorite || fallback.isFavorite,
    isPlayed: primary.isPlayed || fallback.isPlayed,
    tags: _mergeTags(primary.tags, fallback.tags),
    images: _mergeImages(primary.images, fallback.images),
    coverIndex: primary.coverIndex != 0 ? primary.coverIndex : fallback.coverIndex,
    rating: primary.rating > 0 ? primary.rating : fallback.rating,
    review: _preferText(primary.review, fallback.review),
    savePath: _preferText(primary.savePath, fallback.savePath),
    playDuration: primary.playDuration >= fallback.playDuration
        ? primary.playDuration
        : fallback.playDuration,
    maker: _preferText(primary.maker, fallback.maker),
    makerUrl: _preferText(primary.makerUrl, fallback.makerUrl),
    gameLauncher: _preferText(primary.gameLauncher, fallback.gameLauncher),
    launcherLocked: primary.launcherLocked || fallback.launcherLocked,
    useLocaleEmulator: primary.useLocaleEmulator || fallback.useLocaleEmulator,
    guide: _preferText(primary.guide, fallback.guide),
    introScrollPosition: primary.introScrollPosition != 0
        ? primary.introScrollPosition
        : fallback.introScrollPosition,
    guideScrollPosition: primary.guideScrollPosition != 0
        ? primary.guideScrollPosition
        : fallback.guideScrollPosition,
  );
}

String? _preferText(String? primary, String? fallback) {
  if (primary != null && primary.trim().isNotEmpty) return primary;
  if (fallback != null && fallback.trim().isNotEmpty) return fallback;
  return primary ?? fallback;
}

DateTime? _latestDate(DateTime? primary, DateTime? fallback) {
  if (primary == null) return fallback;
  if (fallback == null) return primary;
  return primary.isAfter(fallback) ? primary : fallback;
}

DateTime? _earliestDate(DateTime? primary, DateTime? fallback) {
  if (primary == null) return fallback;
  if (fallback == null) return primary;
  return primary.isBefore(fallback) ? primary : fallback;
}

List<Tag> _mergeTags(List<Tag> primary, List<Tag> fallback) {
  final result = <String, Tag>{};
  for (final tag in [...primary, ...fallback]) {
    result['${tag.type}:${tag.name.toLowerCase()}'] = tag;
  }
  return result.values.toList();
}

List<GameImage> _mergeImages(List<GameImage> primary, List<GameImage> fallback) {
  final result = <String, GameImage>{};
  for (final image in [...primary, ...fallback]) {
    final key = _normalizedPathKey(image.imagePath);
    result.putIfAbsent(key, () => image);
  }
  return result.values.toList();
}

Future<_DirectoryIdentity> _readDirectoryIdentity(
  String folderPath,
  String fallbackTitle,
) async {
  String? title;
  String? sourceUrl;

  try {
    final metadataFile = await GameDataPaths.existingMetadataFile(folderPath);
    if (await metadataFile.exists()) {
      final metadata =
          jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      title = metadata['title'] as String?;
      sourceUrl = metadata['source_url'] as String?;
    }
  } catch (_) {}

  try {
    final sourceUrlFile = await GameDataPaths.existingSourceUrlFile(folderPath);
    if (await sourceUrlFile.exists()) {
      final value = (await sourceUrlFile.readAsString()).trim();
      if (value.isNotEmpty) sourceUrl = value;
    }
  } catch (_) {}

  return _DirectoryIdentity(
    title: title == null || title.isEmpty ? fallbackTitle : title,
    sourceUrl: sourceUrl,
  );
}

String? _sourceUrlKey(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value.trim().toLowerCase();
}

int _dataWeight(Game game) {
  var score = 0;
  score += game.playCount * 20;
  score += game.playDuration ~/ 60;
  if (game.lastPlayedTime != null) score += 20;
  if (game.isPlayed) score += 20;
  if (game.isFavorite) score += 10;
  if (game.rating > 0) score += 10;
  if (game.review != null && game.review!.isNotEmpty) score += 10;
  if (game.savePath != null && game.savePath!.isNotEmpty) score += 10;
  if (game.tags.isNotEmpty) score += 5;
  return score;
}

class _DirectoryIdentity {
  final String? title;
  final String? sourceUrl;

  const _DirectoryIdentity({
    required this.title,
    required this.sourceUrl,
  });
}

class _LinkedGameCandidate {
  final Game game;
  final int priority;

  int get score => priority + _dataWeight(game);

  const _LinkedGameCandidate(this.game, this.priority);
}

String _normalizedPathKey(String value) =>
    value.replaceAll('\\', '/').toLowerCase();

bool _sameGameRecord(Game left, Game right) {
  if (left.id != null && right.id != null) return left.id == right.id;
  return _normalizedPathKey(left.path) == _normalizedPathKey(right.path);
}

bool _isPathInsideDirectory(String childPath, String parentPath) {
  final child = _normalizedPathKey(childPath);
  var parent = _normalizedPathKey(parentPath);
  if (!parent.endsWith('/')) parent = '$parent/';
  return child.startsWith(parent);
}

Future<bool> _hasExistingLocalClearedGameForBackup(
  String backupBasePath,
  List<Game> clearedGames,
  String backupFolderName,
  Game? existingDbGame,
) async {
  final clearedDir = Directory(backupBasePath).parent;
  if (existingDbGame != null &&
      !ClearedGamePathUtils.hasBackupSegment(existingDbGame.path) &&
      _isPathInsideDirectory(existingDbGame.path, clearedDir.path) &&
      await Directory(existingDbGame.path).exists()) {
    return true;
  }

  if (await _hasExistingLocalClearedFolderForBackup(
    backupBasePath,
    backupFolderName,
  )) {
    return true;
  }

  for (final game in clearedGames) {
    if (ClearedGamePathUtils.hasBackupSegment(game.path)) continue;
    if (!await Directory(game.path).exists()) continue;

    final candidates = <String>{
      path.basename(game.path),
      if (game.title != null) removeVersionFromTitle(game.title!),
    };
    for (final candidate in candidates) {
      if (ClearedGamePathUtils.isLikelyBackupForLocalName(
        backupFolderName,
        candidate,
      )) {
        return true;
      }
    }
  }

  return false;
}

Future<bool> _hasExistingLocalClearedFolderForBackup(
  String backupBasePath,
  String backupFolderName,
) async {
  final backupDir = Directory(backupBasePath);
  final clearedDir = backupDir.parent;
  if (!await clearedDir.exists()) return false;

  await for (final entity in clearedDir.list(followLinks: false)) {
    if (entity is! Directory) continue;

    final folderName = path.basename(entity.path);
    if (folderName.toLowerCase() == 'backup') continue;

    if (ClearedGamePathUtils.isLikelyBackupForLocalName(
      backupFolderName,
      folderName,
    )) {
      return true;
    }

    try {
      final metadataFile =
          await GameDataPaths.existingMetadataFile(entity.path);
      if (await metadataFile.exists()) {
        final metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
        final title = metadata['title'] as String?;
        if (title != null &&
            ClearedGamePathUtils.isLikelyBackupForLocalName(
              backupFolderName,
              removeVersionFromTitle(title),
            )) {
          return true;
        }
      }
    } catch (_) {
      // 本地目录元数据损坏时只跳过元数据标题匹配，继续检查其他目录。
    }
  }

  return false;
}

Future<Game?> _loadGameFromBackup(
  String backupBasePath,
  String? gameTitle,
  Game? existingDbGame,
) async {
  if (gameTitle == null || gameTitle.isEmpty) return null;

  final sep = Platform.pathSeparator;
  final sanitizedTitle = gameTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final backupGameDir = Directory('$backupBasePath$sep$sanitizedTitle');

  if (!await backupGameDir.exists()) {
    return null;
  }

  return _loadGameFromDirectory(backupGameDir.path, gameTitle, existingDbGame);
}

Future<Game?> _loadGameFromDirectory(
  String gamePath,
  String fallbackTitle,
  Game? existingDbGame,
) async {
  final gameDir = Directory(gamePath);
  if (!await gameDir.exists()) return null;

  final metadataFile = await GameDataPaths.existingMetadataFile(gameDir.path);
  Map<String, dynamic>? metadata;
  if (await metadataFile.exists()) {
    try {
      final content = await metadataFile.readAsString();
      metadata = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[Cleared] metadata parse error for ${gameDir.path}: $e');
    }
  }

  final sourceUrlFile = await GameDataPaths.existingSourceUrlFile(gameDir.path);
  String? sourceUrl;
  if (await sourceUrlFile.exists()) {
    sourceUrl = (await sourceUrlFile.readAsString()).trim();
  }

  final imageDir = await GameDataPaths.existingImagesDir(gameDir.path);
  final List<String> imagePaths = [];
  if (await imageDir.exists()) {
    await for (final entity in imageDir.list()) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
          imagePaths.add(entity.path);
        }
      }
    }
    imagePaths.sort();
  }

  final game = Game(
    id: existingDbGame?.id,
    path: gameDir.path,
    title:
        (metadata?['title'] as String?) ?? existingDbGame?.title ?? fallbackTitle,
    version: (metadata?['version'] as String?) ?? existingDbGame?.version,
    intro: (metadata?['intro'] as String?) ?? existingDbGame?.intro,
    features: (metadata?['features'] as String?) ?? existingDbGame?.features,
    changelog: (metadata?['changelog'] as String?) ?? existingDbGame?.changelog,
    downloadUrl:
        (metadata?['download_url'] as String?) ?? existingDbGame?.downloadUrl,
    sourceUrl: sourceUrl ??
        (metadata?['source_url'] as String?) ??
        existingDbGame?.sourceUrl,
    playCount: existingDbGame?.playCount ?? 0,
    lastPlayedTime: existingDbGame?.lastPlayedTime,
    addedTime: existingDbGame?.addedTime,
    isFavorite: existingDbGame?.isFavorite ?? false,
    isPlayed: existingDbGame?.isPlayed ?? true,
    tags: existingDbGame?.tags ?? [],
    images: imagePaths
        .asMap()
        .entries
        .map((e) => GameImage(
              gameId: existingDbGame?.id ?? 0,
              imagePath: e.value,
              sortOrder: e.key,
            ))
        .toList(),
    coverIndex: existingDbGame?.coverIndex ?? 0,
    rating: existingDbGame?.rating ?? 0.0,
    review: existingDbGame?.review,
    savePath: existingDbGame?.savePath,
    playDuration: existingDbGame?.playDuration ?? 0,
    maker: (metadata?['maker'] as String?) ?? existingDbGame?.maker,
    makerUrl: (metadata?['maker_url'] as String?) ?? existingDbGame?.makerUrl,
    gameLauncher: existingDbGame?.gameLauncher,
    launcherLocked: existingDbGame?.launcherLocked ?? false,
    useLocaleEmulator: existingDbGame?.useLocaleEmulator ?? false,
    guide: (metadata?['guide'] as String?) ?? existingDbGame?.guide,
    introScrollPosition: existingDbGame?.introScrollPosition ?? 0.0,
    guideScrollPosition: existingDbGame?.guideScrollPosition ?? 0.0,
  );
  return BackupImageReferenceResolver.rewriteGameReferences(game);
}

final playedGamesProvider = FutureProvider<List<Game>>((ref) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    final games = await repository.getPlayedGames();
    return games
        .where((g) => !g.path.contains(
            '${Platform.pathSeparator}Cleared${Platform.pathSeparator}'))
        .toList();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Played Games: $e\n$stackTrace');
    }
    rethrow;
  }
});

final favoriteGamesProvider = FutureProvider<List<Game>>((ref) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    final games = await repository.getFavoriteGames();
    return games;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Favorite Games: $e\n$stackTrace');
    }
    rethrow;
  }
});

final allTagsProvider = FutureProvider<List<Tag>>((ref) async {
  try {
    final repository = ref.watch(tagRepositoryProvider);
    return await repository.getCustomTags();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Tags: $e\n$stackTrace');
    }
    rethrow;
  }
});

final allSeriesProvider = FutureProvider<List<Tag>>((ref) async {
  try {
    final repository = ref.watch(tagRepositoryProvider);
    return await repository.getSeriesTags();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Series: $e\n$stackTrace');
    }
    rethrow;
  }
});

final favoriteTagsProvider = FutureProvider<List<Tag>>((ref) async {
  try {
    final repository = ref.watch(tagRepositoryProvider);
    return await repository.getFavoriteTags();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Favorite Tags: $e\n$stackTrace');
    }
    rethrow;
  }
});

final gamesByTagProvider =
    FutureProvider.family<List<Game>, int>((ref, tagId) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    return await repository.getGamesByTag(tagId);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Games By Tag: $e\n$stackTrace');
    }
    rethrow;
  }
});

final searchGamesProvider =
    FutureProvider.family<List<Game>, String>((ref, query) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    return await repository.searchGames(query);
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Searching Games: $e\n$stackTrace');
    }
    rethrow;
  }
});

final selectedNavIndexProvider =
    StateProvider<int>((ref) => 1); // Default to games page

final viewModeProvider = StateProvider<ViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('view_mode') ?? 0;
  return ViewMode.values[index.clamp(0, ViewMode.values.length - 1)];
});

final sortModeProvider = StateProvider<SortMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final index = prefs.getInt('sort_mode') ?? 0;
  return SortMode.values[index.clamp(0, SortMode.values.length - 1)];
});

final fontSizeProvider = StateProvider<double>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getDouble('font_size') ?? 14.0;
});

final detailFontSizeProvider = StateProvider<double>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getDouble('detail_font_size') ?? 14.0;
});

final isScanningProvider = StateProvider<bool>((ref) => false);
final scanProcessedProvider = StateProvider<int>((ref) => 0);
final scanTotalProvider = StateProvider<int>((ref) => 0);
final scanCancelProvider = StateProvider<bool>((ref) => false);

final pageSizeProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('page_size') ?? 50;
});

final isFixedColumnCountProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('fixed_column_count') ?? false;
});

final fixedColumnCountProvider = StateProvider<int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt('column_count') ?? 3;
});

final savePathServiceProvider = Provider<SavePathService>((ref) {
  return SavePathService();
});

final saveScanProgressProvider = StateProvider<String>((ref) => '');
final isSaveScanningProvider = StateProvider<bool>((ref) => false);

final allToolsProvider = FutureProvider<List<Tool>>((ref) async {
  try {
    final repository = ref.watch(toolRepositoryProvider);
    return await repository.getAllTools();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Tools: $e\n$stackTrace');
    }
    rethrow;
  }
});

final doubleClickLaunchProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool('double_click_launch') ?? false;
});

final currentPageProvider = StateProvider<Map<int, int>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final jsonStr = prefs.getString('current_pages');
  if (jsonStr != null && jsonStr.isNotEmpty) {
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((k, v) => MapEntry(int.parse(k), v as int));
    } catch (_) {
      // JSON解析失败时返回空Map
    }
  }
  return {};
});

/// 右键菜单配置 Provider（普通游戏列表）
final contextMenuGamesProvider =
    StateNotifierProvider<ContextMenuConfigNotifier, ContextMenuConfig>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ContextMenuConfigNotifier(
      prefs, AppSettings.contextMenuGamesKey, 'games');
});

/// 右键菜单配置 Provider（已玩游戏/通关页面）
final contextMenuPlayedProvider =
    StateNotifierProvider<ContextMenuConfigNotifier, ContextMenuConfig>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ContextMenuConfigNotifier(
      prefs, AppSettings.contextMenuPlayedKey, 'played');
});

/// 菜单配置状态管理器
class ContextMenuConfigNotifier extends StateNotifier<ContextMenuConfig> {
  final AppSettings _prefs;
  final String _key;
  final String _mode;

  ContextMenuConfigNotifier(this._prefs, this._key, this._mode)
      : super(const ContextMenuConfig(items: [])) {
    _load();
  }

  void _load() {
    final jsonStr = _prefs.getString(_key);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        state = ContextMenuConfig.fromMap(map);
      } catch (e) {
        state = ContextMenuConfig.defaults(PresetMenuItems.getDefs(_mode));
      }
    } else {
      state = ContextMenuConfig.defaults(PresetMenuItems.getDefs(_mode));
    }
    _migrate();
  }

  /// 迁移旧配置：补入新增的预设菜单项
  void _migrate() {
    final presetDefs = PresetMenuItems.getDefs(_mode);
    final existingIds = state.items.map((i) => i.id).toSet();
    final missing = presetDefs.where((d) => !existingIds.contains(d.id));
    if (missing.isEmpty) return;

    final updated = List<ContextMenuItemState>.from(state.items);
    for (final def in missing) {
      // 查找预设中的位置，插入到相邻项附近
      final presetIndex = presetDefs.indexOf(def);
      int insertAt = updated.length;
      for (int i = presetIndex + 1; i < presetDefs.length; i++) {
        final neighborIdx = updated.indexWhere((e) => e.id == presetDefs[i].id);
        if (neighborIdx >= 0) {
          insertAt = neighborIdx;
          break;
        }
      }
      updated.insert(
          insertAt,
          ContextMenuItemState(
              id: def.id, enabled: def.defaultEnabled, order: insertAt));
    }
    state = ContextMenuConfig(items: updated);
  }

  Future<void> save() async {
    await _prefs.setString(_key, jsonEncode(state.toMap()));
  }

  void toggleItem(String id) {
    final updatedItems = state.items.map((item) {
      if (item.id == id) {
        return item.copyWith(enabled: !item.enabled);
      }
      return item;
    }).toList();
    state = ContextMenuConfig(items: updatedItems);
  }

  void moveItem(String id, int direction) {
    final items = List<ContextMenuItemState>.from(state.sortedItems);
    final index = items.indexWhere((i) => i.id == id);
    if (index < 0) return;

    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= items.length) return;

    final temp = items[index].order;
    items[index] = items[index].copyWith(order: items[newIndex].order);
    items[newIndex] = items[newIndex].copyWith(order: temp);

    state = ContextMenuConfig(items: items);
  }

  void reorderItem(int oldIndex, int newIndex) {
    final items = List<ContextMenuItemState>.from(state.sortedItems);
    if (newIndex > oldIndex) newIndex--;
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);
    for (int i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(order: i);
    }
    state = ContextMenuConfig(items: items);
  }

  void resetToDefaults() {
    state = ContextMenuConfig.defaults(PresetMenuItems.getDefs(_mode));
  }
}

/// 刮削模式配置 Provider
final scrapeModeConfigsProvider =
    StateNotifierProvider<ScrapeModeConfigsNotifier, ScrapeModeConfigs>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ScrapeModeConfigsNotifier(prefs);
});

class ScrapeModeConfigsNotifier extends StateNotifier<ScrapeModeConfigs> {
  final AppSettings _prefs;

  ScrapeModeConfigsNotifier(this._prefs) : super(ScrapeModeConfigs.defaults()) {
    _load();
  }

  void _load() {
    final jsonStr = _prefs.getString(AppSettings.scrapeModeConfigsKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        state = ScrapeModeConfigs.fromMap(map);
      } catch (e) {
        state = _migrateFromGlobal();
      }
    } else {
      state = _migrateFromGlobal();
    }
  }

  ScrapeModeConfigs _migrateFromGlobal() {
    final autoRename =
        _prefs.getBool(AppSettings.autoRenameFoldersKey) ?? false;
    final autoMove = _prefs.getBool(AppSettings.autoMoveToSortedKey) ?? false;
    return ScrapeModeConfigs(configs: {
      ScrapeMode.quickScrape: const ScrapeModeConfig(),
      ScrapeMode.rescrape:
          ScrapeModeConfig(renameFolder: autoRename, moveToSorted: autoMove),
      ScrapeMode.scraperCenter:
          ScrapeModeConfig(renameFolder: autoRename, moveToSorted: autoMove),
      ScrapeMode.singleAdd: const ScrapeModeConfig(),
      ScrapeMode.batchAdd: const ScrapeModeConfig(),
    });
  }

  Future<void> save() async {
    await _prefs.setString(
        AppSettings.scrapeModeConfigsKey, jsonEncode(state.toMap()));
  }

  void updateConfig(ScrapeMode mode, ScrapeModeConfig config) {
    state = ScrapeModeConfigs(configs: {...state.configs, mode: config});
  }

  void resetToDefaults() {
    state = ScrapeModeConfigs.defaults();
  }
}

final noImageModeProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool(AppSettings.noImageModeKey) ?? false;
});

final sidebarRefreshProvider = StateProvider<int>((ref) => 0);
