import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/app_paths.dart';

class DatabaseHelper {
  static Database? _database;
  static Future<Database>? _databaseFuture;
  static const int _databaseVersion = 9;

  static Future<String> getDataDir() => AppPaths.rootDir;

  static Future<String> getDatabasePath() => AppPaths.databaseFile;

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

    _database = db;
    return db;
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE games ADD COLUMN cover_index INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE games ADD COLUMN rating REAL DEFAULT 0');
      await db.execute('ALTER TABLE games ADD COLUMN review TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE games ADD COLUMN save_path TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE games ADD COLUMN game_launcher TEXT');
      await db.execute('ALTER TABLE games ADD COLUMN launcher_locked INTEGER NOT NULL DEFAULT 0');
      await db.execute('''
        CREATE TABLE tools (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          path TEXT UNIQUE NOT NULL,
          sort_order INTEGER DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE games ADD COLUMN use_locale_emulator INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE games ADD COLUMN maker TEXT');
      await db.execute('ALTER TABLE games ADD COLUMN maker_url TEXT');
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE games ADD COLUMN play_duration INTEGER DEFAULT 0');
    }
    if (oldVersion < 9) {
      await db.execute('CREATE INDEX idx_games_is_played ON games(is_played)');
      await db.execute('CREATE INDEX idx_games_is_favorite ON games(is_favorite)');
      await db.execute('CREATE INDEX idx_game_tag_relation_tag_id ON game_tag_relation(tag_id)');
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
        cover_index INTEGER DEFAULT 0,
        rating REAL DEFAULT 0,
        review TEXT,
        save_path TEXT,
        game_launcher TEXT,
        launcher_locked INTEGER NOT NULL DEFAULT 0,
        use_locale_emulator INTEGER NOT NULL DEFAULT 0,
        maker TEXT,
        maker_url TEXT,
        play_duration INTEGER DEFAULT 0
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
    await db.execute('CREATE INDEX idx_games_last_played ON games(last_played_time)');
    await db.execute('CREATE INDEX idx_games_added_time ON games(added_time)');
    await db.execute('CREATE INDEX idx_games_is_played ON games(is_played)');
    await db.execute('CREATE INDEX idx_games_is_favorite ON games(is_favorite)');
    await db.execute('CREATE INDEX idx_tags_type ON tags(type)');
    await db.execute('CREATE INDEX idx_game_images_game_id ON game_images(game_id)');
    await db.execute('CREATE INDEX idx_game_tag_relation_tag_id ON game_tag_relation(tag_id)');

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
