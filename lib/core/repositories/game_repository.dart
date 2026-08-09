import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import 'play_time_repository.dart';
import '../utils/app_settings.dart';
import '../utils/backup_image_reference_resolver.dart';
import '../utils/cleared_game_path_utils.dart';
import '../utils/game_data_paths.dart';

class GameRepository implements PlayTimeRepository {
  Future<Database> get _db => DatabaseHelper.database;

  final Map<String, bool> _pathExistsCache = {};
  DateTime? _pathCacheTime;

  Future<bool> _pathExists(String path) async {
    if (_pathCacheTime != null &&
        DateTime.now().difference(_pathCacheTime!) <
            const Duration(seconds: 30)) {
      return _pathExistsCache[path] ?? false;
    }
    _pathExistsCache.clear();
    _pathCacheTime = DateTime.now();
    final exists = await Directory(path).exists();
    _pathExistsCache[path] = exists;
    return exists;
  }

  Future<List<Game>> _fillGameRelations(List<Game> games) async {
    if (games.isEmpty) return games;

    final db = await _db;
    final gameIds = games.where((g) => g.id != null).map((g) => g.id!).toList();
    if (gameIds.isEmpty) return games;

    final placeholders = List.filled(gameIds.length, '?').join(', ');

    final tagMaps = await db.rawQuery('''
      SELECT t.*, gtr.game_id FROM tags t
      INNER JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE gtr.game_id IN ($placeholders)
    ''', gameIds);

    final imageMaps = await db.rawQuery('''
      SELECT * FROM game_images
      WHERE game_id IN ($placeholders)
      ORDER BY sort_order ASC
    ''', gameIds);

    final tagsByGameId = <int, List<Tag>>{};
    for (final map in tagMaps) {
      final gameId = map['game_id'] as int;
      tagsByGameId.putIfAbsent(gameId, () => []);
      tagsByGameId[gameId]!.add(Tag.fromMap(map));
    }

    final imagesByGameId = <int, List<GameImage>>{};
    for (final map in imageMaps) {
      final gameId = map['game_id'] as int;
      imagesByGameId.putIfAbsent(gameId, () => []);
      imagesByGameId[gameId]!.add(GameImage.fromMap(map));
    }

    return Future.wait(games.map((game) async {
      var images = imagesByGameId[game.id!] ?? [];
      var resolvedGame = game;
      final gamePathExists = await _pathExists(game.path);

      // 通关游戏目录缺失时，尝试从对应 Backup 目录加载。
      if (!gamePathExists && game.isCleared) {
        // 尝试在 Backup 目录中模糊匹配
        final backupPath = await _findBackupPath(game.path, game.title);
        if (backupPath != null) {
          images = await _loadImagesFromBackupDir(backupPath);
          resolvedGame = game.copyWith(path: backupPath);
        }
      }
      // 对于路径中直接包含 Backup 的游戏
      else if (ClearedGamePathUtils.hasBackupSegment(game.path)) {
        // 检查数据库中的图片是否存在
        bool hasValidImages = false;
        if (images.isNotEmpty) {
          for (final img in images) {
            if (await File(img.imagePath).exists()) {
              hasValidImages = true;
              break;
            }
          }
        }
        // 如果没有有效图片，从备份目录加载
        if (!hasValidImages) {
          images = await _loadImagesFromBackupDir(game.path);
        }
      }

      resolvedGame = resolvedGame.copyWith(
        tags: tagsByGameId[game.id!] ?? [],
        images: images,
      );
      return BackupImageReferenceResolver.rewriteGameReferences(resolvedGame);
    }));
  }

  Future<String?> _findBackupPath(String gamePath, String? gameTitle) async {
    if (gameTitle == null || gameTitle.isEmpty) return null;

    final sep = path.separator;

    // 旧格式：查找 Cleared 目录的位置
    final clearedIndex = gamePath.indexOf('${sep}Cleared$sep');
    if (clearedIndex != -1) {
      // 构建 Backup 目录路径
      final basePath = gamePath.substring(0, clearedIndex);
      final backupDir = Directory('$basePath${sep}Cleared${sep}Backup');

      if (await backupDir.exists()) {
        final result = await _searchBackupDir(backupDir.path, gameTitle);
        if (result != null) return result;
      }
    }

    // 新格式：检查 cleared_paths 配置
    final prefs = await AppSettings.load();
    final rawCleared = prefs.getString('cleared_paths') ?? '';
    if (rawCleared.startsWith('{')) {
      try {
        final decoded = jsonDecode(rawCleared) as Map<String, dynamic>;
        for (final v in decoded.values) {
          final cp = v?.toString() ?? '';
          if (cp.isEmpty) continue;
          if (ClearedGamePathUtils.isSameOrChildPath(gamePath, cp)) {
            final backupDir = Directory('$cp${sep}Backup');
            if (await backupDir.exists()) {
              final result = await _searchBackupDir(backupDir.path, gameTitle);
              if (result != null) return result;
            }
          }
        }
      } catch (_) {}
    }

    return null;
  }

  Future<String?> _searchBackupDir(
      String backupBasePath, String gameTitle) async {
    final backupDir = Directory(backupBasePath);

    // 清理游戏title中的特殊字符
    final sanitizedTitle = gameTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final titleLower = sanitizedTitle.toLowerCase();

    // 遍历 Backup 目录中的所有文件夹
    String? bestMatch;
    int bestScore = 0;

    await for (final entity in backupDir.list()) {
      if (entity is Directory) {
        final folderName = path.basename(entity.path);
        final folderLower = folderName.toLowerCase();

        // 精确匹配
        if (folderLower == titleLower) {
          return entity.path;
        }

        // 计算匹配分数
        int score = 0;
        // 检查文件夹名是否包含title
        if (folderLower.contains(titleLower)) {
          score = 100;
        }
        // 检查title是否包含文件夹名
        else if (titleLower.contains(folderLower)) {
          score = 80;
        }
        // 检查是否有共同的子串
        else {
          final commonLength = _commonSubstringLength(folderLower, titleLower);
          if (commonLength > 3) {
            score = commonLength;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = entity.path;
        }
      }
    }

    return bestMatch;
  }

  int _commonSubstringLength(String s1, String s2) {
    int maxLen = 0;
    for (int i = 0; i < s1.length; i++) {
      for (int j = 0; j < s2.length; j++) {
        int len = 0;
        while (i + len < s1.length &&
            j + len < s2.length &&
            s1[i + len] == s2[j + len]) {
          len++;
        }
        if (len > maxLen) {
          maxLen = len;
        }
      }
    }
    return maxLen;
  }

  Future<List<GameImage>> _loadImagesFromBackupDir(String gamePath) async {
    final imageDir = await GameDataPaths.existingImagesDir(gamePath);
    final List<GameImage> images = [];
    if (await imageDir.exists()) {
      final List<String> imagePaths = [];
      await for (final entity in imageDir.list()) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
            imagePaths.add(entity.path);
          }
        }
      }
      imagePaths.sort();
      for (int i = 0; i < imagePaths.length; i++) {
        images
            .add(GameImage(gameId: 0, imagePath: imagePaths[i], sortOrder: i));
      }
    }
    return images;
  }

  Future<Game> _applyBackupImageFallback(Game game) async {
    var images = game.images;
    var resolvedGame = game;
    final gamePathExists = await _pathExists(game.path);

    if (!gamePathExists && game.isCleared) {
      final backupPath = await _findBackupPath(game.path, game.title);
      if (backupPath != null) {
        images = await _loadImagesFromBackupDir(backupPath);
        resolvedGame = game.copyWith(path: backupPath);
      }
    } else if (ClearedGamePathUtils.hasBackupSegment(game.path)) {
      var hasValidImages = false;
      for (final img in images) {
        if (await File(img.imagePath).exists()) {
          hasValidImages = true;
          break;
        }
      }
      if (!hasValidImages) {
        images = await _loadImagesFromBackupDir(game.path);
      }
    }

    resolvedGame = resolvedGame.copyWith(images: images);
    return BackupImageReferenceResolver.rewriteGameReferences(resolvedGame);
  }

  Future<List<Game>> getAllGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getUnplayedGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_played = 0',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getUnplayedUnclearedGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_played = 0 AND play_count < 1 AND is_cleared = 0',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getNonClearedGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_cleared = 0',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getClearedGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_cleared = 1',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getPlayedGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_played = 1 OR play_count > 0',
      orderBy: 'last_played_time DESC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getFavoriteGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_favorite = 1',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> getGamesByTag(int tagId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT g.* FROM games g
      INNER JOIN game_tag_relation gtr ON g.id = gtr.game_id
      WHERE gtr.tag_id = ?
      ORDER BY g.title ASC
    ''', [tagId]);
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<List<Game>> searchGames(String query) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'title LIKE ? OR intro LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<Game?> getGameById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    final game = Game.fromMap(maps.first);
    final tags = await getGameTags(game.id!);
    final images = await getGameImages(game.id!);
    return _applyBackupImageFallback(game.copyWith(tags: tags, images: images));
  }

  Future<Game?> getGameByPath(String path) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'path = ?',
      whereArgs: [path],
    );
    if (maps.isEmpty) return null;
    final game = Game.fromMap(maps.first);
    final tags = await getGameTags(game.id!);
    final images = await getGameImages(game.id!);
    return _applyBackupImageFallback(game.copyWith(tags: tags, images: images));
  }

  Future<String?> getStoredGamePath(int id) async {
    final db = await _db;
    final maps = await db.query(
      'games',
      columns: ['path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['path'] as String?;
  }

  Future<Game?> getStoredGameByPath(String path) async {
    final db = await _db;
    final maps = await db.query(
      'games',
      where: 'path = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final game = Game.fromMap(maps.first);
    final tags = await getGameTags(game.id!);
    final images = await getGameImages(game.id!);
    return game.copyWith(tags: tags, images: images);
  }

  Future<int> insertGame(Game game) async {
    final db = await _db;
    final gameToInsert = game.addedTime == null
        ? game.copyWith(addedTime: DateTime.now())
        : game;
    return await db.insert(
      'games',
      gameToInsert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateGame(Game game) async {
    final db = await _db;
    await db.update(
      'games',
      game.toMap(),
      where: 'id = ?',
      whereArgs: [game.id],
    );
  }

  Future<void> updateGameLauncher(int id, String? launcher, bool locked) async {
    final db = await _db;
    await db.update(
      'games',
      {
        'game_launcher': launcher,
        'launcher_locked': locked ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateLocaleEmulator(int id, bool useLocaleEmulator) async {
    final db = await _db;
    await db.update(
      'games',
      {'use_locale_emulator': useLocaleEmulator ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateGamePath(int id, String newPath) async {
    final db = await _db;
    await db.update(
      'games',
      {'path': newPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateClearedStatus(int id, bool isCleared) async {
    final db = await _db;
    await db.update(
      'games',
      {'is_cleared': isCleared ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> migrateLegacyClearedStates(List<String> clearedRoots) async {
    final db = await _db;
    final rows = await db.query(
      'games',
      columns: ['id', 'path', 'is_cleared'],
      where: 'is_cleared = 0',
    );
    final normalizedRoots =
        clearedRoots.where((root) => root.isNotEmpty).toList();
    final batch = db.batch();
    var hasUpdates = false;
    for (final row in rows) {
      final gamePath = row['path'] as String? ?? '';
      final normalized =
          path.normalize(gamePath).replaceAll('\\', '/').toLowerCase();
      final segments = normalized.split('/').where((part) => part.isNotEmpty);
      final legacyPath =
          segments.contains('cleared') || segments.contains('backup');
      final configuredPath = normalizedRoots.any(
        (root) => ClearedGamePathUtils.isSameOrChildPath(gamePath, root),
      );
      if (legacyPath || configuredPath) {
        batch.update('games', {'is_cleared': 1},
            where: 'id = ?', whereArgs: [row['id']]);
        hasUpdates = true;
      }
    }
    if (hasUpdates) await batch.commit(noResult: true);
  }

  Future<String?> findBackupPathForGame(Game game) =>
      _findBackupPath(game.path, game.title);

  Future<void> mergeDuplicateGamePath({
    required int keepGameId,
    required int duplicateGameId,
    required String targetPath,
  }) async {
    if (keepGameId == duplicateGameId) {
      await updateGamePath(keepGameId, targetPath);
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      final stateRows = await txn.query(
        'games',
        columns: ['id', 'is_cleared'],
        where: 'id IN (?, ?)',
        whereArgs: [keepGameId, duplicateGameId],
      );
      final isCleared = stateRows.any((row) => row['is_cleared'] == 1);

      await txn.rawInsert('''
        INSERT OR IGNORE INTO game_tag_relation (game_id, tag_id)
        SELECT ?, tag_id FROM game_tag_relation WHERE game_id = ?
      ''', [keepGameId, duplicateGameId]);

      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM game_images WHERE game_id = ?',
        [keepGameId],
      );
      final imageOffset =
          countRows.isEmpty ? 0 : (countRows.first['count'] as int? ?? 0);
      final duplicateImages = await txn.query(
        'game_images',
        where: 'game_id = ?',
        whereArgs: [duplicateGameId],
        orderBy: 'sort_order ASC',
      );
      for (var i = 0; i < duplicateImages.length; i++) {
        await txn.insert('game_images', {
          'game_id': keepGameId,
          'image_path': duplicateImages[i]['image_path'],
          'sort_order': imageOffset + i,
        });
      }

      await txn.delete(
        'game_images',
        where: 'game_id = ?',
        whereArgs: [duplicateGameId],
      );
      await txn.delete(
        'game_tag_relation',
        where: 'game_id = ?',
        whereArgs: [duplicateGameId],
      );
      await txn.delete('games', where: 'id = ?', whereArgs: [duplicateGameId]);
      await txn.update(
        'games',
        {'path': targetPath, 'is_cleared': isCleared ? 1 : 0},
        where: 'id = ?',
        whereArgs: [keepGameId],
      );
    });
  }

  Future<void> deleteGame(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('game_images', where: 'game_id = ?', whereArgs: [id]);
      await txn
          .delete('game_tag_relation', where: 'game_id = ?', whereArgs: [id]);
      await txn.delete('games', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteGameByPath(String path) async {
    final db = await _db;
    await db.transaction((txn) async {
      final maps = await txn.query('games',
          columns: ['id'], where: 'path = ?', whereArgs: [path]);
      if (maps.isNotEmpty) {
        final id = maps.first['id'] as int;
        await txn.delete('game_images', where: 'game_id = ?', whereArgs: [id]);
        await txn
            .delete('game_tag_relation', where: 'game_id = ?', whereArgs: [id]);
      }
      await txn.delete('games', where: 'path = ?', whereArgs: [path]);
    });
  }

  Future<void> incrementPlayCount(int id) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE games
      SET play_count = play_count + 1,
          last_played_time = ?,
          is_played = 1
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  @override
  Future<void> recordPlayStarted(int gameId, DateTime startedAt) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE games
      SET play_count = play_count + 1,
          last_played_time = ?,
          is_played = 1
      WHERE id = ?
    ''', [startedAt.toIso8601String(), gameId]);
  }

  @override
  Future<void> addPlayDurationDelta(int gameId, int seconds) async {
    if (seconds <= 0) return;
    final db = await _db;
    await db.rawUpdate('''
      UPDATE games
      SET play_duration = COALESCE(play_duration, 0) + ?
      WHERE id = ?
    ''', [seconds, gameId]);
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final db = await _db;
    await db.update(
      'games',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAsPlayed(int id) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE games
      SET is_played = 1,
          play_count = play_count + 1,
          last_played_time = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  Future<void> markAsUnplayed(int id) async {
    await resetPlayStatus(id);
  }

  Future<void> decrementPlayCount(int id) async {
    final db = await _db;
    final maps = await db.query('games',
        columns: ['play_count'], where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return;
    final currentCount = (maps.first['play_count'] as int?) ?? 0;
    if (currentCount <= 1) {
      await resetPlayStatus(id);
    } else {
      await db.rawUpdate('''
        UPDATE games
        SET play_count = play_count - 1,
            last_played_time = ?
        WHERE id = ?
      ''', [DateTime.now().toIso8601String(), id]);
    }
  }

  Future<void> updateFavoriteStatus(int id, bool isFavorite) async {
    await toggleFavorite(id, isFavorite);
  }

  Future<void> resetPlayStatus(int id) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE games
      SET play_count = 0,
          last_played_time = NULL,
          is_played = 0
      WHERE id = ?
    ''', [id]);
  }

  Future<List<Tag>> getGameTags(int gameId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE gtr.game_id = ?
    ''', [gameId]);
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<GameImage>> getGameImages(int gameId) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'game_images',
      where: 'game_id = ?',
      whereArgs: [gameId],
      orderBy: 'sort_order ASC',
    );
    return maps.map((map) => GameImage.fromMap(map)).toList();
  }

  Future<void> addTagToGame(int gameId, int tagId) async {
    final db = await _db;
    await db.insert(
      'game_tag_relation',
      {'game_id': gameId, 'tag_id': tagId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTagFromGame(int gameId, int tagId) async {
    final db = await _db;
    await db.delete(
      'game_tag_relation',
      where: 'game_id = ? AND tag_id = ?',
      whereArgs: [gameId, tagId],
    );
  }

  Future<void> clearGameTags(int gameId) async {
    final db = await _db;
    await db.delete(
      'game_tag_relation',
      where: 'game_id = ?',
      whereArgs: [gameId],
    );
  }

  Future<void> setGameImages(int gameId, List<GameImage> images) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn
          .delete('game_images', where: 'game_id = ?', whereArgs: [gameId]);
      for (int i = 0; i < images.length; i++) {
        await txn.insert('game_images', {
          'game_id': gameId,
          'image_path': images[i].imagePath,
          'sort_order': i,
        });
      }
    });
  }

  Future<void> addGameImage(int gameId, String imagePath, int sortOrder) async {
    final db = await _db;
    await db.insert('game_images', {
      'game_id': gameId,
      'image_path': imagePath,
      'sort_order': sortOrder,
    });
  }

  Future<void> deleteGameImage(int imageId) async {
    final db = await _db;
    await db.delete('game_images', where: 'id = ?', whereArgs: [imageId]);
  }

  Future<void> deleteGameImagesByGameId(int gameId) async {
    final db = await _db;
    await db.delete('game_images', where: 'game_id = ?', whereArgs: [gameId]);
  }

  Future<void> updateImageOrder(int imageId, int newOrder) async {
    final db = await _db;
    await db.update(
      'game_images',
      {'sort_order': newOrder},
      where: 'id = ?',
      whereArgs: [imageId],
    );
  }

  Future<void> updateGameImagesOrder(int gameId, List<int> imageIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      for (int i = 0; i < imageIds.length; i++) {
        await txn.update(
          'game_images',
          {'sort_order': i},
          where: 'id = ? AND game_id = ?',
          whereArgs: [imageIds[i], gameId],
        );
      }
    });
  }

  Future<void> updateCoverIndex(int gameId, int coverIndex) async {
    final db = await _db;
    await db.update(
      'games',
      {'cover_index': coverIndex},
      where: 'id = ?',
      whereArgs: [gameId],
    );
  }

  Future<void> updateRatingReview(int id, double rating, String? review) async {
    final db = await _db;
    await db.update(
      'games',
      {
        'rating': rating,
        'review': review,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteRatingReview(int id) async {
    final db = await _db;
    await db.update(
      'games',
      {
        'rating': 0.0,
        'review': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getGameCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM games');
    return result.first['count'] as int;
  }

  Future<int> getPlayedCount() async {
    final db = await _db;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM games WHERE is_played = 1 OR play_count > 0');
    return result.first['count'] as int;
  }

  Future<List<Game>> getGamesPaginated({
    int offset = 0,
    int limit = 50,
    String orderBy = 'title ASC',
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }

  Future<void> updateSavePath(int gameId, String? savePath) async {
    final db = await _db;
    await db.update(
      'games',
      {'save_path': savePath},
      where: 'id = ?',
      whereArgs: [gameId],
    );
  }

  Future<void> updateGuide(int gameId, String? guide) async {
    final db = await _db;
    await db.update(
      'games',
      {'guide': guide},
      where: 'id = ?',
      whereArgs: [gameId],
    );
  }

  Future<void> updateScrollPosition(int gameId,
      {double? introPosition, double? guidePosition}) async {
    final db = await _db;
    final updates = <String, dynamic>{};
    if (introPosition != null) updates['intro_scroll_position'] = introPosition;
    if (guidePosition != null) updates['guide_scroll_position'] = guidePosition;
    if (updates.isNotEmpty) {
      await db.update('games', updates, where: 'id = ?', whereArgs: [gameId]);
    }
  }

  /// Update all image paths that start with [oldPrefix] to start with [newPrefix].
  /// Used when a game folder is moved or renamed.
  Future<void> updateImagePaths(
      int gameId, String oldPrefix, String newPrefix) async {
    final db = await _db;
    await db.transaction((txn) async {
      final images = await txn.query(
        'game_images',
        where: 'game_id = ? AND image_path LIKE ?',
        whereArgs: [gameId, '$oldPrefix%'],
      );
      for (final img in images) {
        final oldImgPath = img['image_path'] as String;
        final newImgPath =
            '$newPrefix${oldImgPath.substring(oldPrefix.length)}';
        await txn.update(
          'game_images',
          {'image_path': newImgPath},
          where: 'id = ?',
          whereArgs: [img['id']],
        );
      }
    });
  }

  Future<List<Game>> getPlayedAndClearedGames() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_played = 1 OR play_count > 0',
      orderBy: 'title ASC',
    );
    final games = maps.map((map) => Game.fromMap(map)).toList();
    return _fillGameRelations(games);
  }
}
