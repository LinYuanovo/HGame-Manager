import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/app_data_migration_service.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hgm_app_data_migration_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('首次启动迁移旧 exe 目录的数据并保留备份', () async {
    final oldExeDir = Directory(path.join(tempDir.path, 'old'));
    final newExeDir = Directory(path.join(tempDir.path, 'new'));
    final oldRoot = Directory(path.join(oldExeDir.path, 'hgame_manager_data'));
    await oldRoot.create(recursive: true);
    final currentRoot =
        Directory(path.join(newExeDir.path, 'hgame_manager_data'));
    await currentRoot.create(recursive: true);
    await File(path.join(currentRoot.path, 'settings.json')).writeAsString(
      jsonEncode({'window_width': 1400}),
    );
    await File(path.join(oldRoot.path, 'settings.json')).writeAsString(
      jsonEncode({
        'library_path': jsonEncode([r'D:\Games'])
      }),
    );
    await File(path.join(oldRoot.path, 'hgame_manager.db'))
        .writeAsString('database');
    await Directory(path.join(oldRoot.path, 'game_images')).create();
    await File(path.join(oldRoot.path, 'game_images', 'cover.jpg'))
        .writeAsString('cover');

    final result = await AppDataMigrationService(
      currentExecutableDirectory: newExeDir.path,
      candidateExecutableDirectories: [oldExeDir.path],
    ).migrateIfNeeded();

    expect(result.migrated, isTrue);
    expect(
      await File(
              path.join(newExeDir.path, 'hgame_manager_data', 'settings.json'))
          .readAsString(),
      allOf(contains('library_path'), contains('window_width')),
    );
    expect(
      await File(path.join(
              newExeDir.path, 'hgame_manager_data', 'hgame_manager.db'))
          .readAsString(),
      'database',
    );
    expect(
      await File(path.join(
        newExeDir.path,
        'hgame_manager_data',
        'game_images',
        'cover.jpg',
      )).exists(),
      isTrue,
    );
    expect(result.backup, isNotNull);
    expect(await Directory(result.backup!).exists(), isTrue);
    expect(
      await File(path.join(
        newExeDir.path,
        'hgame_manager_data',
        AppDataMigrationService.markerFileName,
      )).exists(),
      isTrue,
    );

    final secondRun = await AppDataMigrationService(
      currentExecutableDirectory: newExeDir.path,
      candidateExecutableDirectories: [oldExeDir.path],
    ).migrateIfNeeded();
    expect(secondRun.migrated, isFalse);
  });
}
