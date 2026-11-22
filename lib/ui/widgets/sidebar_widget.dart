import 'package:flutter/material.dart';
import 'selection_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/sidebar_controller.dart';
import '../../core/providers/providers.dart';
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
  bool _isResizing = false;

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(fontSizeProvider);
    final gameCount =
        ref.watch(allGamesProvider.select((a) => a.valueOrNull?.length));
    final playedCount =
        ref.watch(playedGamesProvider.select((a) => a.valueOrNull?.length));
    final clearedCount =
        ref.watch(clearedGamesProvider.select((a) => a.valueOrNull?.length));

    final routes = ref.watch(visibleSidebarRoutesProvider);
    final slot = routes.indexOf(NavRoute.fromIndex(widget.selectedIndex));
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      gradient: LinearGradient(colors: [
        AppTheme.getPrimaryColor(context).withValues(alpha: 0.2),
        AppTheme.getSecondaryColor(context).withValues(alpha: 0.2),
      ]),
      border: Border.all(
          color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.4)),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragStart: (_) => setState(() => _isResizing = true),
        onHorizontalDragEnd: (_) => setState(() => _isResizing = false),
        onHorizontalDragCancel: () => setState(() => _isResizing = false),
        onHorizontalDragUpdate: (details) {
          widget.controller.updateWidth(details.delta.dx);
        },
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            return AnimatedContainer(
              duration: _isResizing
                  ? Duration.zero
                  : AppMotion.duration(context, GlassConstants.animMedium),
              curve: GlassConstants.animCurve,
              width: widget.controller.width,
              decoration: BoxDecoration(
                color:
                    AppTheme.getSurfaceColor(context).withValues(alpha: 0.85),
                border: Border(
                  right: BorderSide(
                    color:
                        AppTheme.getBorderColor(context).withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: GlassConstants.spacingMedium),
                  Expanded(
                      child: SingleChildScrollView(
                          child: SelectionSurface(
                    index: slot,
                    decoration: decoration,
                    insets: const EdgeInsets.symmetric(
                        horizontal: GlassConstants.spacingSmall,
                        vertical: GlassConstants.spacingMicro),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: routes.map((route) {
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
                        }).toList()),
                  ))),
                  _buildToggleButton(fontSize: fontSize),
                  _buildNavItem(
                    context: context,
                    route: NavRoute.settings,
                    selectedIndex: widget.selectedIndex,
                    count: null,
                    fontSize: fontSize,
                    ref: ref,
                  ),
                  const SizedBox(height: GlassConstants.spacingMedium),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildToggleButton({double fontSize = GlassConstants.fontControl}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: GlassConstants.spacingSmall,
          vertical: GlassConstants.spacingMicro),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
          onTap: () => widget.controller.toggle(),
          child: AnimatedContainer(
            duration: AppMotion.duration(context, GlassConstants.animFast),
            curve: GlassConstants.animCurve,
            padding: EdgeInsets.symmetric(
              horizontal: widget.controller.isExpanded
                  ? GlassConstants.spacingMedium
                  : 0,
              vertical: GlassConstants.spacingCompact,
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
                  size: GlassConstants.iconSection,
                ),
                if (widget.controller.isExpanded) ...[
                  const SizedBox(width: GlassConstants.spacingCompact),
                  Flexible(
                    child: Text(
                      '收起',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: fontSize,
                        fontWeight: AppTypography.regular,
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
    double fontSize = GlassConstants.fontControl,
    required WidgetRef ref,
  }) {
    final isSelected = route.navIndex == selectedIndex;

    return Semantics(
        key: ValueKey(route),
        button: true,
        selected: route == NavRoute.settings ? null : isSelected,
        label: widget.controller.isExpanded ? null : route.label,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: GlassConstants.spacingSmall,
              vertical: GlassConstants.spacingMicro),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
            child: InkWell(
              borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
              onTap: () {
                if (route == NavRoute.settings) {
                  showSettingsDialog(context, ref);
                } else {
                  ref.read(selectedNavIndexProvider.notifier).state =
                      route.navIndex;
                }
              },
              child: AnimatedContainer(
                duration: AppMotion.duration(context, GlassConstants.animFast),
                curve: GlassConstants.animCurve,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.controller.isExpanded
                      ? GlassConstants.spacingMedium
                      : 0,
                  vertical: GlassConstants.spacingCompact,
                ),
                child: Row(
                  mainAxisAlignment: widget.controller.isExpanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    AppSelectedMark(
                        selected: isSelected,
                        child: Icon(
                          isSelected ? route.selectedIcon : route.icon,
                          color: isSelected
                              ? AppTheme.getPrimaryColor(context)
                              : AppTheme.getTextPrimary(context),
                          size: GlassConstants.iconSection,
                        )),
                    if (widget.controller.isExpanded) ...[
                      const SizedBox(width: GlassConstants.spacingCompact),
                      Flexible(
                        child: Text(
                          route.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.getPrimaryColor(context)
                                : AppTheme.getCardTitleColor(context),
                            fontSize: fontSize,
                            fontWeight: isSelected
                                ? AppTypography.semibold
                                : AppTypography.regular,
                          ),
                        ),
                      ),
                      if (count != null && count > 0)
                        Flexible(
                          child: Container(
                            margin: const EdgeInsets.only(
                                left: GlassConstants.spacingSmall),
                            padding: const EdgeInsets.symmetric(
                                horizontal: GlassConstants.spacingTight,
                                vertical: GlassConstants.spacingMicro),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                      colors: [
                                        AppTheme.getPrimaryColor(context)
                                            .withValues(alpha: 0.9),
                                        AppTheme.getSecondaryColor(context)
                                            .withValues(alpha: 0.9),
                                      ],
                                    )
                                  : null,
                              color: isSelected
                                  ? null
                                  : AppTheme.getTextSecondary(context)
                                      .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(
                                  GlassConstants.radiusControl),
                            ),
                            constraints: const BoxConstraints(minHeight: 18),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.getOnPrimaryColor(context)
                                    : AppTheme.getTextPrimary(context),
                                fontSize: (fontSize * 0.78).clamp(
                                    GlassConstants.fontMicro,
                                    GlassConstants.fontControl),
                                fontWeight: AppTypography.semibold,
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
        ));
  }
}
