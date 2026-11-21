import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late GameRepository repo;
  late Game original;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createForTesting(database);
    repo = GameRepository(database: database);
    final game = Game(
      path: r'C:\Library\Example',
      title: '原有标题',
      addedTime: DateTime(2026, 1, 1),
      isFavorite: true,
      isPlayed: true,
      playCount: 8,
      playDuration: 3600,
      rating: 4.5,
      review: '原有评价',
      gameLauncher: 'Example.exe',
      launcherLocked: true,
    );
    original = game.copyWith(id: await repo.insertGame(game));
    final tagId = await database.insert('tags', {
      'name': '原有标签',
      'type': Tag.typeCustom,
      'is_favorite': 0,
    });
    await repo.addTagToGame(original.id!, tagId);
    await database.insert('game_images', {
      'game_id': original.id,
      'image_path': r'C:\Library\Example\cover.png',
      'sort_order': 0,
    });
  });

  tearDown(() => database.close());

  Future<void> expectOriginalPreserved() async {
    final games = await database.query('games');
    expect(games, hasLength(1));
    expect(Game.fromMap(games.single).toMap(), original.toMap());
    expect(await repo.getGameTags(original.id!), hasLength(1));
    expect(await repo.getGameImages(original.id!), hasLength(1));
    expect((await database.rawQuery('PRAGMA integrity_check')).single.values,
        ['ok']);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  }

  for (final duplicatePath in [
    r'C:\Library\Example',
    r'c:\library\EXAMPLE',
    'C:/Library/Example/',
    r'C:\Library\Other\..\Example\.',
  ]) {
    test('重复路径 $duplicatePath 返回明确提示并保留原记录及关联', () async {
      await expectLater(
        repo.insertGame(Game(path: duplicatePath, title: '重复导入')),
        throwsA(
            predicate<Object>((error) => error.toString().contains('已在库中'))),
      );
      await expectOriginalPreserved();
    });

    test('按路径查询 $duplicatePath 能找到原记录', () async {
      expect((await repo.getGameByPath(duplicatePath))?.id, original.id);
      expect(
          (await repo.getStoredGameByPath(duplicatePath))?.path, original.path);
    });
  }

  test('同批并发添加同一目录只保留一个新记录', () async {
    final results = await Future.wait([
      r'C:\Library\NewGame',
      'c:/library/newgame/',
      r'C:\Library\NewGame\.',
    ].map((gamePath) async {
      try {
        return await repo.insertGame(Game(path: gamePath, title: '新游戏'));
      } catch (error) {
        expect(error.toString(), contains('已在库中'));
        return null;
      }
    }));
    expect(results.whereType<int>(), hasLength(1));
    expect(await database.query('games'), hasLength(2));
    expect((await repo.getGameById(original.id!))?.title, original.title);
  });

  test('重复项失败后仍可继续添加不同目录，保存原始路径写法', () async {
    await expectLater(
      repo.insertGame(Game(path: original.path)),
      throwsA(predicate<Object>((error) => error.toString().contains('已在库中'))),
    );
    const newPath = 'C:/Library/NewGame/';
    final id = await repo.insertGame(Game(path: newPath, title: '新游戏'));
    expect((await repo.getGameById(id))?.path, newPath);
    expect(await database.query('games'), hasLength(2));
  });
}
