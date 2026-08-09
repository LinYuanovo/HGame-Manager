import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  test('使用游戏记录中的 Backup 路径，不依赖当前通关目录配置', () async {
    final tempDir = await Directory.systemTemp.createTemp('hgm_backup_path_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final backupPath = path.join(tempDir.path, '旧通关目录', 'Backup', 'Example');
    await Directory(backupPath).create(recursive: true);

    final game = Game(
      id: 1,
      path: path.join(tempDir.path, '原游戏库', 'Example'),
      title: 'Example',
      isCleared: true,
      clearedBackupPath: backupPath,
    );

    expect(await GameRepository().findBackupPathForGame(game), backupPath);
  });
}
