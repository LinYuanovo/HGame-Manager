import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/repositories/game_repository.dart';
import 'package:hgame_manager/ui/widgets/multi_select_controller.dart';
import 'package:hgame_manager/ui/pages/categories/tag_games_page.dart';
import 'package:hgame_manager/ui/widgets/game_list_widget.dart';

class _LibrarySettings extends Fake implements AppSettings {
  final strings = {
    'game_list_view_mode': 'list',
    'game_list_pagination_mode': 'paginated'
  };
  @override
  String? getString(String key) => strings[key];
  @override
  bool? getBool(String key) => null;
  @override
  double? getDouble(String key) => null;
  @override
  int? getInt(String key) => null;
  @override
  Object? get(String key) => null;
  @override
  Future<bool> setString(String key, String value) async {
    strings[key] = value;
    return true;
  }
}

class _Favorites extends Fake implements GameRepository {
  List<Game> games = [
    Game(id: 1, path: 'first', title: '同名游戏', isFavorite: true),
    Game(id: 2, path: 'second', title: '同名游戏', isFavorite: true)
  ];
  bool fail = true;
  @override
  Future<void> updateFavoriteStatus(int gameId, bool favorite) async {
    if (fail) throw StateError('写入失败');
    games = games.where((game) => game.id != gameId).toList();
  }
}

void main() {
  testWidgets('无限滚动切换视图后仍能看到刚打开的游戏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1150, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _LibrarySettings();
    settings.strings['game_list_pagination_mode'] = 'infiniteScroll';
    Game? opened;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: GameListWidget(
          games: List.generate(
              25,
              (index) => Game(
                  id: index,
                  path: 'game-$index',
                  title: '游戏${index.toString().padLeft(2, '0')}')),
          onGameTap: (game) => opened = game,
        )))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('游戏18'), 350,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('游戏18'));
    await tester.pumpAndSettle();
    expect(opened?.id, 18);
    await tester.tap(find.byTooltip('海报视图'));
    await tester.pumpAndSettle();
    expect(find.text('游戏18').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(find.text('游戏18').hitTestable(), findsOneWidget);
  });

  testWidgets('多选模式下回车勾选当前游戏并保留列表', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1150, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Game? opened;
    List<Game> selected = [];
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_LibrarySettings()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: GameListWidget(
          games: [Game(id: 1, path: 'sample', title: '键盘选择')],
          onGameTap: (game) => opened = game,
          onSelectionChanged: (games) => selected = games,
        )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('多选模式'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey<Object>(1));
    final focus = tester
        .widgetList<Focus>(
            find.descendant(of: row, matching: find.byType(Focus)))
        .firstWhere((focus) => focus.onKeyEvent != null);
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(selected.map((game) => game.id), [1]);
  });

  test('刷新数据后的多选继续按游戏 ID 保留并移除已删除记录', () {
    final selection = MultiSelectController<Game>();
    final old = Game(id: 1, path: 'before');
    selection.toggleSelection(old);
    final refreshed = Game(id: 1, path: 'after');
    selection.reconcile([refreshed], (game) => game.id!);
    expect(selection.selectedItems.single, same(refreshed));
    selection.reconcile([], (game) => game.id!);
    expect(selection.selectedItems, isEmpty);
    selection.dispose();
  });

  testWidgets('导入定位等待新数据到达，跳转到新游戏所在页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1150, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _LibrarySettings();
    final source = ValueNotifier(List.generate(
        8, (index) => Game(id: index, path: '$index', title: '游戏$index')));
    addTearDown(source.dispose);
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: ValueListenableBuilder(
          valueListenable: source,
          builder: (_, games, __) =>
              GameListWidget(games: games, routeIndex: 1),
        )))));
    await tester.pumpAndSettle();
    container.read(libraryLocationProvider.notifier).state = 9;
    await tester.pump();
    expect(container.read(libraryLocationProvider), 9);
    source.value = [...source.value, Game(id: 9, path: '9', title: '新游戏')];
    await tester.pumpAndSettle();
    expect(container.read(libraryLocationProvider), isNull);
    expect(find.text('新游戏').hitTestable(), findsOneWidget);
  });

  testWidgets('收藏写入失败保留原卡，成功后仅移除对应 ID', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1150, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _Favorites();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_LibrarySettings()),
          gameRepositoryProvider.overrideWithValue(repo),
          allGamesProvider.overrideWith((ref) async => repo.games),
          favoriteGamesProvider.overrideWith((ref) async => repo.games),
        ],
        child: MaterialApp(
            home: Scaffold(body: Consumer(builder: (context, ref, _) {
          final games = ref.watch(favoriteGamesProvider).valueOrNull;
          return games == null
              ? const SizedBox.shrink()
              : GameListWidget(games: games, routeIndex: 3);
        })))));
    await tester.pumpAndSettle();
    final favorite = find.descendant(
        of: find.byKey(const ValueKey<Object>(1)),
        matching: find.byIcon(Icons.favorite));
    await tester.tap(favorite);
    await tester.pumpAndSettle();
    expect(find.textContaining('收藏更新失败'), findsOneWidget);
    expect(find.byKey(const ValueKey<Object>(1)), findsOneWidget);
    repo.fail = false;
    await tester.tap(favorite);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<Object>(1)), findsNothing);
    expect(find.byKey(const ValueKey<Object>(2)), findsOneWidget);
  });
  testWidgets('分页视图切换保留刚打开的游戏，按实际网格容量定位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1150, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _LibrarySettings();
    final games = List.generate(
        18,
        (index) => Game(
            id: index,
            path: 'game-$index',
            title: '游戏${index.toString().padLeft(2, '0')}'));
    Game? opened;
    await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(settings)],
        child: MaterialApp(
            home: Scaffold(
                body: GameListWidget(
          games: games,
          onGameTap: (game) => opened = game,
        )))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('游戏08'));
    await tester.tap(find.text('游戏08'));
    await tester.pumpAndSettle();
    expect(opened?.id, 8);
    await tester.tap(find.byTooltip('海报视图'));
    await tester.pumpAndSettle();
    expect(find.text('游戏08'), findsOneWidget);
    expect(find.text('游戏00'), findsNothing);
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('游戏08'), findsOneWidget);
  });

  testWidgets('同名分类分别匹配当前来源，减少动效时标题直接显示', (tester) async {
    final reduce = ValueNotifier(false);
    addTearDown(reduce.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder(
      valueListenable: reduce,
      builder: (context, disabled, _) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disabled),
          child: const Column(children: [
            TagRouteTitle(anchor: ('分类', 3), name: '冒险', style: TextStyle()),
            TagRouteTitle(anchor: ('分类', 5), name: '冒险', style: TextStyle()),
          ])),
    )));
    expect(tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag),
        [('分类', 3), ('分类', 5)]);
    reduce.value = true;
    await tester.pump();
    expect(find.byType(Hero), findsNothing);
    expect(find.text('冒险'), findsNWidgets(2));
  });

  testWidgets('分类标题在实际子页往返，长标题保持在工具栏内', (tester) async {
    final name = '冒险' * 80;
    const anchor = ('分类', 5);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_LibrarySettings()),
          gamesByTagProvider(5).overrideWith((ref) async => []),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => TagGamesPage(
                                      tagId: 5,
                                      tagName: name,
                                      titleAnchor: anchor))),
                          child: TagRouteTitle(
                              anchor: anchor,
                              name: name,
                              style: const TextStyle()),
                        ))))));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.byType(TagGamesPage), findsOneWidget);
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
