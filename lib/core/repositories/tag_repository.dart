import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class TagRepository {
  Future<Database> get _db => DatabaseHelper.database;

  Future<List<Tag>> getAllTags() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, COUNT(gtr.game_id) as game_count
      FROM tags t
      LEFT JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      GROUP BY t.id
      ORDER BY t.type ASC, t.name ASC
    ''');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<Tag>> getTagsByType(String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, COUNT(gtr.game_id) as game_count
      FROM tags t
      LEFT JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE t.type = ?
      GROUP BY t.id
      ORDER BY t.is_favorite DESC, t.name ASC
    ''', [type]);
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<List<Tag>> getCustomTags() => getTagsByType(Tag.typeCustom);

  Future<List<Tag>> getSeriesTags() => getTagsByType(Tag.typeSeries);

  Future<List<Tag>> getFavoriteTags() async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, COUNT(gtr.game_id) as game_count
      FROM tags t
      LEFT JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE t.is_favorite = 1
      GROUP BY t.id
      ORDER BY t.name ASC
    ''');
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<Tag?> getTagById(int id) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, COUNT(gtr.game_id) as game_count
      FROM tags t
      LEFT JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE t.id = ?
      GROUP BY t.id
    ''', [id]);
    if (maps.isEmpty) return null;
    return Tag.fromMap(maps.first);
  }

  Future<Tag?> getTagByNameAndType(String name, String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, COUNT(gtr.game_id) as game_count
      FROM tags t
      LEFT JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE t.name = ? AND t.type = ?
      GROUP BY t.id
    ''', [name, type]);
    if (maps.isEmpty) return null;
    return Tag.fromMap(maps.first);
  }

  Future<int> insertTag(Tag tag) async {
    final db = await _db;
    return await db.insert(
      'tags',
      tag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> insertOrGetTag(String name, String type, {String? displayName}) async {
    final existing = await getTagByNameAndType(name, type);
    if (existing != null) return existing.id!;

    final db = await _db;
    return await db.insert(
      'tags',
      {
        'name': name,
        'type': type,
        'display_name': displayName ?? name,
        'is_favorite': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateTag(Tag tag) async {
    final db = await _db;
    await db.update(
      'tags',
      tag.toMap(),
      where: 'id = ?',
      whereArgs: [tag.id],
    );
  }

  Future<void> deleteTag(int id) async {
    final db = await _db;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final db = await _db;
    await db.update(
      'tags',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Tag>> searchTags(String query, String type) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT t.*, COUNT(gtr.game_id) as game_count
      FROM tags t
      LEFT JOIN game_tag_relation gtr ON t.id = gtr.tag_id
      WHERE t.type = ? AND t.name LIKE ?
      GROUP BY t.id
      ORDER BY t.name ASC
    ''', [type, '%$query%']);
    return maps.map((map) => Tag.fromMap(map)).toList();
  }

  Future<int> deleteOrphanedTags() async {
    final db = await _db;
    return await db.delete(
      'tags',
      where: '''
        id NOT IN (
          SELECT DISTINCT t.id FROM tags t
          INNER JOIN game_tag_relation gtr ON t.id = gtr.tag_id
        ) AND is_favorite = 0
      ''',
    );
  }
}
