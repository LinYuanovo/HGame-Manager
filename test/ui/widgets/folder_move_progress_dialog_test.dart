import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/folder_move_progress.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/folder_move_progress_dialog.dart';

Future<BuildContext> _boot(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme(),
    home: const Scaffold(body: SizedBox()),
  ));
  return tester.element(find.byType(Scaffold));
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

const _result = FolderMoveResult(
  fileCount: 4,
  dirCount: 3,
  totalBytes: 4 << 20,
  elapsed: Duration(seconds: 2),
);

void main() {
  testWidgets('复制阶段展示百分比、已传大小与当前文件，完成后展示校验结果', (tester) async {
    final context = await _boot(tester);
    final completer = Completer<FolderMoveResult>();
    void Function(FolderMoveProgress)? emit;

    final future = runFolderMoveWithProgress(
      context: context,
      title: '移动游戏文件夹',
      task: (onProgress, shouldCancel) {
        emit = onProgress;
        return completer.future;
      },
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('正在扫描文件…'), findsOneWidget);
    expect(find.text('扫描中…'), findsOneWidget);

    emit!(const FolderMoveProgress(
      phase: FolderMovePhase.copying,
      filesDone: 1,
      filesTotal: 4,
      bytesDone: 1 << 20,
      bytesTotal: 4 << 20,
      currentFile: '大文件/movie_01.bin',
    ));
    await tester.pump();

    expect(find.text('正在复制到目标位置'), findsOneWidget);
    expect(find.text('25.0%'), findsOneWidget);
    expect(find.text('已传 1.0 MB / 4.0 MB'), findsOneWidget);
    expect(find.text('文件 1/4'), findsOneWidget);
    expect(find.text('大文件/movie_01.bin'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.25,
    );

    emit!(const FolderMoveProgress(
      phase: FolderMovePhase.verifying,
      filesDone: 4,
      filesTotal: 4,
      bytesDone: 4 << 20,
      bytesTotal: 4 << 20,
    ));
    await tester.pump();
    expect(find.text('正在校验文件完整性'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);

    completer.complete(_result);
    await tester.pump();
    await tester.pump();

    final successTexts = _texts(tester);
    expect(successTexts.any((t) => t.contains('共 4 个文件')), isTrue);
    expect(successTexts.any((t) => t.contains('校验通过')), isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect((await future).fileCount, 4);
  });

  testWidgets('点击取消后按钮禁用并展示已取消', (tester) async {
    final context = await _boot(tester);
    var cancelRequested = false;
    final completer = Completer<FolderMoveResult>();

    final future = runFolderMoveWithProgress(
      context: context,
      title: '移动游戏文件夹',
      task: (onProgress, shouldCancel) {
        onProgress(const FolderMoveProgress(
          phase: FolderMovePhase.copying,
          filesDone: 2,
          filesTotal: 10,
          bytesDone: 300 << 20,
          bytesTotal: 1024 << 20,
        ));
        return completer.future.then((_) {
          if (shouldCancel()) {
            cancelRequested = true;
            throw const FolderMoveCancelledException();
          }
          return _result;
        });
      },
    );
    final captured = expectLater(
      future,
      throwsA(isA<FolderMoveCancelledException>()),
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('29.3%'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('正在取消…'), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);

    completer.complete(_result);
    await tester.pump();
    await tester.pump();

    final cancelTexts = _texts(tester);
    expect(cancelRequested, isTrue);
    expect(cancelTexts.any((t) => t.contains('已取消')), isTrue);
    expect(cancelTexts.any((t) => t.contains('源目录未改动')), isTrue);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await captured;
  });

  testWidgets('失败时展示失败文件、已写入大小与残留清理告警', (tester) async {
    final context = await _boot(tester);
    final completer = Completer<FolderMoveResult>();

    final future = runFolderMoveWithProgress(
      context: context,
      title: '移动游戏文件夹',
      task: (onProgress, shouldCancel) => completer.future,
    );
    final captured = expectLater(
      future,
      throwsA(isA<FolderMoveException>()),
    );

    await tester.pump();
    await tester.pump();
    completer.completeError(
      const FolderMoveException(
        '复制文件失败：Cannot open file',
        relativePath: '大文件/movie_01.bin',
        bytesWritten: 0,
        expectedBytes: 734003200,
        cleanupWarning: r'目标残留清理失败，请手动删除 \\localhost\HGMRealTest\目标',
      ),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pump();

    final failTexts = _texts(tester);
    expect(failTexts.any((t) => t.contains('移动失败')), isTrue);
    expect(failTexts.any((t) => t.contains('大文件/movie_01.bin')), isTrue);
    expect(failTexts.any((t) => t.contains('已写入 0 B')), isTrue);
    expect(failTexts.any((t) => t.contains('源目录未改动')), isTrue);
    expect(failTexts.any((t) => t.contains('目标残留清理失败')), isTrue);
    expect(failTexts.any((t) => t.contains('已清理目标残留')), isFalse);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await captured;
  });

  testWidgets('文件已搬移但写库失败时不得声称源目录未改动', (tester) async {
    final context = await _boot(tester);
    final completer = Completer<FolderMoveResult>();

    final future = runFolderMoveWithProgress(
      context: context,
      title: '移动游戏文件夹',
      task: (onProgress, shouldCancel) => completer.future,
    );
    final captured = expectLater(
      future,
      throwsA(isA<FolderMoveException>()),
    );

    await tester.pump();
    await tester.pump();
    completer.completeError(
      const FolderMoveException(
        r'文件已移动到 \\localhost\HGMRealTest\目标，但数据库记录更新失败：UNIQUE constraint',
        filesMoved: true,
      ),
      StackTrace.current,
    );
    await tester.pump();
    await tester.pump();

    final texts = _texts(tester);
    expect(texts.any((t) => t.contains('记录未更新')), isTrue);
    expect(texts.any((t) => t.contains('数据库记录更新失败')), isTrue);
    expect(texts.any((t) => t.contains('请到游戏详情页核对路径')), isTrue);
    expect(texts.any((t) => t.contains('源目录未改动')), isFalse,
        reason: '文件已搬走，不能提示源目录未改动');

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await captured;
  });
}
