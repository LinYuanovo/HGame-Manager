import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/drop_import_utils.dart';
import 'package:path/path.dart' as path;

void main() {
  group('DropImportUtils.resolveDroppedPaths', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('hgm_drop_import_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// 辅助：在临时目录下创建游戏目录
    Directory createGameDir(String name) {
      final dir = Directory(path.join(tempDir.path, name));
      dir.createSync(recursive: true);
      return dir;
    }

    /// 辅助：在指定目录下创建文件
    File createFile(Directory dir, String fileName) {
      final file = File(path.join(dir.path, fileName));
      file.createSync(recursive: true);
      return file;
    }

    test('单个目录：仅产生游戏目录，无预设关键词', () {
      final dir = createGameDir('GameA');

      final result = DropImportUtils.resolveDroppedPaths([dir.path]);

      expect(result.folderPaths, [DropImportUtils.normalizeDropPath(dir.path)]);
      expect(result.presetKeywords, isEmpty);
    });

    test('单个 exe：父目录入库，关键词去扩展名且下划线转空格', () {
      final dir = createGameDir('My_Game');
      final exe = createFile(dir, 'Start_Game.exe');

      final result = DropImportUtils.resolveDroppedPaths([exe.path]);

      final expectedDir = DropImportUtils.normalizeDropPath(dir.path);
      expect(result.folderPaths, [expectedDir]);
      expect(result.presetKeywords[expectedDir], 'Start Game');
    });

    test('混合输入：目录 + exe + 非 exe 文件，txt 被忽略', () {
      final dirA = createGameDir('GameA');
      final dirB = createGameDir('GameB');
      final exe = createFile(dirB, 'Run.exe');
      final txt = createFile(tempDir, 'readme.txt');

      final result = DropImportUtils.resolveDroppedPaths([
        dirA.path,
        exe.path,
        txt.path,
      ]);

      final expectedA = DropImportUtils.normalizeDropPath(dirA.path);
      final expectedB = DropImportUtils.normalizeDropPath(dirB.path);
      // 保持首次出现顺序，txt 不产生任何条目
      expect(result.folderPaths, [expectedA, expectedB]);
      expect(result.presetKeywords.length, 1);
      expect(result.presetKeywords[expectedB], 'Run');
      expect(result.presetKeywords.containsKey(expectedA), isFalse);
    });

    test('重复路径去重：末尾分隔符、斜杠、大小写差异均视为同一目录', () {
      final dir = createGameDir('GameA');

      final result = DropImportUtils.resolveDroppedPaths([
        dir.path,
        '${dir.path}\\',
        dir.path.replaceAll('\\', '/'),
        dir.path.toUpperCase(),
      ]);

      expect(result.folderPaths, [DropImportUtils.normalizeDropPath(dir.path)]);
      expect(result.presetKeywords, isEmpty);
    });

    test('文件夹与其内部 exe 同时拖入：去重为一项且 exe 关键词存在', () {
      final dir = createGameDir('GameA');
      final exe = createFile(dir, 'Start_Game.exe');

      // 文件夹在前、exe 在后
      final result = DropImportUtils.resolveDroppedPaths([dir.path, exe.path]);

      final expected = DropImportUtils.normalizeDropPath(dir.path);
      expect(result.folderPaths, [expected]);
      expect(result.presetKeywords[expected], 'Start Game');
    });

    test('同一目录两个 exe：目录一项，关键词取第一个 exe', () {
      final dir = createGameDir('GameA');
      final exe1 = createFile(dir, 'First_Game.exe');
      final exe2 = createFile(dir, 'Second_Game.exe');

      final result = DropImportUtils.resolveDroppedPaths([exe1.path, exe2.path]);

      final expected = DropImportUtils.normalizeDropPath(dir.path);
      expect(result.folderPaths, [expected]);
      expect(result.presetKeywords.length, 1);
      expect(result.presetKeywords[expected], 'First Game');
    });

    test('不存在的路径被忽略', () {
      final missing = path.join(tempDir.path, 'not_exist', 'Game.exe');
      final missingDir = path.join(tempDir.path, 'not_exist_dir');

      final result = DropImportUtils.resolveDroppedPaths([missing, missingDir]);

      expect(result.folderPaths, isEmpty);
      expect(result.presetKeywords, isEmpty);
    });

    test('空输入返回空结果', () {
      final result = DropImportUtils.resolveDroppedPaths(const []);

      expect(result.folderPaths, isEmpty);
      expect(result.presetKeywords, isEmpty);
    });

    test('大写扩展名 .EXE 正确识别', () {
      final dir = createGameDir('GameA');
      final exe = createFile(dir, 'Big_Game.EXE');

      final result = DropImportUtils.resolveDroppedPaths([exe.path]);

      final expected = DropImportUtils.normalizeDropPath(dir.path);
      expect(result.folderPaths, [expected]);
      expect(result.presetKeywords[expected], 'Big Game');
    });
  });
}
