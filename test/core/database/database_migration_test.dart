import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('数据库 11 升级到 13 时迁移通关状态和 Backup 路径字段', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE games (
        id INTEGER PRIMARY KEY,
        path TEXT NOT NULL,
        title TEXT
      )
    ''');
    await db.insert('games', {
      'id': 1,
      'path': r'C:\Games\Cleared\Example',
      'title': 'Example',
    });
    await db.insert('games', {
      'id': 2,
      'path': r'C:\Games\ClearedOther\Example',
      'title': 'Not cleared',
    });

    await DatabaseHelper.upgradeForTesting(db, 11);

    final columns = await db.rawQuery('PRAGMA table_info(games)');
    final columnNames = columns.map((row) => row['name']).toSet();
    expect(columnNames, containsAll(['is_cleared', 'cleared_backup_path']));

    final games = await db.query(
      'games',
      columns: ['id', 'is_cleared', 'cleared_backup_path'],
      orderBy: 'id ASC',
    );
    expect(games[0]['is_cleared'], 1);
    expect(games[1]['is_cleared'], 0);
    expect(games[0]['cleared_backup_path'], isNull);
  });
}
