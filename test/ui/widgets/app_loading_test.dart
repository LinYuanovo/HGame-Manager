import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/models/backup_entry.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/core/services/backup_service.dart';
import 'package:hgame_manager/core/services/fan2d_service.dart';
import 'package:hgame_manager/core/services/webdav_service.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/pages/games/cloud_backup_dialog.dart';
import 'package:hgame_manager/ui/pages/games/save_management_dialog.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/game_list_skeleton.dart';
import 'package:hgame_manager/ui/widgets/image_manager_dialog.dart';

void main() {
  testWidgets('存档读取失败结束等待并提供重试入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backups = _EmptyBackups()..fail = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [backupServiceProvider.overrideWithValue(backups)],
      child: MaterialApp(
          home: Scaffold(
        body: SaveManagementDialog(
            game: Game(id: 1, path: 'sample', title: '测试')),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('存档加载失败'), findsOneWidget);
    expect(find.byType(AppSkeleton), findsNothing);
    backups.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无备份'), findsOneWidget);
    expect(find.textContaining('存档加载失败'), findsNothing);
  });

  testWidgets('存档搜索持续显示忙碌状态，完成后恢复操作按钮', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DelayedSaveSearch();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        backupServiceProvider.overrideWithValue(_EmptyBackups()),
        fan2dServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
          home: Scaffold(
        body: SaveManagementDialog(
            game: Game(id: 1, path: 'sample', title: '测试')),
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载存档'));
    await tester.pump();
    expect(find.text('正在获取存档…'), findsOneWidget);
    await tester.tap(find.text('正在获取存档…'));
    expect(service.calls, 1);
    service.results.complete([]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('下载存档'), findsOneWidget);
    expect(find.text('正在获取存档…'), findsNothing);
  });

  testWidgets('云端备份操作期间禁用刷新和其他操作，失败后恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DelayedWebdav()
      ..files = [const WebDavFile(name: '示例备份.zip', sizeBytes: 1024)];
    service.folders.complete(['加载检查']);
    await tester.pumpWidget(ProviderScope(
      overrides: [webdavServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
          home: Scaffold(
              body: CloudBackupDialog(
        game: Game(path: 'sample', title: '加载检查'),
        webdavUrl: 'https://example.invalid',
        webdavUsername: '',
        webdavPassword: '',
        onBackupDownloaded: () {},
      ))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.widgetWithText(ElevatedButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(service.deleteCalls, 1);
    expect(find.text('正在处理云端备份…'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('删除'));
    await tester.tap(find.byTooltip('下载此备份'));
    await tester.pump();
    expect(service.deleteCalls, 1);
    expect(find.text('确定要删除云端备份 "示例备份.zip" 吗？'), findsNothing);
    service.deletion.complete(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('正在处理云端备份…'), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNotNull);
  });

  testWidgets('图片保存中关闭窗口，完成后不再更新已销毁的界面', (tester) async {
    final repository = _DelayedImages();
    await tester.pumpWidget(ProviderScope(
      overrides: [gameRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: ImageManagerDialog(game: Game(id: 1, path: 'sample')),
        ),
      ),
    ));
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    repository.saved.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('后台插入的骨架保持静止，回到前台后才开始流光', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(const MaterialApp(home: AppSkeleton()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('游戏骨架按固定列数开关显示，并跟随布局设置更新', (tester) async {
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(_MemorySettings()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GameListSkeleton()),
    ));
    expect(tester.widget<AppSkeleton>(find.byType(AppSkeleton)).columns, 3);
    container.read(isFixedColumnCountProvider.notifier).state = true;
    await tester.pump();
    expect(tester.widget<AppSkeleton>(find.byType(AppSkeleton)).columns, 7);
    container.read(fixedColumnCountProvider.notifier).state = 1;
    container.read(posterCoverAspectRatioProvider.notifier).state = 4 / 3;
    await tester.pump();
    final skeleton = tester.widget<AppSkeleton>(find.byType(AppSkeleton));
    expect(skeleton.columns, 2);
    expect(skeleton.coverAspectRatio, 4 / 3);
  });

  testWidgets('图片加载占位填满受约束的显示区域', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 480,
          height: 360,
          child: Center(
            child: Builder(
              builder: (context) => appImageFrameBuilder(
                  context, const SizedBox.shrink(), null, false),
            ),
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(AppSkeleton)), const Size(480, 360));
  });

  testWidgets('正文图片高度未确定时占位有限，缓存命中直接显示图片', (tester) async {
    final loaded = ValueNotifier(false);
    addTearDown(loaded.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: ValueListenableBuilder(
          valueListenable: loaded,
          builder: (context, ready, child) => appImageFrameBuilder(
            context,
            const SizedBox(width: 320, height: 240, child: Text('图片内容')),
            ready ? 0 : null,
            ready,
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(AppSkeleton)).height, 160);
    loaded.value = true;
    await tester.pump();
    expect(find.byType(AppSkeleton), findsNothing);
    expect(find.text('图片内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('骨架隐藏或减少动效后停止，重新显示后恢复', (tester) async {
    final visible = ValueNotifier(true);
    final reduced = ValueNotifier(false);
    addTearDown(visible.dispose);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: reduced,
        builder: (context, disabled, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
          child: ValueListenableBuilder(
            valueListenable: visible,
            builder: (context, enabled, child) => TickerMode(
              enabled: enabled,
              child: const AppSkeleton(),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    visible.value = false;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    visible.value = true;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    reduced.value = true;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动效时未知进度静态等待，已知进度保留真实数值', (tester) async {
    final progress = ValueNotifier<double?>(null);
    addTearDown(progress.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, child) => Column(children: [
            AppProgressIndicator(value: value),
            AppLinearProgress(value: value),
          ]),
        ),
      ),
    ));
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    progress.value = 0.42;
    await tester.pump();
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        0.42);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.42);
  });

  testWidgets('云端备份加载时禁止重复刷新，完成后恢复按钮', (tester) async {
    final service = _DelayedWebdav();
    await tester.pumpWidget(ProviderScope(
      overrides: [webdavServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(
            body: CloudBackupDialog(
          game: Game(path: 'sample', title: '加载检查'),
          webdavUrl: 'https://example.invalid',
          webdavUsername: '',
          webdavPassword: '',
          onBackupDownloaded: () {},
        )),
      ),
    ));
    expect(find.byType(AppSkeleton), findsOneWidget);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(service.calls, 1);
    service.folders.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('暂无云端备份'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNotNull);
  });
}

class _MemorySettings extends Fake implements AppSettings {
  @override
  String? getString(String key) => null;

  @override
  bool? getBool(String key) => false;

  @override
  int? getInt(String key) => key == 'column_count' ? 7 : null;

  @override
  double? getDouble(String key) => null;
}

class _DelayedWebdav extends Fake implements WebdavService {
  final folders = Completer<List<String>>();
  final deletion = Completer<bool>();
  List<WebDavFile> files = [];
  var calls = 0;
  var deleteCalls = 0;

  @override
  Future<bool> deleteGameBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
    required String remoteFileName,
  }) {
    deleteCalls++;
    return deletion.future;
  }

  @override
  Future<List<String>> listGameFolders({
    required String serverUrl,
    required String username,
    required String password,
  }) {
    calls++;
    return folders.future;
  }

  @override
  Future<List<WebDavFile>> listGameBackups({
    required String serverUrl,
    required String username,
    required String password,
    required String gameFolder,
  }) async =>
      files;
}

class _DelayedImages extends Fake implements GameRepository {
  final saved = Completer<void>();

  @override
  Future<void> deleteGameImagesByGameId(int gameId) => saved.future;
}

class _EmptyBackups extends Fake implements BackupService {
  bool fail = false;

  @override
  Future<List<BackupEntry>> listBackups(String gamePath) async {
    if (fail) throw StateError('读取失败');
    return [];
  }

  @override
  Future<BackupEntry?> autoImportSaveFolder(String gamePath) async => null;
}

class _DelayedSaveSearch extends Fake implements Fan2dService {
  final results = Completer<List<Fan2dSearchResult>>();
  var calls = 0;

  @override
  Future<List<Fan2dSearchResult>> searchWithFallback({
    required String gamePath,
    String? gameLauncher,
    required String gameTitle,
  }) {
    calls++;
    return results.future;
  }
}
