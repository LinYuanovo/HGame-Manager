import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/utils/game_path_utils.dart';
import 'package:hgame_manager/ui/pages/games/batch_import_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Future<void> showImport(WidgetTester tester, _ImportRepository repo,
      List<String> folders, bool dark) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [gameRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
        home: Scaffold(
          body: BatchImportDialog(
            onImportComplete: () {},
            userFont: '',
            initialFolderPaths: folders,
            presetKeywords: {for (final folder in folders) folder: '测试游戏'},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}重复导入 45 个已入库目录，全部跳过且不启动逐项处理',
        (tester) async {
      final folders = [
        for (int index = 0; index < 45; index++) 'C:/Library/Game$index/',
      ];
      final repo = _ImportRepository({
        for (int index = 0; index < 45; index++)
          GamePathUtils.comparisonKey(folders[index]): index + 1,
      });
      await showImport(tester, repo, folders, dark);
      await tester.tap(find.byKey(const ValueKey('batch-import-start')));
      await tester.pumpAndSettle();
      expect(find.text('导入完成: 成功 0 个，跳过 45 个，失败 0 个'), findsOneWidget);
      expect(repo.lookups, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('本批路径去重且写入前被其他任务添加的目录计为跳过', (tester) async {
    final repo = _ImportRepository({})..existsBeforeWrite = true;
    await showImport(
        tester,
        repo,
        [r'C:\Library\Example', 'c:/library/example/', r'C:\Library\Example\.'],
        false);
    await tester.tap(find.byKey(const ValueKey('batch-import-start')));
    await tester.pumpAndSettle();
    expect(find.text('导入完成: 成功 0 个，跳过 3 个，失败 0 个'), findsOneWidget);
    expect(repo.lookups, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一项检查失败仍处理其余目录，并恢复可确认的完成状态', (tester) async {
    final repo = _ImportRepository({})
      ..existsBeforeWrite = true
      ..failingPath = r'C:\Library\Broken';
    await showImport(
        tester, repo, [r'C:\Library\Broken', r'C:\Library\Existing'], false);
    final dropdowns = find.byWidgetPredicate((widget) => widget is DropdownButton);
    for (var index = 0; index < dropdowns.evaluate().length; index++) {
      await tester.tap(dropdowns.at(index));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不刮削').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('batch-import-start')));
    await tester.pumpAndSettle();
    expect(find.text('导入完成: 成功 0 个，跳过 1 个，失败 1 个'), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-import-finish')), findsOneWidget);
    expect(repo.lookups, 2);
    expect(tester.takeException(), isNull);
  });
}

class _ImportRepository extends GameRepository {
  final Map<String, int> existingPaths;
  bool existsBeforeWrite = false;
  String? failingPath;
  int lookups = 0;

  _ImportRepository(this.existingPaths);

  @override
  Future<Map<String, int>> getGameIdsByPathKey(
          {DatabaseExecutor? executor}) async =>
      existingPaths;

  @override
  Future<Game?> getStoredGameByPath(String path) async {
    lookups++;
    if (path == failingPath) throw StateError('测试目录不可读取');
    return existsBeforeWrite ? Game(id: 1, path: path) : null;
  }
}
