import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/app_logger.dart';
import 'package:hgame_manager/core/utils/app_paths.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/ui/pages/games/batch_import_dialog.dart';
import 'package:hgame_manager/ui/pages/games/games_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('重复导入：真实目录和 SQLite，45 个已有目录及混合导入', (tester) async {
    final dataRoot = await AppPaths.rootDir;
    expect(path.normalize(dataRoot).replaceAll('\\', '/'),
        contains('/build/windows/x64/runner/Debug/'));
    expect(await Directory(dataRoot).list().isEmpty, isTrue,
        reason: '验收仅使用独立工作树中空的 Debug 数据目录');
    final temporary =
        await Directory.systemTemp.createTemp('hgm_duplicate_native_');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = await AppSettings.loadFromFileForTest(
        path.join(temporary.path, 'settings.json'));
    final repo = GameRepository();
    final logger = AppLogger.instance;
    final pickerBefore = FilePickerPlatform.instance;
    final captureKey = GlobalKey();
    const evidence = String.fromEnvironment('ISSUE18_EVIDENCE');
    await logger.init();

    Future<void> capture(String name) async {
      if (evidence.isEmpty) return;
      final boundary = captureKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path.join(evidence, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    Future<void> waitForText(String text) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (find.text(text).evaluate().isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(text), findsWidgets);
    }

    Future<void> showBatch(List<String> folders, bool dark) async {
      await tester.pumpWidget(RepaintBoundary(
        key: captureKey,
        child: ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
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
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('batch-import-start')), findsOneWidget);
    }

    try {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1440, 1000));
      final folders = <String>[];
      final metadataBefore = <String, String>{};
      for (int index = 0; index < 70; index++) {
        final folder = path.join(temporary.path, 'library', 'Game$index');
        await GameDataPaths.ensureDataDir(folder);
        final metadata = jsonEncode({'title': '原标题 $index', 'intro': '原简介'});
        await GameDataPaths.metadataFile(folder).writeAsString(metadata);
        metadataBefore[folder] = metadata;
        folders.add(folder);
        final gameId = await repo.insertGame(Game(
          path: folder,
          title: '原标题 $index',
          rating: 4.5,
          isFavorite: true,
          playCount: 8,
          playDuration: 3600,
        ));
        final database = await DatabaseHelper.database;
        await database.insert('game_images', {
          'game_id': gameId,
          'image_path': path.join(folder, 'cover.png'),
          'sort_order': 0,
        });
      }
      final database = await DatabaseHelper.database;
      final before = await database.query('games', orderBy: 'id');
      final imagesBefore = await database.query('game_images', orderBy: 'id');
      final duplicateFolders = folders
          .take(45)
          .map((folder) => '${folder.replaceAll('\\', '/').toUpperCase()}/')
          .toList();

      for (final dark in [false, true]) {
        await showBatch(duplicateFolders, dark);
        await tester.tap(find.byKey(const ValueKey('batch-import-start')));
        await waitForText('导入完成: 成功 0 个，跳过 45 个，失败 0 个');
        await tester.pumpAndSettle();
        await capture('duplicate-45-${dark ? "dark" : "light"}');
        expect(await database.query('games', orderBy: 'id'), before);
        expect(
            await database.query('game_images', orderBy: 'id'), imagesBefore);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }

      final newFolder = path.join(temporary.path, 'new', 'NewGame');
      await GameDataPaths.ensureDataDir(newFolder);
      await GameDataPaths.metadataFile(newFolder)
          .writeAsString(jsonEncode({'title': '新游戏'}));
      await showBatch([folders.first, newFolder, '$newFolder\\.'], false);
      final dropdowns =
          find.byWidgetPredicate((widget) => widget is DropdownButton);
      final dropdownCount = dropdowns.evaluate().length;
      expect(dropdownCount, 3);
      for (int index = 0; index < dropdownCount; index++) {
        await tester.tap(dropdowns.at(index));
        await tester.pumpAndSettle();
        await tester.tap(find.text('不刮削').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('不刮削'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('batch-import-start')));
      await waitForText('导入完成: 成功 1 个，跳过 2 个，失败 0 个');
      expect(await database.query('games'), hasLength(71));
      expect((await repo.getGameByPath(newFolder))?.title, '新游戏');
      for (final entry in metadataBefore.entries) {
        expect(await GameDataPaths.metadataFile(entry.key).readAsString(),
            entry.value);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      FilePickerPlatform.instance = _DirectoryPicker(duplicateFolders.first);
      for (final source in ['不刮削', 'Steam', 'DLsite']) {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(settings),
            allGamesProvider.overrideWith((ref) async => <Game>[]),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: const Scaffold(body: GamesPage()),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('添加单个游戏'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(source));
        await tester.pumpAndSettle();
        await tester.tap(find.text('浏览'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(source == '不刮削' ? '导入' : '搜索'));
        await waitForText('该游戏已在库中，已跳过');
        expect(await database.query('games'), hasLength(71));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
      expect(await database.query('games', where: 'id <= 70', orderBy: 'id'),
          before);
      expect((await database.rawQuery('PRAGMA integrity_check')).single.values,
          ['ok']);
      expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      FilePickerPlatform.instance = pickerBefore;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await DatabaseHelper.close();
      await settings.flush();
      AppSettings.invalidateCache();
      await logger.flush();
      final resolved = path.normalize(path.absolute(temporary.path));
      if (!path.isWithin(
              path.normalize(path.absolute(Directory.systemTemp.path)),
              resolved) ||
          !path.basename(resolved).startsWith('hgm_duplicate_native_')) {
        throw StateError('临时目录超出验收范围');
      }
      final expectedRoot = path.join(
          File(Platform.resolvedExecutable).parent.path, 'hgame_manager_data');
      if (!path.equals(
          path.normalize(dataRoot), path.normalize(expectedRoot))) {
        throw StateError('数据目录超出验收范围');
      }
      await temporary.delete(recursive: true);
      await Directory(dataRoot).delete(recursive: true);
    }
  });
}

class _DirectoryPicker extends FilePickerPlatform {
  final String folder;

  _DirectoryPicker(this.folder);

  @override
  Future<String?> getDirectoryPath(
          {String? dialogTitle,
          bool lockParentWindow = false,
          String? initialDirectory}) async =>
      folder;
}
