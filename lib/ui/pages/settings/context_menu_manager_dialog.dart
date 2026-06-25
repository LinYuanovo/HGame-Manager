import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/context_menu_config.dart';
import '../../../core/providers/providers.dart';
import '../../theme/app_theme.dart';

class ContextMenuManagerDialog extends ConsumerStatefulWidget {
  const ContextMenuManagerDialog({super.key});

  @override
  ConsumerState<ContextMenuManagerDialog> createState() => _ContextMenuManagerDialogState();
}

class _ContextMenuManagerDialogState extends ConsumerState<ContextMenuManagerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        height: 600,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(child: _buildTabContent()),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(Icons.menu, color: AppTheme.primaryColor, size: 24),
          const SizedBox(width: 12),
          Text(
            '右键菜单管理',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 24),
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(GlassConstants.radiusMedium),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTabItem(0, '普通游戏列表')),
          Expanded(child: _buildTabItem(1, '已玩游戏/通关')),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String label) {
    final isSelected = _tabController.index == index;
    return _TabItemWidget(
      label: label,
      isSelected: isSelected,
      onTap: () => _tabController.animateTo(index),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _MenuItemsList(mode: 'games'),
        _MenuItemsList(mode: 'played'),
      ],
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _resetToDefaults,
            child: Text('恢复默认', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _saveAndClose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text('保存'),
          ),
        ],
      ),
    );
  }

  void _resetToDefaults() {
    final currentMode = _tabController.index == 0 ? 'games' : 'played';
    final provider = currentMode == 'games'
        ? contextMenuGamesProvider
        : contextMenuPlayedProvider;
    ref.read(provider.notifier).resetToDefaults();
  }

  void _saveAndClose() {
    ref.read(contextMenuGamesProvider.notifier).save();
    ref.read(contextMenuPlayedProvider.notifier).save();
    Navigator.pop(context, true);
    AppTheme.showGlassToast(context, message: '右键菜单配置已保存', icon: Icons.check_circle, iconColor: AppTheme.successColor);
  }
}

class _TabItemWidget extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabItemWidget({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TabItemWidget> createState() => _TabItemWidgetState();
}

class _TabItemWidgetState extends State<_TabItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: GlassConstants.animFast,
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppTheme.primaryColor
                : _isHovered
                    ? AppTheme.primaryColor.withValues(alpha: 0.08)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? Colors.white : AppTheme.textSecondary,
              fontWeight: widget.isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItemsList extends ConsumerWidget {
  final String mode;

  const _MenuItemsList({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mode == 'games'
        ? contextMenuGamesProvider
        : contextMenuPlayedProvider;
    final config = ref.watch(provider);
    final items = config.sortedItems;

    return ReorderableListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        ref.read(provider.notifier).reorderItem(oldIndex, newIndex);
      },
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
              child: child,
            ),
          ),
        );
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final def = _getDefinition(item.id);
        if (def == null) return SizedBox.shrink(key: ValueKey('empty_$index'));

        return Container(
          key: ValueKey(item.id),
          margin: EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: item.enabled
                ? AppTheme.surfaceColor
                : AppTheme.surfaceColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            border: Border.all(
              color: item.enabled
                  ? AppTheme.borderColor
                  : AppTheme.borderColor.withValues(alpha: 0.5),
            ),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            ),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(Icons.drag_handle, size: 20, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _getIconData(def.icon),
                  size: 20,
                  color: item.enabled
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 12),
                Text(
                  def.label,
                  style: TextStyle(
                    fontSize: 15,
                    color: item.enabled
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            trailing: Switch(
              value: item.enabled,
              onChanged: (_) => ref.read(provider.notifier).toggleItem(item.id),
              activeThumbColor: AppTheme.primaryColor,
            ),
          ),
        );
      },
    );
  }

  ContextMenuItemDef? _getDefinition(String id) {
    final defs = mode == 'games'
        ? PresetMenuItems.games
        : PresetMenuItems.played;
    return defs.where((d) => d.id == id).firstOrNull;
  }

  static IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'folder_open': return Icons.folder_open;
      case 'drive_file_move': return Icons.drive_file_move;
      case 'folder_special': return Icons.folder_special;
      case 'favorite': return Icons.favorite;
      case 'add_circle_outline': return Icons.add_circle_outline;
      case 'remove_circle_outline': return Icons.remove_circle_outline;
      case 'playlist_add': return Icons.playlist_add;
      case 'image': return Icons.image;
      case 'rate_review_outlined': return Icons.rate_review_outlined;
      case 'emoji_events': return Icons.emoji_events;
      case 'emoji_events_outlined': return Icons.emoji_events_outlined;
      case 'block': return Icons.block;
      case 'folder_delete_outlined': return Icons.folder_delete_outlined;
      default: return Icons.help_outline;
    }
  }
}
