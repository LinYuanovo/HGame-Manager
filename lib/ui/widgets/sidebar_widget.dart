import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/sidebar_controller.dart';
import '../../core/providers/providers.dart';
import '../../core/utils/app_settings.dart';
import '../theme/app_theme.dart';
import '../pages/app_router.dart';
import '../pages/settings/settings_page.dart';

/// 侧边栏独立组件，负责侧边栏的UI渲染和用户交互
class SidebarWidget extends ConsumerStatefulWidget {
  final SidebarController controller;
  final int selectedIndex;

  const SidebarWidget({
    super.key,
    required this.controller,
    required this.selectedIndex,
  });

  @override
  ConsumerState<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends ConsumerState<SidebarWidget> {
  List<NavRoute> _visibleRoutes = NavRoute.values.where((r) => r != NavRoute.settings).toList();

  @override
  void initState() {
    super.initState();
    _loadSidebarConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _loadSidebarConfig() async {
    final prefs = await AppSettings.load();
    final raw = prefs.getString(AppSettings.sidebarConfigKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    try {
      final List<dynamic> list = jsonDecode(raw);
      final configs = list.map((m) => _SidebarEntry.fromJson(m as Map<String, dynamic>)).toList();
      configs.sort((a, b) => a.order.compareTo(b.order));

      final routeMap = {for (final r in NavRoute.values) r.name: r};
      final visible = <NavRoute>[];
      for (final cfg in configs) {
        if (!cfg.visible) continue;
        final route = routeMap[cfg.routeName];
        if (route != null && route != NavRoute.settings) {
          visible.add(route);
        }
      }

      for (final r in NavRoute.values) {
        if (r == NavRoute.settings) continue;
        if (!visible.contains(r)) {
          final cfg = configs.firstWhere(
            (c) => c.routeName == r.name,
            orElse: () => _SidebarEntry(routeName: r.name, visible: true, order: 999),
          );
          if (cfg.visible) visible.add(r);
        }
      }

      if (mounted) {
        setState(() {
          _visibleRoutes = visible;
        });
      }
    } catch (e) {
      debugPrint('[Sidebar] 加载侧边栏配置失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(fontSizeProvider);
    final gameCount = ref.watch(allGamesProvider.select((a) => a.valueOrNull?.length));
    final playedCount = ref.watch(playedGamesProvider.select((a) => a.valueOrNull?.length));
    final clearedCount = ref.watch(clearedGamesProvider.select((a) => a.valueOrNull?.length));

    ref.listen<int>(sidebarRefreshProvider, (prev, next) {
      if (prev != null && prev != next) {
        _loadSidebarConfig();
      }
    });

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          widget.controller.updateWidth(details.delta.dx);
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            return AnimatedContainer(
                  duration: GlassConstants.animMedium,
                  curve: GlassConstants.animCurve,
                  width: widget.controller.width,
                  decoration: BoxDecoration(
                    color: AppTheme.getSurfaceColor(context).withValues(alpha: 0.85),
                    border: Border(
                      right: BorderSide(
                        color: AppTheme.getBorderColor(context).withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                   child: Column(
                    children: [
                      const SizedBox(height: 16),
                      ..._visibleRoutes.map((route) {
                        int? count;
                        if (route == NavRoute.games) {
                          count = gameCount;
                        } else if (route == NavRoute.played) {
                          count = playedCount;
                        } else if (route == NavRoute.cleared) {
                          count = clearedCount;
                        }
                        return _buildNavItem(
                          context: context,
                          route: route,
                          selectedIndex: widget.selectedIndex,
                          count: count,
                          fontSize: fontSize,
                          ref: ref,
                        );
                      }),
                      const Spacer(),
                      _buildToggleButton(fontSize: fontSize),
                      _buildNavItem(
                        context: context,
                        route: NavRoute.settings,
                        selectedIndex: widget.selectedIndex,
                        count: null,
                        fontSize: fontSize,
                        ref: ref,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
          },
        ),
      ),
    );
  }

  Widget _buildToggleButton({double fontSize = 14.0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          onTap: () => widget.controller.toggle(),
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            curve: GlassConstants.animCurve,
            padding: EdgeInsets.symmetric(
              horizontal: widget.controller.isExpanded ? 16 : 0,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              color: Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: widget.controller.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  widget.controller.isExpanded ? Icons.menu_open : Icons.menu,
                  color: AppTheme.getTextPrimary(context),
                  size: 22,
                ),
                if (widget.controller.isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '收起',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required NavRoute route,
    required int selectedIndex,
    int? count,
    double fontSize = 14.0,
    required WidgetRef ref,
  }) {
    final isSelected = route.index == selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          onTap: () {
            if (route == NavRoute.settings) {
              showSettingsDialog(context, ref);
            } else {
              ref.read(selectedNavIndexProvider.notifier).state = route.navIndex;
            }
          },
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            curve: GlassConstants.animCurve,
            padding: EdgeInsets.symmetric(
              horizontal: widget.controller.isExpanded ? 16 : 0,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        AppTheme.getPrimaryColor(context).withValues(alpha: 0.2),
                        AppTheme.secondaryColor.withValues(alpha: 0.2),
                      ],
                    )
                  : null,
              color: isSelected ? null : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppTheme.getPrimaryColor(context).withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: widget.controller.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? route.selectedIcon : route.icon,
                  color: isSelected
                      ? AppTheme.getPrimaryColor(context)
                      : AppTheme.getTextPrimary(context),
                  size: 22,
                ),
                if (widget.controller.isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      route.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.getPrimaryColor(context)
                            : AppTheme.getCardTitleColor(context),
                        fontSize: fontSize,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (count != null && count > 0)
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? LinearGradient(
                                  colors: [
                                    AppTheme.getPrimaryColor(context).withValues(alpha: 0.9),
                                    AppTheme.secondaryColor.withValues(alpha: 0.9),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : AppTheme.getTextSecondary(context).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minHeight: 18),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.getTextColorOnPrimary(context)
                                : AppTheme.getTextPrimary(context),
                            fontSize: (fontSize * 0.78).clamp(9, 14),
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarEntry {
  final String routeName;
  final bool visible;
  final int order;

  _SidebarEntry({required this.routeName, required this.visible, required this.order});

  factory _SidebarEntry.fromJson(Map<String, dynamic> json) {
    return _SidebarEntry(
      routeName: json['routeName'] as String,
      visible: json['visible'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
    );
  }
}
