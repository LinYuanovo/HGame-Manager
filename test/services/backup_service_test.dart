import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/backup_service.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:path/path.dart' as path;

void main() {
  group('BackupService', () {
    late Directory tempDir;
    late BackupService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hgm_backup_test_');
      service = BackupService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('uses HGMDatas backup directory', () {
      expect(
        service.getBackupDir(tempDir.path).path,
        path.join(tempDir.path, 'HGMDatas', 'backup'),
      );
    });

    test('migrates old HGMBackup before listing backups', () async {
      final oldDir = await Directory(path.join(tempDir.path, 'HGMBackup'))
          .create(recursive: true);
      await File(path.join(oldDir.path, '2026-01-01 12-00.zip'))
          .writeAsBytes([1, 2, 3]);

      final entries = await service.listBackups(tempDir.path);

      expect(entries, hasLength(1));
      expect(entries.single.fileName, '2026-01-01 12-00.zip');
      expect(await Directory(path.join(tempDir.path, 'HGMBackup')).exists(),
          isFalse);
      expect(
        await File(path.join(
          GameDataPaths.backupDir(tempDir.path).path,
          '2026-01-01 12-00.zip',
        )).exists(),
        isTrue,
      );
    });
  });
}
