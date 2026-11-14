import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/game_scanner_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporary;
  late Database database;
  late AppSettings settings;
  late _ScanRepository repo;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hgm_duplicate_scan_');
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createForTesting(database);
    repo = _ScanRepository(database);
    settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
  });

  tearDown(() async {
    await settings.flush();
    AppSettings.invalidateCache();
    await database.close();
    final resolved = path.normalize(path.absolute(temporary.path));
    if (!path.isWithin(path.normalize(path.absolute(Directory.systemTemp.path)),
            resolved) ||
        !path.basename(resolved).startsWith('hgm_duplicate_scan_')) {
      throw StateError('临时目录超出测试范围');
    }
    await temporary.delete(recursive: true);
  });

  Future<String> createGame(String name) async {
    final folder = path.join(temporary.path, name);
    await GameDataPaths.ensureDataDir(folder);
    await GameDataPaths.metadataFile(folder).writeAsString(jsonEncode({
      'title': '扫描标题 $name',
      'tags': ['测试标签'],
    }));
    return folder;
  }

  test('扫描匹配不同大小写和分隔符的已有路径，保留 ID、个人数据及存储路径', () async {
    final folder = await createGame('Example');
    final storedPath = '${folder.replaceAll('\\', '/').toUpperCase()}/';
    final initial = Game(
      path: storedPath,
      title: '旧标题',
      addedTime: DateTime(2000),
      isFavorite: true,
      isPlayed: true,
      rating: 4.5,
      review: '个人评价',
      playCount: 8,
      playDuration: 3600,
    );
    final id = await repo.insertGame(initial);

    final scanner = GameScannerService(gameRepository: repo);
    await scanner.scanGameLibrary(temporary.path);
    await scanner.scanGameLibrary(temporary.path);

    final rows = await database.query('games');
    expect(rows, hasLength(1));
    final game = Game.fromMap(rows.single);
    expect(game.id, id);
    expect(game.path, storedPath);
    expect(game.title, '扫描标题 Example');
    expect(game.isFavorite, isTrue);
    expect(game.isPlayed, isTrue);
    expect(game.playCount, initial.playCount);
    expect(game.playDuration, initial.playDuration);
    expect(game.rating, initial.rating);
    expect(game.review, initial.review);
    expect(game.addedTime, initial.addedTime);
  });

  test('扫描快照之后已有目录入库，写库时跳过且继续保存其他新游戏', () async {
    final existingFolder = await createGame('Existing');
    await createGame('NewGame');
    repo.beforeWrite = () async {
      await database.insert('games', {
        'path': existingFolder,
        'title': '并发入库标题',
        'is_favorite': 1,
        'rating': 5,
      });
    };
    final scanner = GameScannerService(gameRepository: repo);
    await scanner.scanGameLibrary(temporary.path);
    final rows = await database.query('games');
    expect(rows, hasLength(2));
    final existing = rows.singleWhere((row) => row['path'] == existingFolder);
    expect(existing['title'], '并发入库标题');
    expect(existing['is_favorite'], 1);
    expect(existing['rating'], 5);
    expect(scanner.isScanning, isFalse);
    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

class _ScanRepository extends GameRepository {
  final Database scanDatabase;
  Future<void> Function()? beforeWrite;

  _ScanRepository(this.scanDatabase) : super(database: scanDatabase);

  @override
  Future<List<Game>> getAllGames() async =>
      (await scanDatabase.query('games')).map(Game.fromMap).toList();

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action) async {
    await beforeWrite?.call();
    beforeWrite = null;
    return super.transaction(action);
  }
}
