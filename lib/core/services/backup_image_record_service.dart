import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PreservedGameImages {
  final int gameId;
  final String gamePath;
  final String title;
  final String sourceUrl;
  final List<String> imagePaths;
  final String? coverPath;

  const PreservedGameImages({
    required this.gameId,
    required this.gamePath,
    required this.title,
    required this.sourceUrl,
    required this.imagePaths,
    required this.coverPath,
  });
}

class BackupImageRecordService {
  Future<List<PreservedGameImages>> capture(Database db) async {
    final games = await db.query(
      'games',
      columns: ['id', 'path', 'title', 'source_url', 'cover_index'],
    );
    final images = await db.query(
      'game_images',
      orderBy: 'game_id, sort_order, id',
    );
    final imagesByGame = <int, List<String>>{};
    for (final image in images) {
      final gameId = image['game_id'] as int;
      final imagePath = image['image_path'] as String? ?? '';
      if (imagePath.isEmpty) continue;
      imagesByGame.putIfAbsent(gameId, () => []).add(imagePath);
    }

    final result = <PreservedGameImages>[];
    for (final game in games) {
      final gameId = game['id'] as int;
      final allImagePaths = imagesByGame[gameId] ?? const <String>[];
      final imagePaths = <String>[];
      for (final imagePath in allImagePaths) {
        if (await File(imagePath).exists()) {
          imagePaths.add(imagePath);
        }
      }
      if (imagePaths.isEmpty) continue;
      final coverIndex = game['cover_index'] as int? ?? 0;
      final originalCoverPath =
          coverIndex >= 0 && coverIndex < allImagePaths.length
              ? allImagePaths[coverIndex]
              : null;
      result.add(
        PreservedGameImages(
          gameId: gameId,
          gamePath: game['path'] as String? ?? '',
          title: game['title'] as String? ?? '',
          sourceUrl: game['source_url'] as String? ?? '',
          imagePaths: List.unmodifiable(imagePaths),
          coverPath: originalCoverPath != null &&
                  await File(originalCoverPath).exists()
              ? originalCoverPath
              : imagePaths.first,
        ),
      );
    }
    return result;
  }

  Future<int> merge(
    Database db,
    List<PreservedGameImages> preservedGames,
  ) async {
    if (preservedGames.isEmpty) return 0;

    final importedGames = await db.query(
      'games',
      columns: ['id', 'path', 'title', 'source_url', 'cover_index'],
    );
    final gamesByPath = <String, Map<String, Object?>>{};
    final gamesById = <int, Map<String, Object?>>{};
    final gamesByTitle = <String, List<Map<String, Object?>>>{};
    final gamesBySourceUrl = <String, List<Map<String, Object?>>>{};
    for (final game in importedGames) {
      final gameId = game['id'] as int;
      gamesById[gameId] = game;
      gamesByPath[_pathKey(game['path'] as String? ?? '')] = game;
      final titleKey = _textKey(game['title'] as String? ?? '');
      if (titleKey.isNotEmpty) {
        gamesByTitle.putIfAbsent(titleKey, () => []).add(game);
      }
      final sourceUrlKey = _sourceUrlKey(game['source_url'] as String? ?? '');
      if (sourceUrlKey != null) {
        gamesBySourceUrl.putIfAbsent(sourceUrlKey, () => []).add(game);
      }
    }
    final preservedTitleCounts = <String, int>{};
    final preservedSourceUrlCounts = <String, int>{};
    for (final preserved in preservedGames) {
      final titleKey = _textKey(preserved.title);
      if (titleKey.isNotEmpty) {
        preservedTitleCounts[titleKey] =
            (preservedTitleCounts[titleKey] ?? 0) + 1;
      }
      final sourceUrlKey = _sourceUrlKey(preserved.sourceUrl);
      if (sourceUrlKey != null) {
        preservedSourceUrlCounts[sourceUrlKey] =
            (preservedSourceUrlCounts[sourceUrlKey] ?? 0) + 1;
      }
    }

    var mergedGameCount = 0;
    for (final preserved in preservedGames) {
      final imported = _findImportedGame(
        preserved,
        gamesByPath,
        gamesById,
        gamesByTitle,
        gamesBySourceUrl,
        preservedTitleCounts,
        preservedSourceUrlCounts,
      );
      if (imported == null) continue;

      final importedGameId = imported['id'] as int;
      final importedImages = await db.query(
        'game_images',
        where: 'game_id = ?',
        whereArgs: [importedGameId],
        orderBy: 'sort_order, id',
      );
      final importedCoverIndex = imported['cover_index'] as int? ?? 0;
      final importedCoverPath =
          importedCoverIndex >= 0 && importedCoverIndex < importedImages.length
              ? importedImages[importedCoverIndex]['image_path'] as String?
              : null;
      final preservedByName = <String, String>{};
      final preservedByStem = <String, String>{};
      for (final imagePath in preserved.imagePaths) {
        preservedByName.putIfAbsent(_basenameKey(imagePath), () => imagePath);
        preservedByStem.putIfAbsent(_stemKey(imagePath), () => imagePath);
      }

      final mergedPaths = <String>[];
      final mergedKeys = <String>{};
      final aliases = <String, String>{};
      for (final image in importedImages) {
        final importedPath = image['image_path'] as String? ?? '';
        if (importedPath.isEmpty) continue;
        String? resolvedPath;
        if (await File(importedPath).exists()) {
          resolvedPath = importedPath;
        } else {
          resolvedPath = preservedByName[_basenameKey(importedPath)] ??
              preservedByStem[_stemKey(importedPath)];
          if (resolvedPath != null) {
            aliases[importedPath] = resolvedPath;
          }
        }
        if (resolvedPath != null && mergedKeys.add(_pathKey(resolvedPath))) {
          mergedPaths.add(resolvedPath);
        }
      }
      for (final imagePath in preserved.imagePaths) {
        if (mergedKeys.add(_pathKey(imagePath))) {
          mergedPaths.add(imagePath);
        }
      }
      if (mergedPaths.isEmpty) continue;

      final resolvedImportedCover = importedCoverPath == null
          ? null
          : aliases[importedCoverPath] ?? importedCoverPath;
      final preferredCover = preserved.coverPath ?? resolvedImportedCover;
      var coverIndex = preferredCover == null
          ? -1
          : mergedPaths.indexWhere(
              (imagePath) => _pathKey(imagePath) == _pathKey(preferredCover),
            );
      if (coverIndex < 0 && resolvedImportedCover != null) {
        coverIndex = mergedPaths.indexWhere(
          (imagePath) => _pathKey(imagePath) == _pathKey(resolvedImportedCover),
        );
      }
      if (coverIndex < 0) coverIndex = 0;

      await db.transaction((txn) async {
        await txn.delete(
          'game_images',
          where: 'game_id = ?',
          whereArgs: [importedGameId],
        );
        for (var index = 0; index < mergedPaths.length; index++) {
          await txn.insert('game_images', {
            'game_id': importedGameId,
            'image_path': mergedPaths[index],
            'sort_order': index,
          });
        }
        await txn.update(
          'games',
          {'cover_index': coverIndex},
          where: 'id = ?',
          whereArgs: [importedGameId],
        );
        for (final alias in aliases.entries) {
          for (final column in ['intro', 'features', 'changelog', 'guide']) {
            await txn.rawUpdate(
              'UPDATE games SET $column = REPLACE($column, ?, ?) '
              'WHERE id = ? AND instr($column, ?) > 0',
              [alias.key, alias.value, importedGameId, alias.key],
            );
          }
        }
      });
      mergedGameCount++;
    }
    return mergedGameCount;
  }

  Map<String, Object?>? _findImportedGame(
    PreservedGameImages preserved,
    Map<String, Map<String, Object?>> gamesByPath,
    Map<int, Map<String, Object?>> gamesById,
    Map<String, List<Map<String, Object?>>> gamesByTitle,
    Map<String, List<Map<String, Object?>>> gamesBySourceUrl,
    Map<String, int> preservedTitleCounts,
    Map<String, int> preservedSourceUrlCounts,
  ) {
    final pathMatch = gamesByPath[_pathKey(preserved.gamePath)];
    if (pathMatch != null) return pathMatch;

    final idMatch = gamesById[preserved.gameId];
    if (idMatch != null) {
      final importedTitle = idMatch['title'] as String? ?? '';
      final importedPath = idMatch['path'] as String? ?? '';
      if (_textKey(importedTitle) == _textKey(preserved.title) ||
          _basenameKey(importedPath) == _basenameKey(preserved.gamePath)) {
        return idMatch;
      }
    }

    final sourceUrlKey = _sourceUrlKey(preserved.sourceUrl);
    final sourceUrlMatches =
        sourceUrlKey == null ? null : gamesBySourceUrl[sourceUrlKey];
    if (sourceUrlKey != null &&
        preservedSourceUrlCounts[sourceUrlKey] == 1 &&
        sourceUrlMatches?.length == 1) {
      return sourceUrlMatches!.single;
    }

    final titleKey = _textKey(preserved.title);
    final titleMatches = gamesByTitle[titleKey];
    return preservedTitleCounts[titleKey] == 1 && titleMatches?.length == 1
        ? titleMatches!.single
        : null;
  }

  String _pathKey(String value) => path.normalize(value).toLowerCase();

  String _textKey(String value) => value.trim().toLowerCase();

  String? _sourceUrlKey(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  String _basenameKey(String value) => path.basename(value).toLowerCase();

  String _stemKey(String value) {
    final fileName = _basenameKey(value);
    final extension = path.extension(fileName);
    return extension.isEmpty
        ? fileName
        : fileName.substring(0, fileName.length - extension.length);
  }
}
