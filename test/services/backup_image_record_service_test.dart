import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/backup_image_record_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hgm_image_records_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('无图片备份导入后保留当前有效图片和封面', () async {
    final cover = await _createImage(tempDir, 'cover.png');
    final detail = await _createImage(tempDir, 'detail.png');
    final currentDb =
        await _openTestDatabase(path.join(tempDir.path, 'current.db'));
    final importedDb =
        await _openTestDatabase(path.join(tempDir.path, 'imported.db'));

    try {
      await currentDb.insert('games', {
        'id': 1,
        'path': path.join(tempDir.path, 'GameA'),
        'title': 'Game A',
        'cover_index': 1,
      });
      await _insertImage(currentDb, 1, cover.path, 0);
      await _insertImage(currentDb, 1, detail.path, 1);

      final service = BackupImageRecordService();
      final preserved = await service.capture(currentDb);

      await importedDb.insert('games', {
        'id': 99,
        'path': path.join(tempDir.path, 'GameA'),
        'title': 'Game A',
        'cover_index': 0,
      });
      expect(await service.merge(importedDb, preserved), 1);

      final images = await importedDb.query(
        'game_images',
        orderBy: 'sort_order',
      );
      expect(images.map((row) => row['image_path']), [cover.path, detail.path]);
      final game = (await importedDb.query('games')).single;
      expect(game['cover_index'], 1);
    } finally {
      await currentDb.close();
      await importedDb.close();
    }
  });

  test('失效旧路径按文件名修复并移除无法显示的记录', () async {
    final cover = await _createImage(tempDir, 'cover.png');
    final currentDb =
        await _openTestDatabase(path.join(tempDir.path, 'current.db'));
    final importedDb =
        await _openTestDatabase(path.join(tempDir.path, 'imported.db'));
    final oldCoverPath = path.join('Z:', 'OldGame', 'cover.png');

    try {
      await currentDb.insert('games', {
        'id': 1,
        'path': path.join(tempDir.path, 'GameA'),
        'title': 'Game A',
        'cover_index': 0,
      });
      await _insertImage(currentDb, 1, cover.path, 0);
      final service = BackupImageRecordService();
      final preserved = await service.capture(currentDb);

      await importedDb.insert('games', {
        'id': 1,
        'path': path.join(tempDir.path, 'MovedGameA'),
        'title': 'Game A',
        'cover_index': 0,
        'intro': '[图片:$oldCoverPath]',
      });
      await _insertImage(importedDb, 1, oldCoverPath, 0);
      await _insertImage(importedDb, 1, path.join('Z:', 'missing.png'), 1);

      expect(await service.merge(importedDb, preserved), 1);
      final images = await importedDb.query('game_images');
      expect(images.map((row) => row['image_path']), [cover.path]);
      final game = (await importedDb.query('games')).single;
      expect(game['intro'], '[图片:${cover.path}]');
      expect(game['cover_index'], 0);
    } finally {
      await currentDb.close();
      await importedDb.close();
    }
  });
}

Future<File> _createImage(Directory directory, String name) async {
  final file = File(path.join(directory.path, name));
  await file.writeAsBytes([1, 2, 3, 4]);
  return file;
}

Future<Database> _openTestDatabase(String databasePath) async {
  return openDatabase(
    databasePath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE games (
          id INTEGER PRIMARY KEY,
          path TEXT NOT NULL,
          title TEXT,
          cover_index INTEGER DEFAULT 0,
          intro TEXT,
          features TEXT,
          changelog TEXT,
          guide TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE game_images (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          game_id INTEGER NOT NULL,
          image_path TEXT NOT NULL,
          sort_order INTEGER DEFAULT 0
        )
      ''');
    },
  );
}

Future<void> _insertImage(
  Database db,
  int gameId,
  String imagePath,
  int sortOrder,
) async {
  await db.insert('game_images', {
    'game_id': gameId,
    'image_path': imagePath,
    'sort_order': sortOrder,
  });
}
