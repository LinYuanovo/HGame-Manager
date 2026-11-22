import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/providers.dart';
import '../../core/utils/drop_import_utils.dart';
import '../theme/app_theme.dart';
import '../controllers/window_controller.dart';
import '../controllers/sidebar_controller.dart';
import '../widgets/title_bar_widget.dart';
import '../widgets/sidebar_widget.dart';
import 'app_router.dart';
import 'games/batch_import_dialog.dart';

class HomePage extends ConsumerStatefulWidget {
  final WindowController? windowController;

  const HomePage({super.key, this.windowController});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final SidebarController _sidebarController;
  late final WindowController _effectiveWindowController;

  /// 是否有文件正拖入窗口（用于显示拖放提示遮罩）
  bool _isDragHovering = false;

  @override
  void initState() {
    super.initState();
    _sidebarController = SidebarController();
    _effectiveWindowController = widget.windowController ??
        WindowController(ref.read(sharedPreferencesProvider));
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  /// 处理拖入完成：分流为游戏目录后弹出批量添加对话框
  void _handleDropDone(List<String> paths) {
    if (_isDragHovering) setState(() => _isDragHovering = false);
    final result = DropImportUtils.resolveDroppedPaths(paths);
    if (result.folderPaths.isEmpty) {
      AppTheme.showGlassToast(
        context,
        message: '请拖入游戏文件夹或 exe 文件',
        icon: Icons.warning_amber,
        iconColor: AppTheme.warningColor,
      );
      return;
    }
    showGlassDialog(
      context: context,
      child: BatchImportDialog(
        onLocate: (id) {
          ref.read(libraryLocationProvider.notifier).state = id;
          ref.read(selectedNavIndexProvider.notifier).state =
              NavRoute.games.navIndex;
        },
        onImportComplete: () {
          ref.invalidate(allGamesProvider);
        },
        initialFolderPaths: result.folderPaths,
        presetKeywords: result.presetKeywords,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedNavIndexProvider);

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragHovering = true),
      onDragExited: (_) => setState(() => _isDragHovering = false),
      onDragDone: (detail) =>
          _handleDropDone(detail.files.map((f) => f.path).toList()),
      child: Scaffold(
        backgroundColor: AppTheme.getBackgroundColor(context),
        body: Stack(
          children: [
            Column(
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
                        child: AppRouter.getCurrentPage(
                          selectedIndex,
                          routeOrder: ref.watch(visibleSidebarRoutesProvider),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 拖入悬停时的提示遮罩
            if (_isDragHovering)
              Positioned.fill(
                // 遮罩不拦截指针事件，避免干扰拖放与下层 UI
                child: IgnorePointer(
                  child: Container(
                    color: AppTheme.getPrimaryColor(context)
                        .withValues(alpha: 0.08),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: GlassConstants.spacingPage,
                            vertical: GlassConstants.spacingXLarge),
                        decoration: BoxDecoration(
                          color: AppTheme.getSurfaceColor(context)
                              .withValues(alpha: 0.92),
                          borderRadius:
                              BorderRadius.circular(GlassConstants.radiusLarge),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.create_new_folder_outlined,
                              size: GlassConstants.iconPlaceholder,
                              color: AppTheme.getPrimaryColor(context),
                            ),
                            const SizedBox(
                                height: GlassConstants.spacingCompact),
                            Text(
                              '松开以添加游戏文件夹 / exe',
                              style: TextStyle(
                                fontSize: GlassConstants.fontBodyLarge,
                                fontWeight: AppTypography.semibold,
                                color: AppTheme.getTextPrimary(context),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
