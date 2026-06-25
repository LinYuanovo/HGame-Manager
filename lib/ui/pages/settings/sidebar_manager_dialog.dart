import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/utils/app_settings.dart';
import '../../theme/app_theme.dart';
import '../app_router.dart';

class SidebarManagerDialog extends StatefulWidget {
  const SidebarManagerDialog({super.key});

  @override
  State<SidebarManagerDialog> createState() => _SidebarManagerDialogState();
}

class _SidebarManagerDialogState extends State<SidebarManagerDialog> {
  List<_SidebarItemConfig> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await AppSettings.load();
    final raw = prefs.getString(AppSettings.sidebarConfigKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw);
        _items = list.map((m) => _SidebarItemConfig.fromJson(m as Map<String, dynamic>)).toList();
        _loading = false;
        setState(() {});
        return;
      } catch (_) {}
    }

    _items = NavRoute.values
        .where((r) => r != NavRoute.settings)
        .toList()
        .asMap()
        .entries
        .map((e) => _SidebarItemConfig(
              routeName: e.value.name,
              visible: true,
              order: e.key,
            ))
        .toList();
    _loading = false;
    setState(() {});
  }

  Future<void> _saveConfig() async {
    final prefs = await AppSettings.load();
    final jsonStr = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(AppSettings.sidebarConfigKey, jsonStr);
  }

  void _resetToDefaults() {
    setState(() {
      _items = NavRoute.values
          .where((r) => r != NavRoute.settings)
          .toList()
          .asMap()
          .entries
          .map((e) => _SidebarItemConfig(
                routeName: e.value.name,
                visible: true,
                order: e.key,
              ))
          .toList();
    });
  }

  NavRoute? _findRoute(String name) {
    for (final r in NavRoute.values) {
      if (r.name == name) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        height: 560,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _buildList()),
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
          Icon(Icons.view_sidebar_outlined, color: AppTheme.primaryColor, size: 24),
          const SizedBox(width: 12),
          Text(
            '侧边栏页面管理',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: _items.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _items.removeAt(oldIndex);
          _items.insert(newIndex, item);
          for (int i = 0; i < _items.length; i++) {
            _items[i].order = i;
          }
        });
      },
      itemBuilder: (context, index) {
        final item = _items[index];
        final route = _findRoute(item.routeName);
        final isGames = item.routeName == 'games';

        return Container(
          key: ValueKey(item.routeName),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: item.visible
                ? AppTheme.surfaceColor
                : AppTheme.surfaceColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            border: Border.all(
              color: item.visible
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
                  route?.icon ?? Icons.help_outline,
                  size: 20,
                  color: item.visible
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 12),
                Text(
                  route?.label ?? item.routeName,
                  style: TextStyle(
                    fontSize: 15,
                    color: item.visible
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            trailing: Switch(
              value: item.visible,
              onChanged: isGames
                  ? null
                  : (v) {
                      setState(() => item.visible = v);
                    },
              activeThumbColor: AppTheme.primaryColor,
            ),
          ),
        );
      },
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
            onPressed: () async {
              await _saveConfig();
              if (mounted) {
                Navigator.pop(context, true);
                AppTheme.showGlassToast(context, message: '侧边栏配置已保存', icon: Icons.check_circle, iconColor: AppTheme.successColor);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _SidebarItemConfig {
  String routeName;
  bool visible;
  int order;

  _SidebarItemConfig({
    required this.routeName,
    required this.visible,
    required this.order,
  });

  factory _SidebarItemConfig.fromJson(Map<String, dynamic> json) {
    return _SidebarItemConfig(
      routeName: json['routeName'] as String,
      visible: json['visible'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'routeName': routeName,
        'visible': visible,
        'order': order,
      };
}
