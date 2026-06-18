import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';
import '../models/tool.dart';

class ToolRepository {
  Future<Database> get _db => DatabaseHelper.database;

  Future<List<Tool>> getAllTools() async {
    final db = await _db;
    final maps = await db.query('tools', orderBy: 'sort_order ASC, created_at DESC');
    return maps.map((m) => Tool.fromMap(m)).toList();
  }

  Future<Tool?> getToolById(int id) async {
    final db = await _db;
    final maps = await db.query('tools', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Tool.fromMap(maps.first);
  }

  Future<Tool?> getToolByPath(String path) async {
    final db = await _db;
    final maps = await db.query('tools', where: 'path = ?', whereArgs: [path]);
    if (maps.isEmpty) return null;
    return Tool.fromMap(maps.first);
  }

  Future<int> insertTool(Tool tool) async {
    final db = await _db;
    return await db.insert('tools', tool.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTool(Tool tool) async {
    final db = await _db;
    await db.update('tools', tool.toMap(), where: 'id = ?', whereArgs: [tool.id]);
  }

  Future<void> deleteTool(int id) async {
    final db = await _db;
    await db.delete('tools', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateSortOrder(int id, int sortOrder) async {
    final db = await _db;
    await db.update('tools', {'sort_order': sortOrder}, where: 'id = ?', whereArgs: [id]);
  }
}
