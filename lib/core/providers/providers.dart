import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../utils/app_settings.dart';
import '../repositories/game_repository.dart';
import '../repositories/tag_repository.dart';
import '../services/game_scanner_service.dart';
import '../services/game_count_service.dart';
import '../services/webdav_service.dart';
import '../models/models.dart';

final sharedPreferencesProvider = Provider<AppSettings>((ref) {
  throw UnimplementedError('AppSettings not initialized');
});

final gameRepositoryProvider = Provider<GameRepository>((ref) {
  return GameRepository();
});

final tagRepositoryProvider = Provider<TagRepository>((ref) {
  return TagRepository();
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

final gameCountServiceProvider = Provider<GameCountService>((ref) {
  return GameCountService(ref);
});

final webdavServiceProvider = Provider<WebdavService>((ref) {
  return WebdavService();
});

final allGamesProvider = FutureProvider<List<Game>>((ref) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    final allGames = await repository.getAllGames();
    return allGames.where((g) => !g.path.contains('${Platform.pathSeparator}Cleared${Platform.pathSeparator}')).toList();
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
    final sortedPath = prefs.getString('sorted_path') ?? '';
    final allGames = await repository.getAllGames();

    final sep = Platform.pathSeparator;
    final dbClearedGames = allGames.where((g) =>
      g.path.contains('${sep}Cleared$sep') &&
      !g.path.contains('${sep}Backup$sep')
    ).toList();

    final result = <String, Game>{};
    final backupDir = sortedPath.isNotEmpty
        ? Directory('$sortedPath${sep}Cleared${sep}Backup')
        : null;

    for (final game in dbClearedGames) {
      final dir = Directory(game.path);
      if (await dir.exists()) {
        result[(game.title ?? '').toLowerCase()] = game;
      } else if (backupDir != null && await backupDir.exists()) {
        final backupGame = await _loadGameFromBackup(
          backupDir.path, game.title, game,
        );
        if (backupGame != null) {
          result[(game.title ?? '').toLowerCase()] = backupGame;
        }
      }
    }

    if (backupDir != null && await backupDir.exists()) {
      await for (final entity in backupDir.list()) {
        if (entity is Directory) {
          final folderName = path.basename(entity.path);
          final key = folderName.toLowerCase();
          if (!result.containsKey(key)) {
            final backupGame = await _loadGameFromBackup(
              backupDir.path, folderName, null,
            );
            if (backupGame != null) {
              result[key] = backupGame;
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

Future<Game?> _loadGameFromBackup(
  String backupBasePath, String? gameTitle, Game? existingDbGame,
) async {
  if (gameTitle == null || gameTitle.isEmpty) return null;

  final sep = Platform.pathSeparator;
  final sanitizedTitle = gameTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final backupGameDir = Directory('$backupBasePath$sep$sanitizedTitle');

  if (!await backupGameDir.exists()) return null;

  final metadataFile = File('${backupGameDir.path}${sep}metadata.json');
  Map<String, dynamic>? metadata;
  if (await metadataFile.exists()) {
    try {
      final content = await metadataFile.readAsString();
      metadata = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {}
  }

  final sourceUrlFile = File('${backupGameDir.path}${sep}source_url.txt');
  String? sourceUrl;
  if (await sourceUrlFile.exists()) {
    sourceUrl = (await sourceUrlFile.readAsString()).trim();
  }

  final imageDir = Directory('${backupGameDir.path}${sep}images');
  final List<String> imagePaths = [];
  if (await imageDir.exists()) {
    await for (final entity in imageDir.list()) {
      if (entity is File) {
        final ext = path.extension(entity.path).toLowerCase();
        if (['.jpg', '.jpeg', '.png', '.webp'].contains(ext)) {
          imagePaths.add(entity.path);
        }
      }
    }
    imagePaths.sort();
  }

  return Game(
    id: existingDbGame?.id,
    path: backupGameDir.path,
    title: metadata?['title'] as String? ?? gameTitle,
    version: metadata?['version'] as String?,
    intro: metadata?['intro'] as String?,
    features: metadata?['features'] as String?,
    changelog: metadata?['changelog'] as String?,
    downloadUrl: metadata?['download_url'] as String?,
    sourceUrl: sourceUrl ?? metadata?['source_url'] as String?,
    playCount: existingDbGame?.playCount ?? 0,
    lastPlayedTime: existingDbGame?.lastPlayedTime,
    addedTime: existingDbGame?.addedTime,
    isFavorite: existingDbGame?.isFavorite ?? false,
    isPlayed: true,
    tags: existingDbGame?.tags ?? [],
    images: imagePaths.asMap().entries.map((e) => GameImage(
      gameId: existingDbGame?.id ?? 0,
      imagePath: e.value,
      sortOrder: e.key,
    )).toList(),
    coverIndex: existingDbGame?.coverIndex ?? 0,
  );
}

final playedGamesProvider = FutureProvider<List<Game>>((ref) async {
  try {
    final repository = ref.watch(gameRepositoryProvider);
    final games = await repository.getPlayedGames();
    return games.where((g) => !g.path.contains('${Platform.pathSeparator}Cleared${Platform.pathSeparator}')).toList();
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
    return games.where((g) => !g.path.contains('${Platform.pathSeparator}Cleared${Platform.pathSeparator}')).toList();
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

final gamesByTagProvider = FutureProvider.family<List<Game>, int>((ref, tagId) async {
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

final searchGamesProvider = FutureProvider.family<List<Game>, String>((ref, query) async {
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

final selectedNavIndexProvider = StateProvider<int>((ref) => 1); // Default to games page

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
