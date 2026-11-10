import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/app_logger.dart';
import 'package:hgame_manager/core/utils/app_paths.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/app_router.dart';
import 'package:hgame_manager/ui/pages/categories/cleared_games_page.dart';
import 'package:hgame_manager/ui/pages/categories/categories_page.dart';
import 'package:hgame_manager/ui/pages/categories/tag_games_page.dart';
import 'package:hgame_manager/ui/pages/games/game_detail_page.dart';
import 'package:hgame_manager/ui/pages/games/guide_search_dialog.dart';
import 'package:hgame_manager/ui/pages/games/save_management_dialog.dart';
import 'package:hgame_manager/ui/pages/home_page.dart';
import 'package:hgame_manager/ui/pages/favorites/favorites_page.dart';
import 'package:hgame_manager/ui/pages/settings/context_menu_manager_dialog.dart';
import 'package:hgame_manager/ui/pages/settings/guide_hotkey_dialog.dart';
import 'package:hgame_manager/ui/pages/settings/metadata_translation_dialog.dart';
import 'package:hgame_manager/ui/pages/settings/rename_manager_dialog.dart';
import 'package:hgame_manager/ui/pages/settings/scrape_mode_config_dialog.dart';
import 'package:hgame_manager/ui/pages/settings/settings_page.dart';
import 'package:hgame_manager/ui/pages/settings/sidebar_manager_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/image_manager_dialog.dart';
import 'package:hgame_manager/ui/widgets/game_list_widget.dart';
import 'package:hgame_manager/ui/widgets/markdown_editor.dart';
import 'package:hgame_manager/ui/windows/guide_window.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('主题与动效：浅深色逐页、加载状态及共享弹窗', (tester) async {
    final dataRoot = await AppPaths.rootDir;
    expect(path.normalize(dataRoot).replaceAll('\\', '/'),
        contains('/build/windows/x64/runner/Debug/'));
    expect(await Directory(dataRoot).list().isEmpty, isTrue,
        reason: '必须使用空的构建数据目录');
    final settings = await AppSettings.loadFromFileForTest(
        path.join(dataRoot, 'settings.json'));
    await settings.setBool('guide_window_hotkeys_enabled', false);
    await settings.setBool('auto_update_enabled', false);
    await settings.setString(
        'library_path', jsonEncode([path.join(dataRoot, 'games')]));
    await settings.setString('game_list_view_mode', 'poster');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final repo = GameRepository();
    final tags = TagRepository();
    final tagId = await tags.insertOrGetTag('冒险', Tag.typeCustom);
    await tags.toggleFavorite(tagId, true);
    final seriesId = await tags.insertOrGetTag('RPG', Tag.typeSeries);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 480, 270),
        Paint()
          ..shader = AppTheme.primaryGradient
              .createShader(const Rect.fromLTWH(0, 0, 480, 270)));
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 270);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final cover = File(path.join(dataRoot, 'cover.png'));
    await cover.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    Game? selected;
    for (var index = 0; index < 4; index++) {
      final directory =
          await Directory(path.join(dataRoot, 'games', 'sample_$index'))
              .create(recursive: true);
      final gameId = await repo.insertGame(Game(
        path: directory.path,
        title: '主题检查 ${index + 1}',
        intro: '在游戏详情中检查标题、正文、标签、按钮以及图片覆盖层。',
        features: '共享组件与浅深色主题',
        guide: '# 攻略标题\n\n检查正文和 Markdown 标题样式。',
        isFavorite: index == 0,
        isPlayed: index == 1,
        isCleared: index == 2,
        rating: 8,
      ));
      await repo.addTagToGame(gameId, tagId);
      await repo.addTagToGame(gameId, seriesId);
      await repo.setGameImages(gameId,
          [GameImage(gameId: gameId, imagePath: cover.path, sortOrder: 0)]);
      selected ??= await repo.getGameById(gameId);
    }
    final game = selected!;
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(settings),
      allToolsProvider.overrideWith((ref) async => [
            Tool(id: 1, name: '示例工具', path: path.join(dataRoot, 'sample.exe')),
            Tool(id: 2, name: '示例文档', path: path.join(dataRoot, 'guide.txt')),
          ]),
    ]);
    final boundaryKey = GlobalKey();
    const evidencePath = String.fromEnvironment('UI_TOKEN_EVIDENCE');
    var states = 0;
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1440, 1000));

    Future<void> settle() async {
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(String name) async {
      await settle();
      states++;
      if (evidencePath.isEmpty) return;
      final directory = await Directory(evidencePath).create(recursive: true);
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final screenshot = await boundary.toImage();
      final png = await screenshot.toByteData(format: ui.ImageByteFormat.png);
      await File(path.join(directory.path, '$name.png'))
          .writeAsBytes(png!.buffer.asUint8List());
      screenshot.dispose();
    }

    Future<void> render(ThemeData theme, Widget child,
        {ProviderContainer? scope, bool reduced = false}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: UncontrolledProviderScope(
          container: scope ?? container,
          child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: reduced),
                    child: child!,
                  ),
              home: Scaffold(body: Center(child: child))),
        ),
      ));
      await settle();
    }

    try {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final theme = brightness == Brightness.light
            ? AppTheme.lightTheme()
            : AppTheme.darkTheme();
        final mode = brightness.name;
        for (final route
            in NavRoute.values.where((route) => route != NavRoute.settings)) {
          container.read(selectedNavIndexProvider.notifier).state =
              route.navIndex;
          await render(theme, const HomePage());
          await capture('${mode}_${route.name}');
        }
        await render(theme, const CategoriesPage());
        await tester.tap(find.text('标签'));
        await capture('${mode}_categories_tags');
        await render(theme, const FavoritesPage());
        await tester.tap(find.text('分类').last);
        await capture('${mode}_favorite_categories');
        await settings.setString('game_list_view_mode', 'list');
        await render(theme, GameListWidget(games: await repo.getAllGames()));
        await capture('${mode}_games_rows');
        await settings.setString('game_list_view_mode', 'poster');

        for (final phase in ['loading', 'empty', 'error']) {
          Future<List<T>> loadState<T>() => switch (phase) {
                'loading' => Completer<List<T>>().future,
                'empty' => Future.value([]),
                _ => Future.error(StateError('测试加载失败')),
              };
          final scope = ProviderContainer(parent: container, overrides: [
            allGamesProvider.overrideWith((ref) => loadState<Game>()),
            playedGamesProvider.overrideWith((ref) => loadState<Game>()),
            clearedGamesProvider.overrideWith((ref) => loadState<Game>()),
            favoriteGamesProvider.overrideWith((ref) => loadState<Game>()),
            allTagsProvider.overrideWith((ref) => loadState<Tag>()),
            allSeriesProvider.overrideWith((ref) => loadState<Tag>()),
            favoriteTagsProvider.overrideWith((ref) => loadState<Tag>()),
            allToolsProvider.overrideWith((ref) => loadState<Tool>()),
          ]);
          try {
            for (final route in [
              NavRoute.games,
              NavRoute.categories,
              NavRoute.favorites,
              NavRoute.played,
              NavRoute.cleared,
              NavRoute.tools
            ]) {
              await render(theme, route.buildPage(), scope: scope);
              await capture('${mode}_${route.name}_$phase');
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            scope.dispose();
          }
        }
        await render(theme, const HomePage());
        await tester.tap(find.text('设置').last);
        await settle();
        for (final category in ['通用', '管理', '刮削', '网络', '备份', '关于']) {
          await tester.tap(find
              .descendant(
                  of: find.byType(SettingsDialogContent),
                  matching: find.text(category))
              .first);
          await capture('${mode}_settings_$category');
          final scrollable = find
              .descendant(
                  of: find.byType(SettingsDialogContent),
                  matching: find.byType(SingleChildScrollView))
              .first;
          final scroll = tester.state<ScrollableState>(find
              .descendant(of: scrollable, matching: find.byType(Scrollable))
              .first);
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await capture('${mode}_settings_${category}_bottom');
        }
        final dialogs = <String, Widget>{
          'context_menu': const ContextMenuManagerDialog(),
          'sidebar': const SidebarManagerDialog(),
          'rename': const RenameManagerDialog(),
          'scrape_modes': const ScrapeModeConfigDialog(),
          'guide_hotkeys': const GuideHotkeyDialog(),
          'translation': MetadataTranslationDialog(settings: settings),
          'detail': GameDetailDialog(game: game),
          'images': ImageManagerDialog(game: game),
          'saves': SaveManagementDialog(game: game),
          'guide_search': GuideSearchDialog(game: game, initialKeyword: '主题检查'),
          'tag_games': TagGamesPage(tagId: tagId, tagName: '冒险'),
          'cleared_games': const ClearedGamesPage(),
        };
        for (final entry in dialogs.entries) {
          await render(theme, entry.value);
          await capture('${mode}_${entry.key}');
          if (entry.key == 'context_menu') {
            await tester.tap(find.text('已玩游戏/通关'));
            await capture('${mode}_context_menu_played');
          }
          if (entry.key == 'scrape_modes') {
            for (final label in ['重新刮削', '刮削中心', '单个添加', '批量添加']) {
              await tester.tap(find.text(label));
              await capture('${mode}_scrape_modes_$label');
            }
          }
        }
        container.read(selectedNavIndexProvider.notifier).state =
            NavRoute.games.navIndex;
        for (final entry in {
          'batch_import': '批量添加游戏',
          'single_import': '添加单个游戏',
        }.entries) {
          await render(theme, const HomePage());
          await tester.tap(find.byTooltip(entry.value));
          await capture('${mode}_${entry.key}');
        }

        final editor = TextEditingController(text: '# 动效检查\n\n编辑和预览内容保持一致。');
        try {
          await render(
              theme,
              SizedBox(
                width: 700,
                height: 500,
                child: MarkdownEditor(controller: editor, imagePaths: const []),
              ));
          await capture('${mode}_markdown_edit');
          await tester.tap(find.text('预览'));
          await capture('${mode}_markdown_preview');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          editor.dispose();
        }
        await render(theme, const CategoriesPage(), reduced: true);
        await tester.tap(find.text('标签'));
        await tester.pump();
        final tabs = tester.widget<TabBarView>(find.byType(TabBarView));
        expect(tabs.controller!.animationDuration, Duration.zero);
        await capture('${mode}_reduced_categories');
        await render(theme, const AppSkeleton(), reduced: true);
        await capture('${mode}_reduced_loading');
      }
      await render(
          AppTheme.lightTheme(),
          GuideWindowPage(
            windowId: '',
            arguments: {
              'title': '攻略动效检查',
              'content': '攻略\n\n图片与正文加载。\n\n[图片:${cover.path}]',
              'gameKey': 'motion_review',
            },
            fontSize: GlassConstants.fontBody,
          ));
      await capture('light_guide_window');
      await windowManager.setPreventClose(false);
      expect(states, 127);
      AppLogger.instance.info('DesignTokens', '原生主题检查完成: states=$states');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      await windowManager.setPreventClose(false);
      await settings.flush();
      await DatabaseHelper.close();
      await AppLogger.instance.flush();
      await Directory(dataRoot).delete(recursive: true);
    }
  });
}
