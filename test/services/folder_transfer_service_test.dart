import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/folder_move_progress.dart';
import 'package:hgame_manager/core/services/folder_transfer_service.dart';
import 'package:path/path.dart' as path;

Future<Directory> _createSampleSource(Directory root) async {
  final source = Directory(path.join(root.path, 'source'));
  await Directory(path.join(source.path, 'sub')).create(recursive: true);
  await Directory(path.join(source.path, 'empty')).create(recursive: true);
  await File(path.join(source.path, 'a.txt')).writeAsString('hello');
  final bytes = List<int>.generate(1500000, (index) => index % 251);
  await File(path.join(source.path, 'sub', 'b.bin')).writeAsBytes(bytes);
  return source;
}

Future<void> _expectSampleSourceIntact(Directory source) async {
  expect(await File(path.join(source.path, 'a.txt')).readAsString(), 'hello');
  expect(await File(path.join(source.path, 'sub', 'b.bin')).length(), 1500000);
  expect(await Directory(path.join(source.path, 'empty')).exists(), isTrue);
}

void main() {
  group('FolderTransferService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hgm_transfer_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('同一卷移动保留目录结构与文件内容', () async {
      final source = await _createSampleSource(tempDir);
      final expectedBytes =
          await File(path.join(source.path, 'sub', 'b.bin')).readAsBytes();
      final target = Directory(path.join(tempDir.path, 'moved'));

      final result = await FolderTransferService().moveDirectory(
        source: source,
        target: target,
      );

      expect(await source.exists(), isFalse);
      expect(await target.exists(), isTrue);
      expect(result.fileCount, 2);
      expect(result.dirCount, 2);
      expect(result.totalBytes, expectedBytes.length + 'hello'.length);
      expect(
          await File(path.join(target.path, 'a.txt')).readAsString(), 'hello');
      expect(
        await File(path.join(target.path, 'sub', 'b.bin')).readAsBytes(),
        expectedBytes,
      );
      expect(await Directory(path.join(target.path, 'empty')).exists(), isTrue);
    });

    test('强制复制模式下进度单调且阶段有序', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'copied'));
      final events = <FolderMoveProgress>[];

      final result = await FolderTransferService(forceCopy: true).moveDirectory(
        source: source,
        target: target,
        onProgress: events.add,
      );

      expect(events, isNotEmpty);
      final phases = events.map((event) => event.phase).toList();
      expect(phases.first, FolderMovePhase.scanning);
      expect(phases.last, FolderMovePhase.done);
      expect(phases.indexOf(FolderMovePhase.copying),
          greaterThan(phases.indexOf(FolderMovePhase.scanning)));
      expect(phases.indexOf(FolderMovePhase.verifying),
          greaterThan(phases.indexOf(FolderMovePhase.copying)));
      expect(phases.indexOf(FolderMovePhase.cleaning),
          greaterThan(phases.indexOf(FolderMovePhase.verifying)));
      expect(phases.indexOf(FolderMovePhase.done),
          greaterThan(phases.indexOf(FolderMovePhase.cleaning)));

      var lastBytesDone = -1;
      var lastFilesDone = -1;
      for (final event in events) {
        expect(event.bytesDone, greaterThanOrEqualTo(lastBytesDone));
        expect(event.filesDone, greaterThanOrEqualTo(lastFilesDone));
        lastBytesDone = event.bytesDone;
        lastFilesDone = event.filesDone;
        if (event.currentFile != null) {
          expect(event.currentFile, isNot(contains(r'\')));
        }
      }

      final lastEvent = events.last;
      expect(lastEvent.bytesTotal, greaterThan(0));
      expect(lastEvent.bytesDone, lastEvent.bytesTotal);
      expect(result.fileCount, 2);
      expect(result.dirCount, 2);
      expect(result.totalBytes, lastEvent.bytesTotal);
      expect(await source.exists(), isFalse);
      expect(await target.exists(), isTrue);
    });

    test('校验失败时清理目标目录且保留源目录', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'broken'));
      final service = FolderTransferService(
        forceCopy: true,
        retryDelays: const [],
        onAfterCopy: (directory) async {
          await File(path.join(directory.path, 'a.txt')).writeAsBytes(const []);
        },
      );

      Object? error;
      try {
        await service.moveDirectory(source: source, target: target);
      } catch (e) {
        error = e;
      }

      expect(error, isA<FolderMoveException>());
      expect((error as FolderMoveException).relativePath, contains('a.txt'));
      expect(await target.exists(), isFalse);
      expect(await source.exists(), isTrue);
      await _expectSampleSourceIntact(source);
    });

    test('目标残留清理失败时异常携带残留路径提示', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'locked'));
      RandomAccessFile? hold;
      final service = FolderTransferService(
        forceCopy: true,
        retryDelays: const [],
        onAfterCopy: (directory) async {
          hold = await File(path.join(directory.path, 'a.txt')).open(
            mode: FileMode.append,
          );
          await File(path.join(directory.path, 'a.txt')).writeAsBytes(
            const [],
          );
        },
      );

      Object? error;
      try {
        await service.moveDirectory(source: source, target: target);
      } catch (e) {
        error = e;
      } finally {
        await hold?.close();
      }

      if (error is FolderMoveException && error.cleanupWarning != null) {
        expect(error.cleanupWarning, contains('请手动删除'));
        expect(error.toString(), contains(target.path));
        expect(await target.exists(), isTrue);
        await target.delete(recursive: true);
      } else {
        expect(await target.exists(), isFalse);
      }
      expect(error, isA<FolderMoveException>());
      expect((error as FolderMoveException).relativePath, contains('a.txt'));
      expect(await source.exists(), isTrue);
      await _expectSampleSourceIntact(source);
    });

    test('取消复制时清理目标目录且保留源目录', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'cancelled'));
      var completedFiles = 0;

      Object? error;
      try {
        await FolderTransferService(forceCopy: true).moveDirectory(
          source: source,
          target: target,
          onProgress: (progress) {
            if (progress.phase == FolderMovePhase.copying &&
                progress.filesDone >= 1) {
              completedFiles = progress.filesDone;
            }
          },
          shouldCancel: () => completedFiles >= 1,
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<FolderMoveCancelledException>());
      expect(await target.exists(), isFalse);
      expect(await source.exists(), isTrue);
      await _expectSampleSourceIntact(source);
    });

    test('中文与长文件名按字节复制', () async {
      final source = Directory(path.join(tempDir.path, 'cn_source'));
      final nested = Directory(path.join(source.path, '测试游戏', '中文名（v1.0）'));
      await nested.create(recursive: true);
      final bytes = List<int>.generate(4096, (index) => index % 251);
      const fileName = '场景 ①②③.bin';
      await File(path.join(nested.path, fileName)).writeAsBytes(bytes);
      final target = Directory(path.join(tempDir.path, 'cn_target'));

      await FolderTransferService(forceCopy: true).moveDirectory(
        source: source,
        target: target,
      );

      final copied = File(
        path.join(target.path, '测试游戏', '中文名（v1.0）', fileName),
      );
      expect(await copied.readAsBytes(), bytes);
      expect(await source.exists(), isFalse);
    });

    test('空目录移动不报错且文件数为零', () async {
      final source = Directory(path.join(tempDir.path, 'empty_source'));
      await source.create(recursive: true);
      final target = Directory(path.join(tempDir.path, 'empty_target'));

      final result = await FolderTransferService(forceCopy: true).moveDirectory(
        source: source,
        target: target,
      );

      expect(result.fileCount, 0);
      expect(result.dirCount, 0);
      expect(result.totalBytes, 0);
      expect(await target.exists(), isTrue);
      expect(await source.exists(), isFalse);
    });

    test('目标位于源目录内部时拒绝移动且不删除任何文件', () async {
      final source = await _createSampleSource(tempDir);
      final nestedTarget = Directory(path.join(source.path, 'moved'));

      Object? error;
      try {
        await FolderTransferService(forceCopy: true).moveDirectory(
          source: source,
          target: nestedTarget,
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<FolderMoveException>());
      expect(await source.exists(), isTrue);
      await _expectSampleSourceIntact(source);
      expect(await nestedTarget.exists(), isFalse);
    });

    test('含符号链接的目录被拒绝且不创建目标', () async {
      final source = Directory(path.join(tempDir.path, 'linked_source'));
      await source.create(recursive: true);
      final file = File(path.join(source.path, 'a.txt'));
      await file.writeAsString('a');
      final linkPath = path.join(source.path, 'link.txt');
      try {
        await Link(linkPath).create(file.path);
      } catch (e) {
        debugPrint('跳过符号链接测试：当前环境无法创建链接（$e）');
        return;
      }
      final target = Directory(path.join(tempDir.path, 'linked_target'));

      Object? error;
      try {
        await FolderTransferService(forceCopy: true).moveDirectory(
          source: source,
          target: target,
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<FolderMoveException>());
      expect((error as FolderMoveException).message, contains('符号链接'));
      expect(await target.exists(), isFalse);
    });

    test('commit 在删除源目录之前调用且此时两份目录都在', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'commit_order'));
      var called = false;
      bool? sourceExisted;
      bool? targetExisted;

      final result = await FolderTransferService(forceCopy: true).moveDirectory(
        source: source,
        target: target,
        commit: () async {
          called = true;
          sourceExisted = await source.exists();
          targetExisted = await target.exists();
        },
      );

      expect(called, isTrue);
      expect(sourceExisted, isTrue, reason: '写库时源目录必须还在');
      expect(targetExisted, isTrue, reason: '写库时目标已完整校验');
      expect(result.fileCount, greaterThan(0));
      expect(await source.exists(), isFalse);
    });

    test('跨卷 commit 失败时清理目标并保留源目录', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'commit_fail'));

      Object? error;
      try {
        await FolderTransferService(forceCopy: true).moveDirectory(
          source: source,
          target: target,
          commit: () async {
            throw StateError('数据库记录更新失败');
          },
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<StateError>());
      expect(await target.exists(), isFalse, reason: '目标副本必须清理');
      expect(await source.exists(), isTrue);
      await _expectSampleSourceIntact(source);
    });

    test('同卷 commit 失败时把目录名还原', () async {
      final source = await _createSampleSource(tempDir);
      final target = Directory(path.join(tempDir.path, 'commit_fail_rename'));

      Object? error;
      try {
        await FolderTransferService().moveDirectory(
          source: source,
          target: target,
          commit: () async {
            throw StateError('数据库记录更新失败');
          },
        );
      } catch (e) {
        error = e;
      }

      expect(error, isA<StateError>());
      expect(await source.exists(), isTrue, reason: '同卷应改回原名');
      expect(await target.exists(), isFalse);
      await _expectSampleSourceIntact(source);
    });
  });
}
