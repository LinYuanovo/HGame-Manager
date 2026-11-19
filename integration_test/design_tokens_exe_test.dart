import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/repositories/tag_repository.dart';
import 'package:hgame_manager/core/services/app_logger.dart';
import 'package:hgame_manager/core/services/app_update_service.dart';
import 'package:hgame_manager/core/services/fan2d_service.dart';
import 'package:hgame_manager/core/services/webdav_service.dart';
import 'package:hgame_manager/core/utils/app_paths.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/app_router.dart';
import 'package:hgame_manager/ui/pages/categories/cleared_games_page.dart';
import 'package:hgame_manager/ui/pages/categories/categories_page.dart';
import 'package:hgame_manager/ui/pages/categories/tag_games_page.dart';
import 'package:hgame_manager/ui/pages/games/game_detail_page.dart';
import 'package:hgame_manager/ui/pages/games/cloud_backup_dialog.dart';
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
import 'package:hgame_manager/ui/widgets/draggable_image_grid.dart';
import 'package:hgame_manager/ui/widgets/app_update_dialog.dart';
import 'package:hgame_manager/ui/widgets/tag_input_dialog.dart';
import 'package:hgame_manager/ui/widgets/game_list_widget.dart';
import 'package:hgame_manager/ui/widgets/markdown_editor.dart';
import 'package:hgame_manager/ui/windows/guide_window.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实窗口：显示器节奏下的装饰采样', (tester) async {
    final policy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final done = Completer<void>();
    final samples = <Duration>[];
    double? previous;
    double? rate;
    try {
      await tester.pumpWidget(MaterialApp(home: Center(child: AppMotionValue(
        target: 1, begin: 0, duration: const Duration(milliseconds: 800),
        curve: Curves.linear, child: const FlutterLogo(size: 64),
        builder: (context, value, child) {
          rate = View.of(context).display.refreshRate;
          if (previous != value) {
            samples.add(SchedulerBinding.instance.currentFrameTimeStamp);
            previous = value;
          }
          if (value == 1 && !done.isCompleted) done.complete();
          return Transform.translate(offset: Offset(value * 100, 0), child: child);
        },
      ))));
      await done.future.timeout(const Duration(seconds: 10));
      expect(previous, 1);
      final elapsed = samples.last - samples.first;
      if (!MediaQuery.disableAnimationsOf(tester.element(find.byType(AppMotionValue))) &&
          !MediaQuery.accessibleNavigationOf(tester.element(find.byType(AppMotionValue)))) {
        expect(samples.length, greaterThan(2));
        expect(elapsed.inMilliseconds, greaterThanOrEqualTo(799));
        if (rate != null && rate! > 1) {
          expect(samples.length, lessThanOrEqualTo((elapsed.inMicroseconds * rate! / 1000000).ceil() + 2));
        }
      }
      debugPrint('动效采样 窗口 $rate Hz，耗时 ${elapsed.inMicroseconds / 1000} ms，观察到 ${samples.length} 个不同动画值，终值 $previous');
    } finally {
      binding.framePolicy = policy;
    }
  });
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
        await render(theme, const HomePage());
        for (final route in [
          NavRoute.categories,
          NavRoute.favorites,
          NavRoute.tools,
          NavRoute.games
        ]) {
          container.read(selectedNavIndexProvider.notifier).state =
              route.navIndex;
          await tester.pump(const Duration(milliseconds: 30));
        }
        await capture('${mode}_rapid_navigation');
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
              if (phase == 'error') expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
              if (route == NavRoute.categories || route == NavRoute.favorites) {
                await tester.tap(
                    find.text(route == NavRoute.categories ? '标签' : '分类').last);
                await capture('${mode}_${route.name}_second_$phase');
                if (phase == 'error') expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
              }
              if (route == NavRoute.games && phase == 'loading') {
                await settings.setString('game_list_view_mode', 'list');
                await render(theme, route.buildPage(), scope: scope);
                await capture('${mode}_games_rows_loading');
                await settings.setString('game_list_view_mode', 'poster');
              }
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
          'tag_input': TagInputDialog(selectedTags: const [], availableTags: [
            Tag(id: tagId, name: '冒险', type: Tag.typeCustom)
          ]),
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
        final images = _PausedImages();
        final imageScope = ProviderContainer(parent: container, overrides: [
          gameRepositoryProvider.overrideWithValue(images),
        ]);
        try {
          await render(theme, ImageManagerDialog(game: game),
              scope: imageScope);
          final gridSize = tester.getSize(find.byType(DraggableImageGrid));
          await tester.tap(find.text('保存'));
          await capture('${mode}_images_saving');
          expect(tester.getSize(find.byType(DraggableImageGrid)), gridSize);
          expect(find.text('正在处理图片…'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          images.saved.complete();
          await settle();
          imageScope.dispose();
        }

        final guides = _PausedGuides();
        final guideScope = ProviderContainer(parent: container, overrides: [
          fan2dServiceProvider.overrideWithValue(guides),
        ]);
        try {
          await render(
              theme, GuideSearchDialog(game: game, initialKeyword: '测试'),
              scope: guideScope);
          await tester.tap(find.text('pilipili'));
          await settle();
          await tester.tap(find.text('2DFan').last);
          await settle();
          await tester.tap(find.text('搜索'));
          await capture('${mode}_guide_search_loading');
          guides.results.complete([
            Fan2dGuideResult(
                title: '示例攻略', guideUrl: 'https://example.invalid'),
          ]);
          await settle();
          await tester.tap(find.text('示例攻略'));
          await capture('${mode}_guide_content_loading');
          expect(find.text('正在获取攻略及图片…'), findsOneWidget);
          await render(theme, SaveManagementDialog(game: game),
              scope: guideScope);
          await tester.tap(find.text('下载存档'));
          await capture('${mode}_save_search_loading');
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          guides.content.complete(Fan2dGuideScrapeResult());
          guides.saves.complete([]);
          await settle();
          guideScope.dispose();
        }

        final cloud = _PausedCloud();
        final cloudScope = ProviderContainer(parent: container, overrides: [
          webdavServiceProvider.overrideWithValue(cloud),
        ]);
        try {
          await render(
              theme,
              CloudBackupDialog(
                  game: game,
                  webdavUrl: 'https://example.invalid',
                  webdavUsername: '',
                  webdavPassword: '',
                  onBackupDownloaded: () {}),
              scope: cloudScope);
          await capture('${mode}_cloud_loading');
          cloud.folders.complete([]);
          await capture('${mode}_cloud_ready');
          await tester.tap(find.byTooltip('删除'));
          await settle();
          await tester.tap(find.widgetWithText(ElevatedButton, '删除'));
          await capture('${mode}_cloud_operating');
          expect(find.text('正在处理云端备份…'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          cloud.deletion.complete(false);
          await settle();
          cloudScope.dispose();
        }

        final updateProgress =
            ValueNotifier(const AppUpdateDownloadProgress(receivedBytes: 4096));
        try {
          await render(theme, const SizedBox.shrink());
          unawaited(showAppUpdateDownloadProgress(
              tester.element(find.byType(Scaffold)),
              version: '1.5.5',
              progressListenable: updateProgress));
          await capture('${mode}_update_unknown');
          updateProgress.value = const AppUpdateDownloadProgress(
              receivedBytes: 4200, totalBytes: 10000);
          await capture('${mode}_update_known');
          expect(
              tester
                  .widget<AppLinearProgress>(find.byType(AppLinearProgress))
                  .value,
              0.42);
          await render(theme, const SizedBox.shrink(), reduced: true);
          updateProgress.value =
              const AppUpdateDownloadProgress(receivedBytes: 4096);
          unawaited(showAppUpdateDownloadProgress(
              tester.element(find.byType(Scaffold)),
              version: '1.5.5',
              progressListenable: updateProgress));
          await capture('${mode}_update_reduced');
          expect(find.byType(LinearProgressIndicator), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          updateProgress.dispose();
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
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await render(
            brightness == Brightness.light
                ? AppTheme.lightTheme()
                : AppTheme.darkTheme(),
            GuideWindowPage(
              windowId: '',
              arguments: {
                'title': '攻略动效检查',
                'content': '攻略\n\n图片与正文加载。\n\n[图片:${cover.path}]',
                'gameKey': 'motion_review',
              },
              fontSize: GlassConstants.fontBody,
            ));
        await capture('${brightness.name}_guide_window');
      }
      await windowManager.setPreventClose(false);
      expect(states, 166);
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

class _PausedImages extends Fake implements GameRepository {
  final saved = Completer<void>();

  @override
  Future<void> setGameImages(int gameId, List<GameImage> images, {int? coverIndex}) => saved.future;

  @override
  Future<void> addGameImage(
      int gameId, String imagePath, int sortOrder) async {}

  @override
  Future<void> updateCoverIndex(int gameId, int coverIndex) async {}
}

class _PausedGuides extends Fake implements Fan2dService {
  final results = Completer<List<Fan2dGuideResult>>();
  final content = Completer<Fan2dGuideScrapeResult>();
  final saves = Completer<List<Fan2dSearchResult>>();

  @override
  Future<List<Fan2dGuideResult>> searchGuides(String keyword) => results.future;

  @override
  Future<Fan2dGuideScrapeResult> scrapeGuideContent(String url) =>
      content.future;

  @override
  Future<List<Fan2dSearchResult>> searchWithFallback({
    required String gamePath,
    String? gameLauncher,
    required String gameTitle,
  }) =>
      saves.future;
}

class _PausedCloud extends Fake implements WebdavService {
  final folders = Completer<List<String>>();
  final deletion = Completer<bool>();

  @override
  Future<List<String>> listGameFolders({
    required String serverUrl,
    required String username,
    required String password,
  }) =>
      folders.future;

  @override
  Future<List<WebDavFile>> listGameBackups({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
  }) async =>
      [const WebDavFile(name: '示例备份.zip', sizeBytes: 1024)];

  @override
  Future<bool> deleteGameBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
    required String remoteFileName,
  }) =>
      deletion.future;
}
