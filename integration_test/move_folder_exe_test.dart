import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/folder_move_progress.dart';
import 'package:hgame_manager/core/services/game_move_service.dart';
import 'package:hgame_manager/main.dart' as app;
import 'package:hgame_manager/ui/pages/home_page.dart';
import 'package:hgame_manager/ui/widgets/folder_move_progress_dialog.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

const String smbTargetRoot = String.fromEnvironment(
  'HGM_EXE_TEST_TARGET',
  defaultValue: r'\\localhost\HGMRealTest\exe移动目标',
);

bool _appStarted = false;

Future<void> _ensureApp(WidgetTester tester) async {
  if (_appStarted && find.byType(HomePage).evaluate().isNotEmpty) {
    return;
  }
  app.main([]);
  _appStarted = true;
  final ready = await _pumpUntil(
    tester,
    find.byType(HomePage),
    const Duration(seconds: 90),
  );
  if (!ready) {
    throw StateError('应用首页未在 90 秒内就绪');
  }
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return finder.evaluate().isNotEmpty;
}

List<String> _snapshotTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

Future<Directory> _makeSource(String root, String name) async {
  final source = Directory(path.join(root, name));
  await source.create(recursive: true);
  await Directory(path.join(source.path, '大文件')).create(recursive: true);
  await File(path.join(source.path, 'readme.txt')).writeAsString('readme');
  final exeSink =
      await File(path.join(source.path, 'game.exe')).open(mode: FileMode.write);
  final chunk = List<int>.generate(1 << 20, (i) => i % 251);
  for (var i = 0; i < 3; i++) {
    await exeSink.writeFrom(chunk);
  }
  await exeSink.flush();
  await exeSink.close();
  final binSink = await File(path.join(source.path, '大文件', 'movie_01.bin'))
      .open(mode: FileMode.write);
  for (var i = 0; i < 48; i++) {
    await binSink.writeFrom(chunk);
  }
  await binSink.flush();
  await binSink.close();
  return source;
}

Future<Map<String, String>> _hashes(Directory dir) async {
  final result = <String, String>{};
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File) {
      final digest = sha256.convert(await entity.readAsBytes());
      result[path.relative(entity.path, from: dir.path)] = digest.toString();
    }
  }
  return result;
}

Future<void> _waitResult(WidgetTester tester, Duration timeout) async {
  final ok = await _pumpUntil(tester, find.text('移动完成'), timeout);
  expect(ok, isTrue, reason: 'exe 内应出现成功结果页');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实 exe：跨卷移动到 SMB 网络盘并更新数据库', (tester) async {
    await _ensureApp(tester);

    final workRoot = Directory(path.join(Directory.systemTemp.path,
        'hgm_exe_test_${DateTime.now().millisecondsSinceEpoch}'));
    await workRoot.create(recursive: true);
    final source = await _makeSource(workRoot.path, '源文件夹');
    final sourceHashes = await _hashes(source);
    final target = Directory(path.join(
        smbTargetRoot, '目标文件夹_${DateTime.now().millisecondsSinceEpoch}'));
    if (await target.exists()) {
      await target.delete(recursive: true);
    }

    final repo = GameRepository();
    final gameId = await repo.insertGame(Game(
      path: source.path,
      title: '真实EXE测试游戏',
      intro: '路径引用: ${source.path}\\readme.txt',
      gameLauncher: path.join(source.path, 'game.exe'),
      savePath: path.join(source.path, 'save'),
    ));

    final progressEvents = <FolderMoveProgress>[];
    final dialogFuture = runFolderMoveWithProgress(
      context: tester.element(find.byType(HomePage)),
      title: '移动游戏文件夹',
      task: (onProgress, shouldCancel) =>
          GameMoveService(gameRepository: repo).moveGameFolderCrossDrive(
        gameId: gameId,
        oldPath: source.path,
        newPath: target.path,
        onProgress: (progress) {
          progressEvents.add(progress);
          onProgress(progress);
        },
        shouldCancel: shouldCancel,
      ),
    );

    await _waitResult(tester, const Duration(minutes: 3));
    final successTexts = _snapshotTexts(tester);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    final result = await dialogFuture;

    final refreshed = await repo.getGameById(gameId);
    final dbPath = refreshed!.path;
    final dbLauncher = refreshed.gameLauncher;
    final dbSavePath = refreshed.savePath;
    final dbIntro = refreshed.intro;
    final sourceExists = await source.exists();
    final targetHashes = await _hashes(target);

    // ignore: avoid_print
    print('EXE成功页: $successTexts');
    // ignore: avoid_print
    print('EXE进度事件: ${progressEvents.length}, 阶段: '
        '${progressEvents.map((e) => e.phase.name).toSet()}, '
        '文件数: ${result.fileCount}, 字节: ${result.totalBytes}, '
        '耗时: ${result.elapsed.inMilliseconds}ms');

    expect(successTexts.any((t) => t.contains('共 3 个文件')), isTrue);
    expect(successTexts.any((t) => t.contains('校验通过')), isTrue);
    expect(result.fileCount, 3);
    expect(result.totalBytes, 53477382);
    expect(
      progressEvents.map((e) => e.phase).toSet(),
      containsAll(<FolderMovePhase>[
        FolderMovePhase.copying,
        FolderMovePhase.verifying,
      ]),
      reason: '进度事件必须覆盖复制与校验阶段',
    );
    expect(progressEvents.last.fraction, 1.0);
    expect(dbPath, target.path, reason: '数据库路径必须更新');
    expect(dbLauncher, path.join(target.path, 'game.exe'));
    expect(dbSavePath, path.join(target.path, 'save'));
    expect(dbIntro, contains(target.path));
    expect(sourceExists, isFalse, reason: '源目录应已删除');
    expect(targetHashes, sourceHashes, reason: '目标内容必须与源一致');

    await target.delete(recursive: true);
    await workRoot.delete(recursive: true);
  });

  testWidgets('真实 exe：复制中点击取消 → 源保留、目标清理、库不变', (tester) async {
    await _ensureApp(tester);

    final workRoot = Directory(path.join(Directory.systemTemp.path,
        'hgm_exe_cancel_${DateTime.now().millisecondsSinceEpoch}'));
    await workRoot.create(recursive: true);
    final source = Directory(path.join(workRoot.path, '取消源'));
    await source.create(recursive: true);
    final bigFile = File(path.join(source.path, 'movie.bin'));
    final sink = await bigFile.open(mode: FileMode.write);
    final chunk = List<int>.filled(1 << 20, 7);
    for (var i = 0; i < 600; i++) {
      await sink.writeFrom(chunk);
    }
    await sink.flush();
    await sink.close();

    final target = Directory(path.join(
        smbTargetRoot, '取消目标_${DateTime.now().millisecondsSinceEpoch}'));
    if (await target.exists()) {
      await target.delete(recursive: true);
    }

    final repo = GameRepository();
    final gameId = await repo.insertGame(Game(
      path: source.path,
      title: '真实EXE取消测试',
    ));

    Object? error;
    final dialogFuture = runFolderMoveWithProgress(
      context: tester.element(find.byType(HomePage)),
      title: '移动游戏文件夹',
      task: (onProgress, shouldCancel) async {
        try {
          return await GameMoveService(gameRepository: repo)
              .moveGameFolderCrossDrive(
            gameId: gameId,
            oldPath: source.path,
            newPath: target.path,
            onProgress: onProgress,
            shouldCancel: shouldCancel,
          );
        } catch (e) {
          error = e;
          rethrow;
        }
      },
    );
    final captured = expectLater(
      dialogFuture,
      throwsA(isA<FolderMoveCancelledException>()),
    );

    var tappedCancel = false;
    var sawCancelling = false;
    final end = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('已取消').evaluate().isNotEmpty ||
          find.text('移动失败').evaluate().isNotEmpty ||
          find.text('移动完成').evaluate().isNotEmpty) {
        break;
      }
      if (!tappedCancel &&
          find.text('正在复制到目标位置').evaluate().isNotEmpty &&
          find.text('取消').evaluate().isNotEmpty) {
        await tester.tap(find.text('取消'));
        tappedCancel = true;
        await tester.pump();
        sawCancelling = find.text('正在取消…').evaluate().isNotEmpty;
      }
    }

    final cancelTexts = _snapshotTexts(tester);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await captured;

    final refreshed = await repo.getGameById(gameId);
    final dbPath = refreshed!.path;
    final sourceExists = await source.exists();
    final sourceLength = await bigFile.length();
    final targetExists = await target.exists();

    // ignore: avoid_print
    print('EXE取消页: $cancelTexts; 取消异常: $error; '
        '源存在: $sourceExists, 源大小: $sourceLength, 目标残留: $targetExists');

    expect(tappedCancel, isTrue, reason: '应在复制阶段点到取消');
    expect(sawCancelling, isTrue, reason: '取消后按钮应立即变为正在取消…');
    expect(cancelTexts.any((t) => t.contains('已取消')), isTrue);
    expect(cancelTexts.any((t) => t.contains('源目录未改动')), isTrue);
    expect(error, isA<FolderMoveCancelledException>());
    expect(dbPath, source.path, reason: '取消后数据库路径不得改变');
    expect(sourceExists, isTrue, reason: '取消后源目录必须保留');
    expect(sourceLength, 600 << 20);
    expect(targetExists, isFalse, reason: '取消后目标残留必须清理');

    await workRoot.delete(recursive: true);
  });
}
