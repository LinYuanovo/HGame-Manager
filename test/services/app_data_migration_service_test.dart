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

  for (final errorCode in [5, 1337]) {
    test('候选目录检测返回 $errorCode 时跳过该目录并迁移可访问的数据', () async {
      final inaccessibleExeDir = path.join(tempDir.path, 'inaccessible');
      final oldRoot = await _createOldRoot(path.join(tempDir.path, 'old'));
      final newExeDir = path.join(tempDir.path, 'new');
      final overrides = _DirectoryErrorOverrides(
        path.join(inaccessibleExeDir, 'hgame_manager_data'),
        errorCode: errorCode,
      );

      final result = await IOOverrides.runWithIOOverrides(
        () => AppDataMigrationService(
          currentExecutableDirectory: newExeDir,
          candidateExecutableDirectories: [
            inaccessibleExeDir,
            oldRoot.parent.path,
          ],
        ).migrateIfNeeded(),
        overrides,
      );

      expect(overrides.failureCount, greaterThan(0));
      expect(result.source, oldRoot.path);
      expect(
        await File(path.join(newExeDir, 'hgame_manager_data',
                'hgame_manager.db'))
            .readAsString(),
        'database',
      );
    });
  }

  test('候选数据目录递归枚举失败时继续选择其他可访问的数据', () async {
    final inaccessibleRoot =
        await _createOldRoot(path.join(tempDir.path, 'inaccessible'));
    final oldRoot = await _createOldRoot(path.join(tempDir.path, 'old'));
    final overrides = _DirectoryErrorOverrides(
      inaccessibleRoot.path,
      failOnList: true,
    );

    final result = await IOOverrides.runWithIOOverrides(
      () => AppDataMigrationService(
        currentExecutableDirectory: path.join(tempDir.path, 'new'),
        candidateExecutableDirectories: [
          inaccessibleRoot.parent.path,
          oldRoot.parent.path,
        ],
      ).migrateIfNeeded(),
      overrides,
    );

    expect(overrides.failureCount, greaterThan(0));
    expect(result.source, oldRoot.path);
  });

  test('自动发现遇到 WpSystem 候选权限异常时仍能迁移其他旧目录', () async {
    final scanRoot = path.join(tempDir.path, 'scan');
    final newExeDir = path.join(scanRoot, 'apps', 'current');
    final wpSystem = Directory(path.join(scanRoot, 'WpSystem'));
    await wpSystem.create(recursive: true);
    final oldRoot = await _createOldRoot(path.join(scanRoot, 'old'));
    final overrides = _DirectoryErrorOverrides(
      path.join(wpSystem.path, 'hgame_manager_data'),
    );

    final result = await IOOverrides.runWithIOOverrides(
      () => AppDataMigrationService(
        currentExecutableDirectory: newExeDir,
      ).migrateIfNeeded(),
      overrides,
    );

    expect(overrides.failureCount, greaterThan(0));
    expect(result.source, oldRoot.path);
  });

  test('父目录枚举失败后继续检查祖父目录中的旧数据', () async {
    final scanRoot = path.join(tempDir.path, 'scan');
    final newExeDir = path.join(scanRoot, 'apps', 'current');
    final oldRoot = await _createOldRoot(path.join(scanRoot, 'old'));
    final overrides = _DirectoryErrorOverrides(
      path.dirname(newExeDir),
      failOnList: true,
    );

    final result = await IOOverrides.runWithIOOverrides(
      () => AppDataMigrationService(
        currentExecutableDirectory: newExeDir,
      ).migrateIfNeeded(),
      overrides,
    );

    expect(overrides.failureCount, greaterThan(0));
    expect(result.source, oldRoot.path);
  });

  test('所有候选均不可访问时不写迁移标记，恢复访问后仍可重试', () async {
    final oldExeDir = path.join(tempDir.path, 'old');
    final newExeDir = path.join(tempDir.path, 'new');
    final service = AppDataMigrationService(
      currentExecutableDirectory: newExeDir,
      candidateExecutableDirectories: [oldExeDir],
    );
    final overrides = _DirectoryErrorOverrides(
      path.join(oldExeDir, 'hgame_manager_data'),
    );

    final result = await IOOverrides.runWithIOOverrides(
      service.migrateIfNeeded,
      overrides,
    );

    expect(overrides.failureCount, greaterThan(0));
    expect(result.migrated, isFalse);
    expect(
      await File(path.join(newExeDir, 'hgame_manager_data',
              AppDataMigrationService.markerFileName))
          .exists(),
      isFalse,
    );

    final oldRoot = await _createOldRoot(oldExeDir);
    final retry = await service.migrateIfNeeded();
    expect(retry.source, oldRoot.path);
  });
}

Future<Directory> _createOldRoot(String exeDir) async {
  final root = Directory(path.join(exeDir, 'hgame_manager_data'));
  await root.create(recursive: true);
  await File(path.join(root.path, 'hgame_manager.db')).writeAsString('database');
  return root;
}

// 通过覆盖指定临时目录的访问操作模拟 Windows 文件系统错误。
final class _DirectoryErrorOverrides extends IOOverrides {
  final String targetPath;
  final int errorCode;
  final bool failOnList;
  int failureCount = 0;

  _DirectoryErrorOverrides(
    this.targetPath, {
    this.errorCode = 1337,
    this.failOnList = false,
  });

  @override
  Directory createDirectory(String value) {
    final directory = super.createDirectory(value);
    if (path.normalize(value) != path.normalize(targetPath)) return directory;
    return _ErrorDirectory(directory, this);
  }

  FileSystemException failure(String operation) {
    failureCount++;
    return FileSystemException(
      operation,
      targetPath,
      OSError(errorCode == 1337 ? '安全 ID 结构无效' : '拒绝访问', errorCode),
    );
  }
}

class _ErrorDirectory implements Directory {
  final Directory directory;
  final _DirectoryErrorOverrides overrides;

  _ErrorDirectory(this.directory, this.overrides);

  @override
  String get path => directory.path;

  @override
  Directory get parent => directory.parent;

  @override
  Future<bool> exists() async {
    if (!overrides.failOnList) throw overrides.failure('目录存在性检查失败');
    return directory.exists();
  }

  @override
  Future<Directory> create({bool recursive = false}) =>
      directory.create(recursive: recursive);

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    if (overrides.failOnList) throw overrides.failure('目录枚举失败');
    yield* directory.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
