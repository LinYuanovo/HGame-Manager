import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/providers/providers.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/ui/controllers/sidebar_controller.dart';
import 'package:hgame_manager/ui/pages/app_router.dart';
import 'package:hgame_manager/ui/theme/app_theme.dart';
import 'package:hgame_manager/ui/widgets/sidebar_widget.dart';

class _Settings extends Fake implements AppSettings {
  String? config;
  @override
  String? getString(String key) =>
      key == AppSettings.sidebarConfigKey ? config : null;
  @override
  double? getDouble(String key) => null;
}

class _IndicatorPaint extends TestRecordingPaintingContext {
  _IndicatorPaint(super.canvas);
  @override
  void paintChild(RenderObject child, Offset offset) {}
}

void main() {
  test('侧栏配置按视觉顺序补齐新增入口，忽略重复和隐藏项', () {
    final settings = _Settings()
      ..config =
          '[{"routeName":"tools","order":1},{"routeName":"played","visible":false},{"routeName":"games","order":2},{"routeName":"games","order":3}]';
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(settings)]);
    addTearDown(container.dispose);
    expect(container.read(visibleSidebarRoutesProvider), [
      NavRoute.tools,
      NavRoute.games,
      NavRoute.scraper,
      NavRoute.categories,
      NavRoute.favorites,
      NavRoute.cleared
    ]);
    settings.config = null;
    container.read(sidebarRefreshProvider.notifier).state++;
    expect(container.read(visibleSidebarRoutesProvider),
        NavRoute.values.where((route) => route != NavRoute.settings));
  });

  testWidgets('选中背景从当前绘制位置改向，重排与减少动效使用实际行位置', (tester) async {
    final settings = _Settings();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(settings),
      allGamesProvider.overrideWith((ref) async => []),
      playedGamesProvider.overrideWith((ref) async => []),
      clearedGamesProvider.overrideWith((ref) async => []),
    ]);
    final sidebar = SidebarController();
    final reduced = ValueNotifier(false);
    addTearDown(container.dispose);
    addTearDown(sidebar.dispose);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: ValueListenableBuilder(
          valueListenable: reduced,
          builder: (context, disable, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: disable),
              child: Consumer(
                builder: (context, ref, _) => SidebarWidget(
                    controller: sidebar,
                    selectedIndex: ref.watch(selectedNavIndexProvider)),
              )),
        )))));
    await tester.pumpAndSettle();
    double markerCenter() {
      final box =
          tester.renderObject<RenderBox>(find.byType(AppMotionValue).first);
      final canvas = TestRecordingCanvas();
      box.paint(_IndicatorPaint(canvas), Offset.zero);
      final rounded = canvas.invocations
          .firstWhere((entry) => entry.invocation.memberName == #drawRRect);
      final rect = rounded.invocation.positionalArguments.first as RRect;
      return box.localToGlobal(rect.outerRect.center).dy;
    }

    double rowCenter(NavRoute route) =>
        tester.getCenter(find.byKey(ValueKey(route))).dy;
    expect(markerCenter(), closeTo(rowCenter(NavRoute.games), 0.01));
    await tester.tap(find.byKey(const ValueKey(NavRoute.tools)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    final mid = markerCenter();
    expect(mid,
        inExclusiveRange(rowCenter(NavRoute.games), rowCenter(NavRoute.tools)));
    await tester.tap(find.byKey(const ValueKey(NavRoute.scraper)));
    await tester.pump();
    expect(markerCenter(), closeTo(mid, 0.01));
    reduced.value = true;
    await tester.pump();
    expect(markerCenter(), closeTo(rowCenter(NavRoute.scraper), 0.01));
    settings.config = '[{"routeName":"tools","order":0}]';
    container.read(sidebarRefreshProvider.notifier).state++;
    sidebar.toggle();
    await tester.pumpAndSettle();
    expect(rowCenter(NavRoute.tools), lessThan(rowCenter(NavRoute.scraper)));
    expect(markerCenter(), closeTo(rowCenter(NavRoute.scraper), 0.01));
    expect(find.bySemanticsLabel('设置'), findsOneWidget);
  });
}
