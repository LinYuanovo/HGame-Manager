import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/database/database_helper.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/fan2d_service.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/core/utils/app_paths.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/games/game_detail_page.dart';
import 'package:hgame_manager/ui/pages/games/guide_search_dialog.dart';
import 'package:hgame_manager/ui/pages/settings/settings_page.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/game_list_widget.dart';
import 'package:hgame_manager/ui/widgets/image_manager_dialog.dart';
import 'package:hgame_manager/ui/widgets/draggable_image_grid.dart';
import 'package:hgame_manager/ui/widgets/picture_motion.dart';
import 'package:hgame_manager/ui/widgets/selection_surface.dart';
import 'package:hgame_manager/ui/pages/games/batch_import_dialog.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生图片开合、回库定位、封面拖排及设置定位', (tester) async {
    final timings = <FrameTiming>[];
    void collectTimings(List<FrameTiming> frames) => timings.addAll(frames);
    SchedulerBinding.instance.addTimingsCallback(collectTimings);
    addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(collectTimings));
    final root = await AppPaths.rootDir;
    expect(root.replaceAll('\\', '/'), contains('/build/windows/'));
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final settings = await AppSettings.loadFromFileForTest(
        path.join(root, 'motion-settings.json'));
    await settings.setBool('guide_window_hotkeys_enabled', false);
    await settings.setString('game_list_view_mode', 'list');
    await settings.setString('game_list_pagination_mode', 'paginated');
    final folder = await Directory(root).createTemp('motion-fixture-');
    final images = <String>[];
    for (var index = 0; index < 2; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final color = index == 0 ? AppTheme.successColor : AppTheme.warningColor;
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 480, 270), Paint()..color = color);
      canvas.drawCircle(
          const Offset(240, 135), 80, Paint()..color = AppTheme.errorColor);
      final picture = recorder.endRecording();
      final image = await picture.toImage(480, 270);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path.join(folder.path, 'image-$index.png'));
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      images.add(file.path);
      image.dispose();
      picture.dispose();
    }
    final repo = GameRepository();
    final games = <Game>[];
    for (var index = 0; index < 14; index++) {
      final gameFolder =
          await Directory(path.join(folder.path, 'game-$index')).create();
      final id = await repo.insertGame(Game(
          path: gameFolder.path,
          title: '动效${index.toString().padLeft(2, '0')}',
          intro: '阅读定位验证',
          isFavorite: true));
      await repo.setGameImages(
          id,
          images
              .map((image) => GameImage(gameId: id, imagePath: image))
              .toList());
      games.add((await repo.getGameById(id))!);
    }
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(settings)]);
    final boundary = GlobalKey();
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1440, 1000));
    Future<void> settle() async {
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(tester.takeException(), isNull);
    }

    Future<void> screenshot(String name, {bool settleFirst = true}) async {
      if (settleFirst) await settle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory =
          await Directory(path.join(root, 'motion-evidence')).create();
      await File(path.join(directory.path, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    Future<void> show(Widget child) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  theme: AppTheme.lightTheme(), home: Scaffold(body: child)))));
      await settle();
    }

    Future<void> verifyPromptActionRow({
      required String targetItem,
      required String prompt,
      required Finder action,
    }) async {
      await show(SettingsDialogContent(targetItem: targetItem));
      final promptFinder = find.textContaining(prompt).first;
      final row = find
          .ancestor(of: promptFinder, matching: find.byType(Row))
          .first;
      final actionFinder = find.descendant(of: row, matching: action);
      expect(actionFinder, findsOneWidget);
      expect(tester.getTopLeft(promptFinder).dx,
          lessThan(tester.getTopLeft(actionFinder).dx));
    }

    await show(GameListWidget(games: games, routeIndex: 1));
    container.read(libraryLocationProvider.notifier).state = games[8].id;
    await settle();
    expect(find.text('动效08').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('海报视图'));
    await settle();
    await tester.tap(find.text('动效08'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await screenshot('detail-opening', settleFirst: false);
    await settle();
    expect(find.byType(GameDetailDialog), findsOneWidget);
    final playButton = find.widgetWithText(ElevatedButton, '开始游玩');
    final manageImagesButton = find.widgetWithText(OutlinedButton, '管理图片');
    final standardOutlinedButtonHeight =
        tester.getSize(manageImagesButton).height;
    expect(tester.getSize(manageImagesButton).height,
        tester.getSize(playButton).height);
    final origin = find.byWidgetPredicate(
        (widget) => widget is PictureOrigin && widget.identity == images[0]);
    await tester.ensureVisible(origin.first);
    await settle();
    await tester.tap(origin.first);
    await settle();
    final viewer = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_ImageViewerDialog');
    expect(find.descendant(of: viewer, matching: find.text('1 / 2')),
        findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle();
    expect(find.descendant(of: viewer, matching: find.text('2 / 2')),
        findsOneWidget);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(viewer), scrollDelta: const Offset(0, -80)));
    await settle();
    expect(find.text('120%'), findsOneWidget);
    await screenshot('image-zoomed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(viewer, findsNothing);
    expect(find.byType(GameDetailDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(find.byType(GameDetailDialog), findsNothing);
    expect(find.text('动效08').hitTestable(), findsOneWidget);
    await screenshot('return-to-game');
    await show(ImageManagerDialog(game: games[8]));
    final grid = find.byType(DraggableImageGrid);
    final drags =
        find.descendant(of: grid, matching: find.byType(Draggable<GameImage>));
    final dragStart = tester.getCenter(drags.first);
    final dragEnd = tester.getCenter(drags.last);
    final imageDrag = await tester.startGesture(dragStart);
    await imageDrag.moveTo(Offset.lerp(dragStart, dragEnd, 0.4)!);
    await tester.pump(const Duration(milliseconds: 60));
    await imageDrag.moveTo(dragEnd);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.widget<DraggableImageGrid>(grid).images.first.imagePath,
        images[1]);
    await imageDrag.up();
    await settle();
    final reordered = tester.widget<DraggableImageGrid>(grid);
    expect(reordered.images.first.imagePath, images[1]);
    expect(reordered.images[reordered.coverIndex].imagePath, images[0]);
    await screenshot('images-reordered');
    expect((await repo.getGameById(games[8].id!))!.images.first.imagePath,
        images[0]);
    await show(Builder(
        builder: (context) => TextButton(
            onPressed: () => showAppDialog(
                context: context,
                builder: (_) => ImageManagerDialog(game: games[8])),
            child: const Text('打开图片管理'))));
    await tester.tap(find.text('打开图片管理'));
    await settle();
    await tester.dragFrom(tester.getCenter(drags.first),
        tester.getCenter(drags.last) - tester.getCenter(drags.first));
    await settle();
    await tester.tap(find.text('保存'));
    await settle();
    final saved = (await repo.getGameById(games[8].id!))!;
    expect(saved.images.first.imagePath, images[1]);
    expect(saved.images[saved.coverIndex].imagePath, images[0]);
    await show(const SettingsDialogContent(targetItem: '自动更新'));
    expect(find.text('自动更新').hitTestable(), findsWidgets);
    await screenshot('settings-located');
    await show(const SettingsDialogContent(targetItem: '诊断日志'));
    final diagnosticsText = find.textContaining('遇到问题后导出诊断包');
    final exportDiagnostics =
        find.widgetWithText(ElevatedButton, '导出诊断包');
    final diagnosticsRow = find
        .ancestor(of: diagnosticsText, matching: find.byType(Row))
        .first;
    expect(
        find.descendant(
            of: diagnosticsRow, matching: exportDiagnostics),
        findsOneWidget);
    expect(
        (tester.widget<Row>(diagnosticsRow).children[1] as SizedBox).width,
        GlassConstants.spacingLarge);
    expect(tester.getTopLeft(diagnosticsText).dx,
        lessThan(tester.getTopLeft(exportDiagnostics).dx));
    await screenshot('diagnostics-layout');
    await show(const SettingsDialogContent(targetItem: '封面画质'));
    expect(
        tester.widget<SelectionSurface>(find.byType(SelectionSurface)).index,
        0);
    expect(find.text('节省封面内存'), findsOneWidget);

    await show(const SettingsDialogContent(targetItem: '忽略文件夹'));
    final folderButtons =
        find.widgetWithText(OutlinedButton, '选择文件夹');
    expect(folderButtons, findsNWidgets(2));
    for (var index = 0; index < 2; index++) {
      expect(tester.getSize(folderButtons.at(index)).height,
          standardOutlinedButtonHeight);
    }
    await verifyPromptActionRow(
      targetItem: '忽略文件夹',
      prompt: '扫描游戏库时将跳过这些文件夹',
      action: find.widgetWithText(OutlinedButton, '选择文件夹'),
    );
    await verifyPromptActionRow(
      targetItem: '字体设置',
      prompt: '导入自定义 TTF 字体文件',
      action: find.widgetWithText(OutlinedButton, '导入 TTF 字体'),
    );
    expect(
        tester.getSize(find.widgetWithText(OutlinedButton, '导入 TTF 字体'))
            .height,
        standardOutlinedButtonHeight);

    await settings.setString('xpath_parsers', jsonEncode([
      {'domain': 'example.test', 'name': '示例站点', 'title': '//h1'},
    ]));
    await verifyPromptActionRow(
      targetItem: '自定义解析器',
      prompt: '当内置解析器无法覆盖新站点时',
      action: find.widgetWithText(OutlinedButton, '添加站点'),
    );
    final parserHeader = find.text('示例站点 (example.test)');
    final parserCard = find
        .ancestor(of: parserHeader, matching: find.byType(GlassContainer))
        .first;
    final parserCardWidget = tester.widget<GlassContainer>(parserCard);
    expect(parserCardWidget.enableBlur, isFalse);
    expect(parserCardWidget.color,
        AppTheme.getCardDefaultColor(tester.element(parserCard)));
    expect(tester.getSize(find.widgetWithText(OutlinedButton, '添加站点')).height,
        standardOutlinedButtonHeight);
    await screenshot('settings-parser-card');

    await verifyPromptActionRow(
      targetItem: '黑名单管理',
      prompt: '管理扫描时忽略的游戏路径',
      action: find.widgetWithText(ElevatedButton, '编辑黑名单'),
    );
    await verifyPromptActionRow(
      targetItem: '右键菜单管理',
      prompt: '管理游戏列表右键菜单中显示的选项',
      action: find.widgetWithText(ElevatedButton, '打开菜单管理'),
    );
    await verifyPromptActionRow(
      targetItem: '侧边栏页面管理',
      prompt: '管理侧边栏中显示的页面及顺序',
      action: find.widgetWithText(ElevatedButton, '打开侧边栏管理'),
    );
    await verifyPromptActionRow(
      targetItem: '封面比例管理',
      prompt: '仅调整海报网格的封面宽高比',
      action: find.text('4:3'),
    );
    await verifyPromptActionRow(
      targetItem: '刮削行为管理',
      prompt: '为每种刮削模式独立设置重命名和移动行为',
      action: find.widgetWithText(ElevatedButton, '打开刮削行为管理'),
    );
    await verifyPromptActionRow(
      targetItem: '重命名规则管理',
      prompt: '配置游戏文件夹重命名规则',
      action: find.widgetWithText(ElevatedButton, '打开重命名规则管理'),
    );
    await verifyPromptActionRow(
      targetItem: '攻略浮窗快捷键',
      prompt: '自定义攻略浮窗的全局快捷键',
      action: find.widgetWithText(ElevatedButton, '打开快捷键设置'),
    );
    await show(Consumer(
        builder: (context, ref, _) => TextButton(
            onPressed: () => showSettingsDialog(context, ref),
            child: const Text('打开设置'))));
    await tester.tap(find.text('打开设置'));
    await settle();
    await tester.tap(find.text('关于').first);
    await settle();
    final settingsScroll = find
        .descendant(
            of: find.byType(SettingsDialogContent),
            matching: find.byType(SingleChildScrollView))
        .last;
    await tester.drag(settingsScroll, const Offset(0, -550));
    await settle();
    final position = tester
        .state<ScrollableState>(find
            .descendant(of: settingsScroll, matching: find.byType(Scrollable))
            .first)
        .position
        .pixels;
    Navigator.of(tester.element(find.byType(SettingsDialogContent))).pop();
    await settle();
    await tester.tap(find.text('打开设置'));
    await settle();
    final restoredScroll = find
        .descendant(
            of: find.byType(SettingsDialogContent),
            matching: find.byType(SingleChildScrollView))
        .last;
    expect(
        tester
            .state<ScrollableState>(find
                .descendant(
                    of: restoredScroll, matching: find.byType(Scrollable))
                .first)
            .position
            .pixels,
        closeTo(position, 1));

    final importedFolder =
        await Directory(path.join(folder.path, 'new-import')).create();
    int? importedId;
    await show(Builder(
        builder: (context) => TextButton(
            onPressed: () => showGlassDialog(
                context: context,
                child: BatchImportDialog(
                    initialFolderPaths: [importedFolder.path],
                    onImportComplete: () {},
                    onLocate: (id) => importedId = id)),
            child: const Text('批量添加样例'))));
    await tester.tap(find.text('批量添加样例'));
    await settle();
    await tester.tap(find.text('Steam').first);
    await settle();
    await tester.tap(find.text('不刮削').last);
    await settle();
    await tester.tap(find.widgetWithText(ElevatedButton, '导入 (1)'));
    for (var step = 0;
        step < 100 && find.byTooltip('在游戏库中查看').evaluate().isEmpty;
        step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byTooltip('在游戏库中查看'), findsOneWidget);
    await tester.tap(find.byTooltip('在游戏库中查看'));
    await settle();
    expect(importedId, isNotNull);
    expect((await repo.getGameById(importedId!))!.path, importedFolder.path);
    await File(path.join(root, 'motion-evidence', 'debug-frame-times.json'))
        .writeAsString(jsonEncode({
      'mode': 'debug',
      'frames': timings.length,
      'buildMicroseconds':
          timings.map((frame) => frame.buildDuration.inMicroseconds).toList(),
      'rasterMicroseconds':
          timings.map((frame) => frame.rasterDuration.inMicroseconds).toList(),
    }));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await DatabaseHelper.close();
    await settings.flush();
  });

  testWidgets('改选攻略后旧图片请求不会覆盖当前和已保存配图', (tester) async {
    final temp = await Directory.systemTemp.createTemp('hgame-guide-motion-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final oldRequested = Completer<void>();
    final releaseOld = Completer<void>();
    final oldResponded = Completer<void>();
    final subscription = server.listen((request) async {
      if (request.uri.path == '/old.jpg') {
        oldRequested.complete();
        await releaseOld.future;
        request.response.add([1, 2, 3]);
        await request.response.close();
        oldResponded.complete();
      } else {
        request.response.add([4, 5, 6]);
        await request.response.close();
      }
    });
    addTearDown(() async {
      if (!releaseOld.isCompleted) releaseOld.complete();
      await subscription.cancel();
      await server.close(force: true);
      AppSettings.invalidateCache();
      await temp.delete(recursive: true);
    });
    final settings = await AppSettings.loadFromFileForTest(
        path.join(temp.path, 'settings.json'));
    final images = await GameDataPaths.ensureImagesDir(temp.path);
    final savedImage = File(path.join(images.path, 'guide_01.jpg'));
    await savedImage.writeAsBytes([9, 8, 7]);
    final service = _LocalImageGuides('http://127.0.0.1:${server.port}');
    String? result;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(settings),
          fan2dServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () async {
                            result = await showAppDialog<String>(
                                context: context,
                                builder: (_) => GuideSearchDialog(
                                    game: Game(path: temp.path),
                                    initialKeyword: '攻略'));
                          },
                          child: const Text('打开攻略测试'),
                        ))))));
    await tester.tap(find.text('打开攻略测试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pilipili'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2DFan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('攻略甲'));
    for (var attempt = 0;
        attempt < 100 && !oldRequested.isCompleted;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(oldRequested.isCompleted, isTrue);
    await tester.tap(find.text('攻略乙'));
    for (var attempt = 0; attempt < 100 && result == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(result, isNotNull);
    final currentImage =
        File(RegExp(r'\[图片:([^\]]+)\]').firstMatch(result!)!.group(1)!);
    expect(await currentImage.readAsBytes(), [4, 5, 6]);
    releaseOld.complete();
    await oldResponded.future.timeout(const Duration(seconds: 5));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(await currentImage.readAsBytes(), [4, 5, 6]);
    expect(await savedImage.readAsBytes(), [9, 8, 7]);
    expect(await images.list().length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _LocalImageGuides extends Fake implements Fan2dService {
  _LocalImageGuides(this.baseUrl);
  final String baseUrl;

  @override
  Future<List<Fan2dGuideResult>> searchGuides(String keyword) async => [
        Fan2dGuideResult(title: '攻略甲', guideUrl: '$baseUrl/old.jpg'),
        Fan2dGuideResult(title: '攻略乙', guideUrl: '$baseUrl/current.jpg'),
      ];

  @override
  Future<Fan2dGuideScrapeResult> scrapeGuideContent(String url) async =>
      Fan2dGuideScrapeResult(content: '[图片:$url]');
}
