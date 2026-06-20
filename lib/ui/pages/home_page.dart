import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';
import '../theme/app_theme.dart';
import '../controllers/window_controller.dart';
import '../controllers/sidebar_controller.dart';
import '../widgets/title_bar_widget.dart';
import '../widgets/sidebar_widget.dart';
import 'app_router.dart';

class HomePage extends ConsumerStatefulWidget {
  final WindowController? windowController;

  const HomePage({super.key, this.windowController});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final SidebarController _sidebarController;
  late final WindowController _effectiveWindowController;

  @override
  void initState() {
    super.initState();
    _sidebarController = SidebarController();
    _effectiveWindowController = widget.windowController ?? WindowController(ref.read(sharedPreferencesProvider));
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedNavIndexProvider);

    final body = Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          TitleBarWidget(windowController: _effectiveWindowController),
          Expanded(
            child: Row(
              children: [
                SidebarWidget(
                  controller: _sidebarController,
                  selectedIndex: selectedIndex,
                ),
                Expanded(
                  child: AppRouter.getCurrentPage(selectedIndex),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: _effectiveWindowController.isExiting,
      builder: (context, isExiting, child) {
        return AnimatedOpacity(
          opacity: isExiting ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: child,
        );
      },
      child: body,
    );
  }
}
