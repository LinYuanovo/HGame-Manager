import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// 锁定的 sqflite_common 2.5.8 在 COMMIT 失败时关闭 Dart 事务但保留 SQLite 事务。
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:sqflite_common/src/transaction.dart' show SqfliteTransactionMixin;
import '../database/database_helper.dart';
import '../models/models.dart';
import 'play_time_repository.dart';
import '../utils/app_settings.dart';
import '../utils/backup_image_reference_resolver.dart';
import '../utils/cleared_game_path_utils.dart';
import '../utils/game_data_paths.dart';
import '../utils/path_reference_rewriter.dart';
import '../utils/game_path_utils.dart';

class GameAlreadyExistsException implements Exception {
  final String gamePath;

  const GameAlreadyExistsException(this.gamePath);

  @override
  String toString() => '该游戏已在库中，已跳过';
}

class GameRepository implements PlayTimeRepository {
  final Database? _database;

  GameRepository({Database? database}) : _database = database;

  Future<Database> get _db async => _database ?? await DatabaseHelper.database;

  Future<T> _transactionWithCommitRollback<T>(
      Database db, Future<T> Function(Transaction txn) action) async {
    Transaction? transaction;
    var actionComplete = false;
    try {
      return await db.transaction((txn) async {
        transaction = txn;
        final result = await action(txn);
        actionComplete = true;
        return result;
      });
    } catch (error, stackTrace) {
      final txn = transaction;
      if (actionComplete && txn is SqfliteTransactionMixin) {
        // 必须沿用事务 ID；无事务的 ROLLBACK 会在 FFI 队列中等待自己结束。
        txn.closed = false;
        try {
          await transaction!.execute('ROLLBACK');
        } catch (rollbackError) {
          throw StateError('事务提交失败且无法回滚：$error；$rollbackError');
        } finally {
          txn.closed = true;
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  final Map<String, bool> _pathExistsCache = {};
  DateTime? _pathCacheTime;

  Future<bool> _pathExists(String path) async {
    if (_pathCacheTime == null ||
        DateTime.now().difference(_pathCacheTime!) >=
            const Duration(seconds: 30)) {
      _pathExistsCache.clear();
      _pathCacheTime = DateTime.now();
    }
    final cached = _pathExistsCache[path];
    if (cached != null) return cached;
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

    return Future.wait(games.map((game) => _applyBackupImageFallback(
      game.copyWith(
        tags: tagsByGameId[game.id] ?? [],
        images: imagesByGameId[game.id] ?? [],
      ),
    )));
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
    if (game.isCleared && !await _pathExists(game.path)) {
      final backupPath = await findBackupPathForGame(game);
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
    final map = await _getGameMapByPath(path);
    if (map == null) return null;
    final game = Game.fromMap(map);
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
    final map = await _getGameMapByPath(path);
    if (map == null) return null;
    final game = Game.fromMap(map);
    final tags = await getGameTags(game.id!);
    final images = await getGameImages(game.id!);
    return game.copyWith(tags: tags, images: images);
  }

  Future<Map<String, int>> getGameIdsByPathKey(
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db;
    final maps = await db.query('games', columns: ['id', 'path']);
    return {
      for (final map in maps)
        GamePathUtils.comparisonKey(map['path'] as String): map['id'] as int,
    };
  }

  Future<Map<String, dynamic>?> _getGameMapByPath(String gamePath) async {
    final db = await _db;
    final maps = await db.query(
      'games',
      where: 'path = ?',
      whereArgs: [gamePath],
      limit: 1,
    );
    if (maps.isNotEmpty) return maps.first;
    final id =
        (await getGameIdsByPathKey())[GamePathUtils.comparisonKey(gamePath)];
    if (id == null) return null;
    final matches = await db.query('games', where: 'id = ?', whereArgs: [id]);
    return matches.isEmpty ? null : matches.first;
  }

  Future<int> insertGame(Game game) async {
    final db = await _db;
    final gameToInsert = game.addedTime == null
        ? game.copyWith(addedTime: DateTime.now())
        : game;
    return _transactionWithCommitRollback(db, (txn) async {
      final existingPaths = await getGameIdsByPathKey(executor: txn);
      if (existingPaths.containsKey(GamePathUtils.comparisonKey(game.path))) {
        throw GameAlreadyExistsException(game.path);
      }
      return txn.insert(
        'games',
        gameToInsert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  Future<T> transaction<T>(Future<T> Function(Transaction) action) async {
    final db = await _db;
    return _transactionWithCommitRollback(db, action);
  }

  Future<void> updateGame(Game game, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db;
    await db.update(
      'games',
      game.toMap(),
      where: 'id = ?',
      whereArgs: [game.id],
    );
  }

  static Map<String, Object?> _scrapedFields(Game game) => {
    'title': game.title,
    'version': game.version,
    'intro': game.intro,
    'features': game.features,
    'changelog': game.changelog,
    'download_url': game.downloadUrl,
    'source_url': game.sourceUrl,
    'maker': game.maker,
    'maker_url': game.makerUrl,
  };

  /// 网络处理期间游玩状态仍会更新，刮削仅写入自身负责的元数据字段。
  Future<void> updateScrapedFields(Game game, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db;
    final changed = await db.update('games', _scrapedFields(game),
        where: 'id = ? AND path = ?', whereArgs: [game.id, game.path]);
    if (changed != 1) throw StateError('游戏记录或路径已变化，请重新确认');
  }

  /// 编辑资料时原子替换标签；文件保存失败会撤销本次数据库修改。
  Future<void> updateGameWithTags(Game game,
      {Future<void> Function()? beforeCommit}) async {
    if (game.id == null) throw StateError('编辑标签需要已入库的游戏');
    final db = await _db;
    await _transactionWithCommitRollback(db, (txn) async {
      final changed = await txn.update('games', {
        ..._scrapedFields(game),
        'guide': game.guide,
        'game_launcher': game.gameLauncher,
        'launcher_locked': game.launcherLocked ? 1 : 0,
      }, where: 'id = ? AND path = ?', whereArgs: [game.id, game.path]);
      if (changed != 1) throw StateError('游戏记录或路径已变化，请刷新后重试');
      await txn.delete('game_tag_relation',
          where: 'game_id = ?', whereArgs: [game.id]);
      for (final tag in game.tags) {
        final matches = await txn.query('tags',
            columns: ['id'],
            where: 'type = ? AND name = ? COLLATE NOCASE',
            whereArgs: [tag.type, tag.name],
            limit: 1);
        final tagId = matches.isNotEmpty
            ? matches.first['id'] as int
            : await txn.insert('tags', {
                'name': tag.name,
                'type': tag.type,
                'display_name': tag.displayName ?? tag.name,
                'is_favorite': 0,
              });
        await txn.insert(
            'game_tag_relation', {'game_id': game.id, 'tag_id': tagId},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await beforeCommit?.call();
    });
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
    _pathExistsCache.clear();
  }

  /// 在同一事务中更新搬运涉及的记录，文件替换失败则撤销全部写入。
  Future<void> moveGameRecords({
    required int gameId,
    required String oldPath,
    required String newPath,
    Future<void> Function()? beforeCommit,
  }) async {
    final db = await _db;
    await _transactionWithCommitRollback(db, (txn) async {
      final rows = await txn.query('games',
          where: 'id = ?', whereArgs: [gameId], limit: 1);
      if (rows.isEmpty) throw StateError('游戏记录已不存在');
      final game = Game.fromMap(rows.single);
      if (GamePathUtils.comparisonKey(game.path) != GamePathUtils.comparisonKey(oldPath)) {
        throw StateError('游戏路径已变更，请刷新后重试');
      }

      final occupied = await getGameIdsByPathKey(executor: txn);
      final occupiedId = occupied[GamePathUtils.comparisonKey(newPath)];
      if (occupiedId != null && occupiedId != gameId) {
        throw StateError('目标路径已被其他游戏记录占用');
      }

      String? movedPath(String? value) =>
          PathReferenceRewriter.relocateLocalPath(value, oldPath, newPath);

      final replacements = {oldPath: newPath};
      await txn.update('games', {
        'path': newPath,
        'intro': PathReferenceRewriter.replace(game.intro, replacements),
        'features': PathReferenceRewriter.replace(game.features, replacements),
        'changelog': PathReferenceRewriter.replace(game.changelog, replacements),
        'guide': PathReferenceRewriter.replace(game.guide, replacements),
        'game_launcher': movedPath(game.gameLauncher),
        'save_path': movedPath(game.savePath),
        'cleared_backup_path': movedPath(game.clearedBackupPath),
      }, where: 'id = ?', whereArgs: [gameId]);
      final images = await txn.query('game_images',
          where: 'game_id = ?', whereArgs: [gameId]);
      for (final image in images) {
        final previous = image['image_path'] as String;
        final updated = movedPath(previous);
        if (updated != previous) {
          await txn.update('game_images', {'image_path': updated},
              where: 'id = ? AND game_id = ?',
              whereArgs: [image['id'], gameId]);
        }
      }
      await beforeCommit?.call();
    });
    _pathExistsCache.clear();
  }

  /// 撤销本次刮削对该游戏的写入，保留全局标签及其他游戏的修改。
  Future<void> restoreScrapeSnapshot({
    required String gamePath,
    required Game? original,
    bool metadataOnly = false,
  }) async {
    final db = await _db;
    await _transactionWithCommitRollback(db, (txn) async {
      if (original == null) {
        final rows = await txn.query('games',
            columns: ['id'], where: 'path = ?', whereArgs: [gamePath]);
        for (final row in rows) {
          final gameId = row['id'];
          await txn.delete('game_tag_relation',
              where: 'game_id = ?', whereArgs: [gameId]);
          await txn.delete('game_images',
              where: 'game_id = ?', whereArgs: [gameId]);
          await txn.delete('games', where: 'id = ?', whereArgs: [gameId]);
        }
        return;
      }
      if (original.id == null) throw StateError('恢复快照需要原游戏 ID');
      final changed = await txn.update('games', metadataOnly ? _scrapedFields(original) : {
        ...original.toMap(),
        'cleared_backup_path': original.clearedBackupPath,
        'review': original.review,
        'save_path': original.savePath,
        'maker': original.maker,
        'maker_url': original.makerUrl,
        'guide': original.guide,
      }, where: 'id = ?', whereArgs: [original.id]);
      if (changed != 1) throw StateError('原游戏记录已不存在，无法恢复刮削快照');
      await txn.delete('game_tag_relation',
          where: 'game_id = ?', whereArgs: [original.id]);
      for (final tag in original.tags) {
        if (tag.id == null) throw StateError('原标签缺少 ID，无法恢复刮削快照');
        await txn.insert('game_tag_relation', {
          'game_id': original.id,
          'tag_id': tag.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.delete('game_images',
          where: 'game_id = ?', whereArgs: [original.id]);
      for (final image in original.images) {
        await txn.insert('game_images', {
          if (image.id != null) 'id': image.id,
          'game_id': original.id,
          'image_path': image.imagePath,
          'sort_order': image.sortOrder,
        });
      }
    });
    _pathExistsCache.clear();
  }

  Future<void> updateClearedStatus(
    int id,
    bool isCleared, {
    String? clearedBackupPath,
  }) async {
    final db = await _db;
    await db.update(
      'games',
      {
        'is_cleared': isCleared ? 1 : 0,
        'cleared_backup_path': isCleared ? clearedBackupPath : null,
      },
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

  Future<String?> findBackupPathForGame(Game game) async {
    final storedPath = game.clearedBackupPath;
    if (storedPath != null && storedPath.isNotEmpty) {
      if (await Directory(storedPath).exists()) return storedPath;
    }
    return _findBackupPath(game.path, game.title);
  }

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

  Future<void> addTagToGame(int gameId, int tagId,
      {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db;
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

  Future<void> clearGameTags(int gameId, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _db;
    await db.delete(
      'game_tag_relation',
      where: 'game_id = ?',
      whereArgs: [gameId],
    );
  }

  Future<void> setGameImages(int gameId, List<GameImage> images, {int? coverIndex}) async {
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
      if (coverIndex != null) await txn.update('games', {'cover_index': images.isEmpty ? 0 : coverIndex.clamp(0, images.length - 1)}, where: 'id = ?', whereArgs: [gameId]);
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
