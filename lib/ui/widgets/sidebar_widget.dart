import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/sidebar_controller.dart';
import '../../core/providers/providers.dart';
import '../theme/app_theme.dart';
import '../pages/app_router.dart';
import '../pages/settings/settings_page.dart';

/// 侧边栏独立组件，负责侧边栏的UI渲染和用户交互
class SidebarWidget extends ConsumerWidget {
  final SidebarController controller;
  final int selectedIndex;

  const SidebarWidget({
    super.key,
    required this.controller,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(fontSizeProvider);
    final gamesAsync = ref.watch(allGamesProvider);
    final playedAsync = ref.watch(playedGamesProvider);
    final clearedAsync = ref.watch(clearedGamesProvider);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          controller.updateWidth(details.delta.dx);
        },
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: GlassConstants.blurMedium,
                  sigmaY: GlassConstants.blurMedium,
                ),
                child: AnimatedContainer(
                  duration: GlassConstants.animMedium,
                  curve: GlassConstants.animCurve,
                  width: controller.width,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    border: Border(
                      right: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      ...NavRoute.values.where((r) => r != NavRoute.settings).map((route) {
                        int? count;
                        if (route == NavRoute.games) {
                          count = gamesAsync.valueOrNull?.length;
                        } else if (route == NavRoute.played) {
                          count = playedAsync.valueOrNull?.length;
                        } else if (route == NavRoute.cleared) {
                          count = clearedAsync.valueOrNull?.length;
                        }
                        return _buildNavItem(
                          context: context,
                          route: route,
                          selectedIndex: selectedIndex,
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
                        selectedIndex: selectedIndex,
                        count: null,
                        fontSize: fontSize,
                        ref: ref,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
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
          onTap: () => controller.toggle(),
          child: AnimatedContainer(
            duration: GlassConstants.animFast,
            curve: GlassConstants.animCurve,
            padding: EdgeInsets.symmetric(
              horizontal: controller.isExpanded ? 16 : 0,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              color: Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: controller.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  controller.isExpanded ? Icons.menu_open : Icons.menu,
                  color: AppTheme.textPrimary,
                  size: 22,
                ),
                if (controller.isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '收起',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
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
              horizontal: controller.isExpanded ? 16 : 0,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                        AppTheme.secondaryColor.withValues(alpha: 0.15),
                      ],
                    )
                  : null,
              color: isSelected ? null : Colors.transparent,
              border: Border.all(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: controller.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? route.selectedIcon : route.icon,
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textPrimary,
                  size: 22,
                ),
                if (controller.isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      route.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textPrimary,
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
                                    AppTheme.primaryColor.withValues(alpha: 0.8),
                                    AppTheme.secondaryColor.withValues(alpha: 0.8),
                                  ],
                                )
                              : null,
                          color: isSelected
                              ? null
                              : AppTheme.textSecondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minHeight: 18),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary,
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
