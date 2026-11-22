import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';
import '../../core/utils/app_settings.dart';
import '../../core/services/app_logger.dart';
import '../theme/app_theme.dart';
import 'games/games_page.dart';
import 'categories/categories_page.dart';
import 'favorites/favorites_page.dart';
import 'played/played_page.dart';
import 'played/cleared_page.dart';
import 'scraper/scraper_page.dart';
import 'tools/tools_page.dart';

enum NavRoute {
  scraper(0, '刮削', Icons.description_outlined, Icons.description),
  games(1, '游戏', Icons.sports_esports_outlined, Icons.sports_esports),
  categories(2, '分类', Icons.category_outlined, Icons.category),
  favorites(3, '收藏', Icons.favorite_outline, Icons.favorite),
  played(4, '已玩', Icons.sports_score_outlined, Icons.sports_score),
  cleared(5, '通关', Icons.emoji_events_outlined, Icons.emoji_events),
  tools(6, '工具', Icons.build_outlined, Icons.build),
  settings(7, '设置', Icons.settings_outlined, Icons.settings);

  final int navIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const NavRoute(this.navIndex, this.label, this.icon, this.selectedIcon);

  static NavRoute fromIndex(int index) {
    return NavRoute.values.firstWhere(
      (route) => route.navIndex == index,
      orElse: () => NavRoute.games,
    );
  }

  Widget buildPage() {
    switch (this) {
      case NavRoute.scraper:
        return const ScraperPage();
      case NavRoute.games:
        return const GamesPage();
      case NavRoute.categories:
        return const CategoriesPage();
      case NavRoute.favorites:
        return const FavoritesPage();
      case NavRoute.played:
        return const PlayedPage();
      case NavRoute.cleared:
        return const ClearedPage();
      case NavRoute.tools:
        return const ToolsPage();
      case NavRoute.settings:
        return const SizedBox.shrink();
    }
  }

  static List<NavRoute> get sidebarOrder {
    final routes =
        NavRoute.values.where((r) => r != NavRoute.settings).toList();
    routes.add(NavRoute.settings);
    return routes;
  }
}

final visibleSidebarRoutesProvider = Provider<List<NavRoute>>((ref) {
  ref.watch(sidebarRefreshProvider);
  final raw = ref
      .watch(sharedPreferencesProvider)
      .getString(AppSettings.sidebarConfigKey);
  final defaults = NavRoute.values.where((route) => route != NavRoute.settings);
  if (raw == null || raw.isEmpty) return defaults.toList();
  try {
    final entries = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((first, second) => ((first['order'] as int?) ?? 0)
          .compareTo((second['order'] as int?) ?? 0));
    final remaining = {for (final route in defaults) route.name: route};
    final routes = <NavRoute>[];
    for (final entry in entries) {
      final route = remaining.remove(entry['routeName']);
      if (route != null && entry['visible'] != false) routes.add(route);
    }
    return [...routes, ...remaining.values];
  } catch (error) {
    debugPrint('[Sidebar] 加载侧边栏配置失败: $error');
    return defaults.toList();
  }
});

class AppRouter extends StatefulWidget {
  final int selectedIndex;
  final List<NavRoute> routeOrder;

  const AppRouter(
      {super.key,
      required this.selectedIndex,
      this.routeOrder = NavRoute.values});

  @override
  State<AppRouter> createState() => _AppRouterState();

  static Widget getCurrentPage(int selectedIndex,
      {List<NavRoute> routeOrder = NavRoute.values}) {
    return AppRouter(selectedIndex: selectedIndex, routeOrder: routeOrder);
  }

  static List<NavRoute> getAllRoutes() => NavRoute.values;
}

class _AppRouterState extends State<AppRouter> {
  bool _isForward = true;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.info('Navigation',
        '打开页面: ${NavRoute.fromIndex(widget.selectedIndex).label}');
  }

  @override
  void didUpdateWidget(covariant AppRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final previous = widget.routeOrder
          .indexOf(NavRoute.fromIndex(oldWidget.selectedIndex));
      final next =
          widget.routeOrder.indexOf(NavRoute.fromIndex(widget.selectedIndex));
      _isForward = next >= previous;
      AppLogger.instance.info('Navigation',
          '切换页面: ${NavRoute.fromIndex(widget.selectedIndex).label}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = NavRoute.fromIndex(widget.selectedIndex).buildPage();
    return AppContentSwitcher(
      direction: _isForward ? 1 : -1,
      child: KeyedSubtree(
        key: ValueKey(widget.selectedIndex),
        child: page,
      ),
    );
  }
}
