import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../database/database_helper.dart';

class DatabaseBackupService {
  static Future<List<int>> snapshot(Database database) async {
    final temporary = await Directory.systemTemp.createTemp('hgm_db_snapshot_');
    try {
      final destination = path.join(temporary.path, 'database.db');
      await database.execute('VACUUM INTO ?', [destination]);
      return await File(destination).readAsBytes();
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  static Future<void> restore({
    required String databasePath,
    required List<int> databaseBytes,
    required String settingsPath,
    List<int>? settingsBytes,
    required Future<void> Function() closeDatabase,
    required Future<void> Function() afterRestore,
  }) async {
    final databaseFile = File(databasePath);
    final settingsFile = File(settingsPath);
    final staging = await databaseFile.parent.createTemp('.hgm-restore-');
    final pending = File(path.join(staging.path, 'incoming.db'));
    final previousDatabase = File(path.join(staging.path, 'previous.db'));
    final previousSettings = File(path.join(staging.path, 'settings.json'));
    var databaseReplaced = false;
    var settingsReplaced = false;
    var keepRecoveryFiles = false;
    try {
      await pending.writeAsBytes(databaseBytes, flush: true);
      final candidate = await databaseFactory.openDatabase(pending.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      try {
        final integrity = await candidate.rawQuery('PRAGMA quick_check');
        if (integrity.length != 1 || integrity.single.values.single != 'ok') {
          throw const FormatException('备份数据库完整性校验失败');
        }
        final tables = await candidate
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
        final names = tables.map((row) => row['name']).toSet();
        if (!names.containsAll(
            ['games', 'tags', 'game_images', 'game_tag_relation'])) {
          throw const FormatException('所选文件不是游戏库备份');
        }
        final version = await candidate.getVersion();
        if (version > DatabaseHelper.schemaVersion) {
          throw const FormatException('备份来自更高版本，请先升级应用');
        }
      } finally {
        await candidate.close();
      }
      if (settingsBytes != null &&
          jsonDecode(utf8.decode(settingsBytes)) is! Map<String, dynamic>) {
        throw const FormatException('备份设置格式错误');
      }
      await closeDatabase();
      if (await databaseFile.exists()) {
        await databaseFile.rename(previousDatabase.path);
      }
      databaseReplaced = true;
      await pending.rename(databasePath);
      if (settingsBytes != null) {
        if (await settingsFile.exists()) {
          await settingsFile.rename(previousSettings.path);
        }
        settingsReplaced = true;
        await settingsFile.writeAsBytes(settingsBytes, flush: true);
      }
      await afterRestore();
    } catch (_) {
      if (databaseReplaced) {
        try {
          await closeDatabase();
          if (await databaseFile.exists()) await databaseFile.delete();
          if (await previousDatabase.exists()) {
            await previousDatabase.rename(databasePath);
          }
          if (settingsReplaced) {
            if (await settingsFile.exists()) await settingsFile.delete();
            if (await previousSettings.exists()) {
              await previousSettings.rename(settingsPath);
            }
          }
        } catch (error) {
          keepRecoveryFiles = true;
          throw FileSystemException('还原失败且回滚未完成，原文件保留在 ${staging.path}：$error');
        }
      }
      rethrow;
    } finally {
      if (!keepRecoveryFiles) await staging.delete(recursive: true);
    }
  }
}
