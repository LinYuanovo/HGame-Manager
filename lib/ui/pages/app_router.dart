import 'package:flutter/material.dart';
import 'games/games_page.dart';
import 'categories/categories_page.dart';
import 'favorites/favorites_page.dart';
import 'played/played_page.dart';
import 'settings/settings_page.dart';
import 'scraper/scraper_page.dart';

enum NavRoute {
  scraper(0, '刮削', Icons.cloud_download_outlined, Icons.cloud_download),
  games(1, '游戏', Icons.sports_esports_outlined, Icons.sports_esports),
  categories(2, '分类', Icons.category_outlined, Icons.category),
  favorites(3, '收藏', Icons.favorite_outline, Icons.favorite),
  played(4, '已玩', Icons.sports_score_outlined, Icons.sports_score),
  settings(5, '设置', Icons.settings_outlined, Icons.settings);

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
      case NavRoute.settings:
        return const SettingsPage();
    }
  }

  static List<NavRoute> get sidebarOrder {
    final routes = NavRoute.values.where((r) => r != NavRoute.settings).toList();
    routes.add(NavRoute.settings);
    return routes;
  }
}

class AppRouter {
  static Widget getCurrentPage(int selectedIndex) {
    return NavRoute.fromIndex(selectedIndex).buildPage();
  }

  static List<NavRoute> getAllRoutes() => NavRoute.values;
}
