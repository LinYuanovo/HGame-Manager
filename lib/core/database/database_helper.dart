import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/app_paths.dart';
import '../utils/app_settings.dart';
import '../utils/cleared_game_path_utils.dart';
import '../services/app_data_migration_service.dart';

class DatabaseHelper {
  static Database? _database;
  static Future<Database>? _databaseFuture;
  static const int _databaseVersion = 13;

  static Future<String> getDataDir() => AppPaths.rootDir;

  static Future<String> getDatabasePath() => AppPaths.databaseFile;

  /// 供数据库迁移测试调用。
  @visibleForTesting
  static Future<void> upgradeForTesting(Database db, int oldVersion) =>
      _onUpgrade(db, oldVersion, _databaseVersion);

  static Future<Database> get database async {
    if (_database != null) return _database!;
    return _databaseFuture ??= _initDatabase();
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasePath();

    final db = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
        await db.execute('PRAGMA cache_size = -8000');
      },
    );

    await AppDataMigrationService.rewriteMigratedPaths(db);

    _database = db;
    return db;
  }

  static Future<bool> _columnExists(
      Database db, String table, String column) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    return result.any((col) => col['name'] == column);
  }

  static Future<bool> _indexExists(Database db, String indexName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name=?",
      [indexName],
    );
    return result.isNotEmpty;
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      if (!await _columnExists(db, 'games', 'cover_index')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN cover_index INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 3) {
      if (!await _columnExists(db, 'games', 'rating')) {
        await db.execute('ALTER TABLE games ADD COLUMN rating REAL DEFAULT 0');
      }
      if (!await _columnExists(db, 'games', 'review')) {
        await db.execute('ALTER TABLE games ADD COLUMN review TEXT');
      }
    }
    if (oldVersion < 4) {
      if (!await _columnExists(db, 'games', 'save_path')) {
        await db.execute('ALTER TABLE games ADD COLUMN save_path TEXT');
      }
    }
    if (oldVersion < 5) {
      if (!await _columnExists(db, 'games', 'game_launcher')) {
        await db.execute('ALTER TABLE games ADD COLUMN game_launcher TEXT');
      }
      if (!await _columnExists(db, 'games', 'launcher_locked')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN launcher_locked INTEGER NOT NULL DEFAULT 0');
      }
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tools (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          path TEXT UNIQUE NOT NULL,
          sort_order INTEGER DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }
    if (oldVersion < 6) {
      if (!await _columnExists(db, 'games', 'use_locale_emulator')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN use_locale_emulator INTEGER NOT NULL DEFAULT 0');
      }
    }
    if (oldVersion < 7) {
      if (!await _columnExists(db, 'games', 'maker')) {
        await db.execute('ALTER TABLE games ADD COLUMN maker TEXT');
      }
      if (!await _columnExists(db, 'games', 'maker_url')) {
        await db.execute('ALTER TABLE games ADD COLUMN maker_url TEXT');
      }
    }
    if (oldVersion < 8) {
      if (!await _columnExists(db, 'games', 'play_duration')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN play_duration INTEGER DEFAULT 0');
      }
    }
    if (oldVersion < 9) {
      if (!await _indexExists(db, 'idx_games_is_played')) {
        await db
            .execute('CREATE INDEX idx_games_is_played ON games(is_played)');
      }
      if (!await _indexExists(db, 'idx_games_is_favorite')) {
        await db.execute(
            'CREATE INDEX idx_games_is_favorite ON games(is_favorite)');
      }
      if (!await _indexExists(db, 'idx_game_tag_relation_tag_id')) {
        await db.execute(
            'CREATE INDEX idx_game_tag_relation_tag_id ON game_tag_relation(tag_id)');
      }
    }
    if (oldVersion < 10) {
      if (!await _columnExists(db, 'games', 'guide')) {
        await db.execute('ALTER TABLE games ADD COLUMN guide TEXT');
      }
    }
    if (oldVersion < 11) {
      if (!await _columnExists(db, 'games', 'intro_scroll_position')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN intro_scroll_position REAL DEFAULT 0');
      }
      if (!await _columnExists(db, 'games', 'guide_scroll_position')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN guide_scroll_position REAL DEFAULT 0');
      }
    }
    if (oldVersion < 12) {
      if (!await _columnExists(db, 'games', 'is_cleared')) {
        await db.execute(
            'ALTER TABLE games ADD COLUMN is_cleared INTEGER NOT NULL DEFAULT 0');
      }
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_games_is_cleared ON games(is_cleared)');
      await _migrateClearedPaths(db);
    }
    if (oldVersion < 13) {
      if (!await _columnExists(db, 'games', 'cleared_backup_path')) {
        await db
            .execute('ALTER TABLE games ADD COLUMN cleared_backup_path TEXT');
      }
    }
  }

  static Future<void> _migrateClearedPaths(Database db) async {
    final clearedRoots = <String>[];
    try {
      final prefs = await AppSettings.load();
      final raw = prefs.getString('cleared_paths') ?? '';
      if (raw.startsWith('{')) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        clearedRoots.addAll(decoded.values
            .map((value) => value?.toString() ?? '')
            .where((value) => value.isNotEmpty));
      }
    } catch (_) {}

    final games = await db.query('games', columns: ['id', 'path']);
    for (final game in games) {
      final gamePath = game['path'] as String? ?? '';
      final normalized = gamePath.replaceAll('\\', '/').toLowerCase();
      final segments = normalized.split('/').where((part) => part.isNotEmpty);
      final isLegacyCleared =
          segments.contains('cleared') || segments.contains('backup');
      final isConfiguredCleared = clearedRoots.any(
        (root) => ClearedGamePathUtils.isSameOrChildPath(gamePath, root),
      );
      if (isLegacyCleared || isConfiguredCleared) {
        await db.update('games', {'is_cleared': 1},
            where: 'id = ?', whereArgs: [game['id']]);
      }
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT UNIQUE NOT NULL,
        title TEXT,
        version TEXT,
        intro TEXT,
        features TEXT,
        changelog TEXT,
        download_url TEXT,
        source_url TEXT,
        play_count INTEGER DEFAULT 0,
        last_played_time DATETIME,
        added_time DATETIME DEFAULT CURRENT_TIMESTAMP,
        is_favorite INTEGER DEFAULT 0,
        is_played INTEGER DEFAULT 0,
        is_cleared INTEGER NOT NULL DEFAULT 0,
        cleared_backup_path TEXT,
        cover_index INTEGER DEFAULT 0,
        rating REAL DEFAULT 0,
        review TEXT,
        save_path TEXT,
        game_launcher TEXT,
        launcher_locked INTEGER NOT NULL DEFAULT 0,
        use_locale_emulator INTEGER NOT NULL DEFAULT 0,
        maker TEXT,
        maker_url TEXT,
        play_duration INTEGER DEFAULT 0,
        guide TEXT,
        intro_scroll_position REAL DEFAULT 0,
        guide_scroll_position REAL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE game_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        game_id INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        sort_order INTEGER DEFAULT 0,
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        display_name TEXT,
        is_favorite INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(type, name)
      )
    ''');

    await db.execute('''
      CREATE TABLE game_tag_relation (
        game_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (game_id, tag_id),
        FOREIGN KEY (game_id) REFERENCES games (id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        path TEXT UNIQUE NOT NULL,
        sort_order INTEGER DEFAULT 0,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_games_title ON games(title)');
    await db.execute('CREATE INDEX idx_games_play_count ON games(play_count)');
    await db.execute(
        'CREATE INDEX idx_games_last_played ON games(last_played_time)');
    await db.execute('CREATE INDEX idx_games_added_time ON games(added_time)');
    await db.execute('CREATE INDEX idx_games_is_played ON games(is_played)');
    await db
        .execute('CREATE INDEX idx_games_is_favorite ON games(is_favorite)');
    await db.execute('CREATE INDEX idx_games_is_cleared ON games(is_cleared)');
    await db.execute('CREATE INDEX idx_tags_type ON tags(type)');
    await db.execute(
        'CREATE INDEX idx_game_images_game_id ON game_images(game_id)');
    await db.execute(
        'CREATE INDEX idx_game_tag_relation_tag_id ON game_tag_relation(tag_id)');

    // Insert default series tags
    final defaultSeries = ['RPG', 'ADV', 'ACT', 'SLG', 'AVG', 'FPS', 'TPS'];
    for (final series in defaultSeries) {
      await db.insert('tags', {
        'name': series,
        'type': 'series',
        'display_name': series,
        'is_favorite': 0,
      });
    }
  }

  static Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
      _databaseFuture = null;
    }
  }
}
