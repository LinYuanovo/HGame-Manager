import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/app_paths.dart';
import 'app_logger.dart';

class AppDataMigrationService {
  static const markerFileName = '.app_data_migration_v1.json';

  final String? currentExecutableDirectory;
  final List<String>? candidateExecutableDirectories;
  final AppLogger _log;

  AppDataMigrationService({
    this.currentExecutableDirectory,
    this.candidateExecutableDirectories,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  Future<AppDataMigrationResult> migrateIfNeeded() async {
    final currentDir =
        currentExecutableDirectory ?? path.dirname(Platform.resolvedExecutable);
    final currentRoot = Directory(path.join(currentDir, 'hgame_manager_data'));
    await currentRoot.create(recursive: true);
    if (await File(path.join(currentRoot.path, markerFileName)).exists()) {
      return const AppDataMigrationResult.none();
    }

    final source = await _findSource(currentDir);
    if (source == null) {
      return const AppDataMigrationResult.none();
    }

    final backupRoot = Directory(path.join(
      currentRoot.path,
      'migration_backups',
      _timestamp(),
      path.basename(source.path),
    ));
    try {
      await _copyTree(source, backupRoot, overwrite: true);
      final copied = await _copyTree(source, currentRoot);
      final marker = File(path.join(currentRoot.path, markerFileName));
      await marker.writeAsString(
        jsonEncode({
          'version': 1,
          'source': source.path,
          'target': currentRoot.path,
          'backup': backupRoot.path,
          'copied': copied,
          'created_at': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
      _log.info(
        'AppDataMigration',
        '应用数据迁移完成: source=${source.path}, target=${currentRoot.path}, '
            'backup=${backupRoot.path}, copied=${copied.length}',
      );
      return AppDataMigrationResult(
        source: source.path,
        target: currentRoot.path,
        backup: backupRoot.path,
        copied: copied,
      );
    } catch (e, stackTrace) {
      _log.error(
        'AppDataMigration',
        '应用数据迁移失败: source=${source.path}, target=${currentRoot.path}',
        e,
        stackTrace,
      );
      return const AppDataMigrationResult.none();
    }
  }

  Future<Directory?> _findSource(String currentDir) async {
    final currentKey = _key(currentDir);
    final candidates = <String>{};
    if (candidateExecutableDirectories != null) {
      candidates.addAll(candidateExecutableDirectories!);
    } else {
      final current = Directory(currentDir);
      final parent = current.parent;
      candidates.add(parent.path);
      await _addChildDirectories(parent, candidates);
      if (parent.path != parent.parent.path) {
        candidates.add(parent.parent.path);
        await _addChildDirectories(parent.parent, candidates);
      }
    }

    final sources = <_MigrationSource>[];
    for (final candidate in candidates) {
      if (_key(candidate) == currentKey) continue;
      final root = Directory(path.join(candidate, 'hgame_manager_data'));
      if (!await root.exists()) continue;

      final settings = File(path.join(root.path, 'settings.json'));
      final database = File(path.join(root.path, 'hgame_manager.db'));
      final hasSettings = await _hasLibrarySettings(settings);
      final hasDatabase =
          await database.exists() && await database.length() > 0;
      if (!hasSettings && !hasDatabase) continue;

      var score = 0;
      if (hasSettings) score += 4;
      if (hasDatabase) score += 2;
      if (await Directory(path.join(root.path, 'game_images')).exists()) {
        score++;
      }
      final modified = await _latestModified(root);
      sources.add(_MigrationSource(root, score, modified));
    }

    sources.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : b.modified.compareTo(a.modified);
    });
    final selected = sources.isEmpty ? null : sources.first;
    if (selected != null) {
      _log.info(
        'AppDataMigration',
        '发现候选旧应用数据: source=${selected.root.path}, score=${selected.score}',
      );
    }
    return selected?.root;
  }

  Future<void> _addChildDirectories(
      Directory parent, Set<String> candidates) async {
    if (!await parent.exists()) return;
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is Directory) candidates.add(entity.path);
    }
  }

  Future<bool> _hasLibrarySettings(File file) async {
    if (!await file.exists() || await file.length() == 0) return false;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return false;
      return const [
        'library_path',
        'sorted_path',
        'sorted_paths',
        'cleared_paths',
      ].any((key) => data[key] != null && data[key].toString().isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<DateTime> _latestModified(Directory root) async {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      try {
        final modified = (await entity.stat()).modified;
        if (modified.isAfter(latest)) latest = modified;
      } catch (_) {}
    }
    return latest;
  }

  Future<List<String>> _copyTree(
    Directory source,
    Directory target, {
    bool overwrite = false,
  }) async {
    final copied = <String>[];
    await target.create(recursive: true);
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      final relative = path.relative(entity.path, from: source.path);
      if (relative == markerFileName ||
          relative.startsWith('migration_backups${path.separator}')) {
        continue;
      }
      final targetPath = path.join(target.path, relative);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }
      if (entity is! File) continue;
      final targetFile = File(targetPath);
      if (await targetFile.exists() && !overwrite) {
        if (relative == 'settings.json' &&
            !await _hasLibrarySettings(targetFile) &&
            await _hasLibrarySettings(entity)) {
          await _mergeSettings(entity, targetFile);
          copied.add(relative);
        } else {
          continue;
        }
        continue;
      }
      await targetFile.parent.create(recursive: true);
      await entity.copy(targetPath);
      copied.add(relative);
    }
    return copied;
  }

  Future<void> _mergeSettings(File source, File target) async {
    try {
      final sourceData = jsonDecode(await source.readAsString());
      final targetData = jsonDecode(await target.readAsString());
      if (sourceData is Map<String, dynamic> &&
          targetData is Map<String, dynamic>) {
        await target.writeAsString(
          jsonEncode({...sourceData, ...targetData}),
          flush: true,
        );
        return;
      }
    } catch (_) {}
    await source.copy(target.path);
  }

  static String _key(String value) =>
      path.normalize(value).replaceAll('\\', '/').toLowerCase();

  static String _timestamp() => DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');

  /// 迁移后数据库中的应用管理图片仍指向旧 exe 目录，需要改为新目录。
  static Future<void> rewriteMigratedPaths(Database db) async {
    final root = await AppPaths.rootDir;
    final marker = File(path.join(root, markerFileName));
    if (!await marker.exists()) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data['paths_rewritten'] == true) return;
    final source = data['source'] as String?;
    final target = data['target'] as String?;
    if (source == null || target == null || _key(source) == _key(target)) {
      return;
    }

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='game_images'",
    );
    var updated = 0;
    if (tables.isNotEmpty) {
      final rows = await db.query('game_images', columns: ['id', 'image_path']);
      for (final row in rows) {
        final id = row['id'];
        final oldPath = row['image_path'] as String?;
        if (id == null || oldPath == null || !_hasPrefix(oldPath, source)) {
          continue;
        }
        final newPath = _replacePrefix(oldPath, source, target);
        await db.update('game_images', {'image_path': newPath},
            where: 'id = ?', whereArgs: [id]);
        updated++;
      }
    }

    final backupDir = Directory(path.join(root, 'cleared_metadata_backups'));
    if (await backupDir.exists()) {
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final content = await entity.readAsString();
          final rewritten = _replaceAllPathForms(content, source, target);
          if (rewritten != content) {
            await entity.writeAsString(rewritten, flush: true);
          }
        } catch (_) {}
      }
    }

    data['paths_rewritten'] = true;
    data['updated_image_references'] = updated;
    await marker.writeAsString(jsonEncode(data), flush: true);
    AppLogger.instance.info(
      'AppDataMigration',
      '已修正迁移后的图片引用: source=$source, target=$target, updated=$updated',
    );
  }

  static bool _hasPrefix(String value, String prefix) {
    final normalizedValue = value.replaceAll('\\', '/');
    final normalizedPrefix = prefix.replaceAll('\\', '/');
    return normalizedValue
        .toLowerCase()
        .startsWith(normalizedPrefix.toLowerCase());
  }

  static String _replacePrefix(
      String value, String oldPrefix, String newPrefix) {
    final oldNormalized = oldPrefix.replaceAll('\\', '/');
    final valueNormalized = value.replaceAll('\\', '/');
    final suffix = valueNormalized.substring(oldNormalized.length);
    return '$newPrefix$suffix'.replaceAll('/', Platform.pathSeparator);
  }

  static String _replaceAllPathForms(
      String value, String oldPrefix, String newPrefix) {
    return value
        .replaceAll(oldPrefix, newPrefix)
        .replaceAll(
            oldPrefix.replaceAll('\\', '/'), newPrefix.replaceAll('\\', '/'))
        .replaceAll(
            oldPrefix.replaceAll('/', '\\'), newPrefix.replaceAll('/', '\\'));
  }
}

class AppDataMigrationResult {
  final String? source;
  final String? target;
  final String? backup;
  final List<String> copied;

  const AppDataMigrationResult({
    this.source,
    this.target,
    this.backup,
    this.copied = const [],
  });

  const AppDataMigrationResult.none()
      : source = null,
        target = null,
        backup = null,
        copied = const [];

  bool get migrated => source != null;
}

class _MigrationSource {
  final Directory root;
  final int score;
  final DateTime modified;

  const _MigrationSource(this.root, this.score, this.modified);
}
