import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class GameRepository {
  Future<Database> get _db => DatabaseHelper.database;

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

    return games.map((game) {
      return game.copyWith(
        tags: tagsByGameId[game.id!] ?? [],
        images: imagesByGameId[game.id!] ?? [],
      );
    }).toList();
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
    final sep = Platform.pathSeparator;
    final clearedPattern = '%${sep}Cleared$sep%';
    final List<Map<String, dynamic>> maps = await db.query(
      'games',
      where: 'is_played = 0 AND play_count < 1 AND path NOT LIKE ?',
      whereArgs: [clearedPattern],
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
    return game.copyWith(tags: tags, images: images);
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

  Future<void> updateGamePath(int id, String newPath) async {
    final db = await _db;
    await db.update(
      'games',
      {'path': newPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteGame(int id) async {
    final db = await _db;
    await db.delete('games', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteGameByPath(String path) async {
    final db = await _db;
    await db.delete('games', where: 'path = ?', whereArgs: [path]);
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
    final maps = await db.query('games', columns: ['play_count'], where: 'id = ?', whereArgs: [id]);
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

  Future<void> setGameImages(int gameId, List<GameImage> images) async {
    final db = await _db;
    await db.delete('game_images', where: 'game_id = ?', whereArgs: [gameId]);
    for (int i = 0; i < images.length; i++) {
      await db.insert('game_images', {
        'game_id': gameId,
        'image_path': images[i].imagePath,
        'sort_order': i,
      });
    }
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
    for (int i = 0; i < imageIds.length; i++) {
      await db.update(
        'game_images',
        {'sort_order': i},
        where: 'id = ? AND game_id = ?',
        whereArgs: [imageIds[i], gameId],
      );
    }
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
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM games WHERE is_played = 1 OR play_count > 0');
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
