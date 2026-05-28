import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final allGames = await repository.getAllGames();
    // 过滤出Cleared目录下的游戏
    return allGames.where((g) => g.path.contains('${Platform.pathSeparator}Cleared${Platform.pathSeparator}') && !g.path.contains('${Platform.pathSeparator}Backup${Platform.pathSeparator}')).toList();
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('ERROR Loading Cleared Games: $e\n$stackTrace');
    }
    rethrow;
  }
});

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
