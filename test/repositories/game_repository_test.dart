import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _snapshotDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = ON');
  await db.execute('''CREATE TABLE games (
    id INTEGER PRIMARY KEY, path TEXT UNIQUE, title TEXT, version TEXT,
    intro TEXT, features TEXT, changelog TEXT, download_url TEXT, source_url TEXT,
    play_count INTEGER, last_played_time TEXT, added_time TEXT,
    is_favorite INTEGER, is_played INTEGER, is_cleared INTEGER,
    cleared_backup_path TEXT, cover_index INTEGER, rating REAL, review TEXT,
    save_path TEXT, play_duration INTEGER, maker TEXT, maker_url TEXT,
    game_launcher TEXT, launcher_locked INTEGER, use_locale_emulator INTEGER,
    guide TEXT, intro_scroll_position REAL, guide_scroll_position REAL
  )''');
  await db.execute('''CREATE TABLE tags (
    id INTEGER PRIMARY KEY, name TEXT, type TEXT, display_name TEXT,
    is_favorite INTEGER DEFAULT 0
  )''');
  await db.execute('''CREATE TABLE game_tag_relation (
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES tags(id), PRIMARY KEY(game_id, tag_id)
  )''');
  await db.execute('''CREATE TABLE game_images (
    id INTEGER PRIMARY KEY, game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    image_path TEXT, sort_order INTEGER
  )''');
  return db;
}

void main() {
  setUpAll(sqfliteFfiInit);
  group('GameRepository Image Methods', () {
    test('deleteGameImage removes image', () async {
      final repo = GameRepository();
      expect(repo.deleteGameImage, isA<Function>());
    });

    test('deleteGameImagesByGameId removes all game images', () async {
      final repo = GameRepository();
      expect(repo.deleteGameImagesByGameId, isA<Function>());
    });

    test('updateImageOrder updates single image order', () async {
      final repo = GameRepository();
      expect(repo.updateImageOrder, isA<Function>());
    });

    test('updateGameImagesOrder updates order', () async {
      final repo = GameRepository();
      expect(repo.updateGameImagesOrder, isA<Function>());
    });
  });

  group('刮削快照恢复', () {
    test('仅更新和恢复刮削字段，保留期间新增的游玩记录与收藏评分', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      final original =
          Game(id: 7, path: '游戏目录', title: '原游戏', playDuration: 60);
      await repo.insertGame(original);
      await db.update(
          'games',
          {
            'play_duration': 120,
            'is_favorite': 1,
            'rating': 4.5,
          },
          where: 'id = 7');

      await repo
          .updateScrapedFields(original.copyWith(title: '候选游戏', maker: '厂商'));
      var current = (await db.query('games', where: 'id = 7')).single;
      expect(current['title'], '候选游戏');
      expect(current['play_duration'], 120);
      await repo.restoreScrapeSnapshot(
          gamePath: original.path, original: original, metadataOnly: true);
      current = (await db.query('games', where: 'id = 7')).single;
      expect(current['title'], '原游戏');
      expect(current['maker'], isNull);
      expect(current['play_duration'], 120);
      expect(current['is_favorite'], 1);
      expect(current['rating'], 4.5);
    });

    test('严格插入拒绝同路径记录且保留原游戏关系', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      await repo.insertGame(Game(id: 7, path: '游戏目录', title: '已有游戏'));
      await db
          .insert('tags', {'id': 8, 'name': '已有标签', 'type': Tag.typeCustom});
      await db.insert('game_tag_relation', {'game_id': 7, 'tag_id': 8});

      await expectLater(
          repo.insertGame(Game(path: '游戏目录', title: '候选游戏'),
              replaceExisting: false),
          throwsA(isA<DatabaseException>()));

      expect((await db.query('games')).single['id'], 7);
      expect((await db.query('games')).single['title'], '已有游戏');
      expect((await db.query('game_tag_relation')).single['tag_id'], 8);
    });

    test('恢复全部可空字段、原标签和图片 ID，保留其他游戏及全局新标签', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      final original = Game(
        id: 7,
        path: r'C:\Games\Example',
        title: '原游戏',
        isFavorite: true,
        rating: 4.5,
        playCount: 3,
        tags: [Tag(id: 8, name: '原标签', type: Tag.typeCustom)],
        images: [
          GameImage(id: 19, gameId: 7, imagePath: '原图.jpg', sortOrder: 4)
        ],
      );
      await db.insert('games', original.toMap());
      await db.insert(
          'games', Game(id: 9, path: '其他游戏', title: '其他资料').toMap());
      await db.insert('tags', {'id': 8, 'name': '原标签', 'type': Tag.typeCustom});
      await db
          .insert('tags', {'id': 10, 'name': '新标签', 'type': Tag.typeCustom});
      await db.insert('game_tag_relation', {'game_id': 7, 'tag_id': 10});
      await db.insert('game_tag_relation', {'game_id': 9, 'tag_id': 10});
      await db.insert('game_images',
          {'id': 22, 'game_id': 7, 'image_path': '新图.jpg', 'sort_order': 0});
      await db.insert('game_images',
          {'id': 23, 'game_id': 9, 'image_path': '其他图.jpg', 'sort_order': 1});
      await repo.updateGame(original.copyWith(
        title: '候选标题',
        intro: '候选简介',
        features: '候选特性',
        changelog: '候选更新',
        sourceUrl: '候选来源',
        maker: '候选厂商',
        makerUrl: '候选厂商链接',
        review: '新评论',
        guide: '新攻略',
        savePath: '新存档',
        clearedBackupPath: '新备份',
      ));

      await repo.restoreScrapeSnapshot(
          gamePath: original.path, original: original);

      final saved = (await db.query('games', where: 'id = 7')).single;
      expect(saved['title'], '原游戏');
      expect(saved['is_favorite'], 1);
      expect(saved['rating'], 4.5);
      expect(saved['play_count'], 3);
      for (final field in [
        'intro',
        'features',
        'changelog',
        'source_url',
        'maker',
        'maker_url',
        'review',
        'guide',
        'save_path',
        'cleared_backup_path'
      ]) {
        expect(saved[field], isNull, reason: '$field 应还原为空');
      }
      expect(await db.query('game_tag_relation', where: 'game_id = 7'), [
        {'game_id': 7, 'tag_id': 8}
      ]);
      expect(await db.query('game_images', where: 'game_id = 7'),
          [original.images.single.toMap()]);
      expect(
          (await db.query('games', where: 'id = 9')).single['title'], '其他资料');
      expect((await db.query('game_images', where: 'game_id = 9')).single['id'],
          23);
      expect((await db.query('tags', where: 'id = 10')).single['name'], '新标签');
      expect(await db.query('game_tag_relation', where: 'game_id = 9'), [
        {'game_id': 9, 'tag_id': 10}
      ]);
    });

    test('原记录不存在时仅撤销该路径的新游戏和关系', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      await db.insert('games', Game(id: 7, path: '新游戏').toMap());
      await db.insert('games', Game(id: 9, path: '其他游戏').toMap());
      await db.insert('tags', {'id': 8, 'name': '新标签', 'type': Tag.typeCustom});
      for (final id in [7, 9]) {
        await db.insert('game_tag_relation', {'game_id': id, 'tag_id': 8});
        await db.insert('game_images',
            {'game_id': id, 'image_path': '$id.jpg', 'sort_order': 0});
      }

      await repo.restoreScrapeSnapshot(gamePath: '新游戏', original: null);

      expect((await db.query('games')).single['id'], 9);
      expect((await db.query('game_tag_relation')).single['game_id'], 9);
      expect((await db.query('game_images')).single['game_id'], 9);
      expect((await db.query('tags')).single['id'], 8);
    });

    test('恢复关联时失败撤销字段和图片恢复，维持失败前状态', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      final original = Game(
          id: 7,
          path: '原游戏',
          title: '原标题',
          tags: [Tag(id: 8, name: '原标签', type: Tag.typeCustom)]);
      await db.insert('games', original.copyWith(title: '新标题').toMap());
      await db.insert('tags', {'id': 8, 'name': '原标签', 'type': Tag.typeCustom});
      await db.insert('game_images',
          {'id': 22, 'game_id': 7, 'image_path': '新图.jpg', 'sort_order': 0});
      await db.execute('''CREATE TRIGGER fail_snapshot_restore
        BEFORE INSERT ON game_tag_relation BEGIN
          SELECT RAISE(ABORT, '模拟标签恢复失败');
        END''');

      await expectLater(
          repo.restoreScrapeSnapshot(
              gamePath: original.path, original: original),
          throwsA(isA<DatabaseException>()));

      expect((await db.query('games')).single['title'], '新标题');
      expect((await db.query('game_images')).single['image_path'], '新图.jpg');
      expect(await db.query('game_tag_relation'), isEmpty);
    });

    test('标签编辑的真实 COMMIT 失败会回滚且后续数据库操作仍可执行', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      final original = Game(id: 7, path: '原游戏', title: '原标题');
      await db.insert('games', original.toMap());
      await db.execute('''CREATE TABLE deferred_tag_failure (
        game_id INTEGER REFERENCES games(id) DEFERRABLE INITIALLY DEFERRED
      )''');
      await db.execute('''CREATE TRIGGER fail_tag_commit
        AFTER INSERT ON game_tag_relation BEGIN
          INSERT INTO deferred_tag_failure(game_id) VALUES(999);
        END''');
      var beforeCommitCalled = false;

      await expectLater(
          repo.updateGameWithTags(
              original.copyWith(
                  title: '新标题', tags: [Tag(name: '新标签', type: Tag.typeCustom)]),
              beforeCommit: () async {
            beforeCommitCalled = true;
          }),
          throwsA(isA<DatabaseException>()));

      expect(beforeCommitCalled, isTrue);
      expect((await db.query('games')).single['title'], '原标题');
      expect(await db.query('tags'), isEmpty);
      expect(await db.query('game_tag_relation'), isEmpty);
      expect(await db.query('deferred_tag_failure'), isEmpty);
      await db.execute('DROP TRIGGER fail_tag_commit');
      await repo.updateGameWithTags(
          original.copyWith(tags: [Tag(name: '可保存标签', type: Tag.typeCustom)]));
      expect((await db.query('tags')).single['name'], '可保存标签');
    });

    test('快照恢复的真实 COMMIT 失败不会留下部分恢复', () async {
      final db = await _snapshotDatabase();
      addTearDown(db.close);
      final repo = GameRepository(database: db);
      final original = Game(
          id: 7,
          path: '原游戏',
          title: '原标题',
          tags: [Tag(id: 8, name: '原标签', type: Tag.typeCustom)]);
      await db.insert('games', original.copyWith(title: '新标题').toMap());
      await db.insert('tags', {'id': 8, 'name': '原标签', 'type': Tag.typeCustom});
      await db.execute('''CREATE TABLE deferred_snapshot_failure (
        game_id INTEGER REFERENCES games(id) DEFERRABLE INITIALLY DEFERRED
      )''');
      await db.execute('''CREATE TRIGGER fail_snapshot_commit
        AFTER INSERT ON game_tag_relation BEGIN
          INSERT INTO deferred_snapshot_failure(game_id) VALUES(999);
        END''');

      await expectLater(
          repo.restoreScrapeSnapshot(
              gamePath: original.path, original: original),
          throwsA(isA<DatabaseException>()));

      expect((await db.query('games')).single['title'], '新标题');
      expect(await db.query('game_tag_relation'), isEmpty);
      expect(await db.query('deferred_snapshot_failure'), isEmpty);
    });
  });
}
