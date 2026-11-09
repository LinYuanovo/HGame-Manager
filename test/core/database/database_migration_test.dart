import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('版本1迁移保留收藏、游玩记录和标签关系且可重复执行', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
        'CREATE TABLE games(id INTEGER PRIMARY KEY, path TEXT, title TEXT, is_played INTEGER, is_favorite INTEGER)');
    await db.execute(
        'CREATE TABLE game_tag_relation(game_id INTEGER, tag_id INTEGER)');
    await db.insert('games', {
      'id': 12,
      'path': r'C:\Games\Cleared\旧版本',
      'title': '旧游戏',
      'is_played': 1,
      'is_favorite': 1
    });
    await db.insert('game_tag_relation', {'game_id': 12, 'tag_id': 3});
    for (var attempt = 0; attempt < 2; attempt++) {
      await DatabaseHelper.upgradeForTesting(db, 1);
      final game = (await db.query('games')).single;
      expect(game['title'], '旧游戏');
      expect(game['is_favorite'], 1);
      expect(game['is_played'], 1);
      expect(game['is_cleared'], 1);
      expect(game.containsKey('cleared_backup_path'), isTrue);
      expect((await db.query('game_tag_relation')).single['tag_id'], 3);
      expect((await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok');
    }
  });

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
