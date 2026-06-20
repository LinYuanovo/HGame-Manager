/// 菜单项定义
class ContextMenuItemDef {
  final String id;
  final String label;
  final String icon;
  final bool defaultEnabled;

  const ContextMenuItemDef({
    required this.id,
    required this.label,
    required this.icon,
    this.defaultEnabled = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'icon': icon,
    'defaultEnabled': defaultEnabled,
  };

  factory ContextMenuItemDef.fromMap(Map<String, dynamic> map) =>
    ContextMenuItemDef(
      id: map['id'] as String,
      label: map['label'] as String,
      icon: map['icon'] as String,
      defaultEnabled: map['defaultEnabled'] as bool? ?? true,
    );
}

/// 菜单项运行时状态（包含启用/禁用和排序）
class ContextMenuItemState {
  final String id;
  final bool enabled;
  final int order;

  const ContextMenuItemState({
    required this.id,
    this.enabled = true,
    this.order = 0,
  });

  ContextMenuItemState copyWith({bool? enabled, int? order}) =>
    ContextMenuItemState(
      id: id,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
    );

  Map<String, dynamic> toMap() => {
    'id': id,
    'enabled': enabled,
    'order': order,
  };

  factory ContextMenuItemState.fromMap(Map<String, dynamic> map) =>
    ContextMenuItemState(
      id: map['id'] as String,
      enabled: map['enabled'] as bool? ?? true,
      order: map['order'] as int? ?? 0,
    );
}

/// 菜单配置管理器
class ContextMenuConfig {
  final List<ContextMenuItemState> items;

  const ContextMenuConfig({required this.items});

  /// 获取启用的菜单项（按order排序）
  List<ContextMenuItemState> get enabledItems =>
    items.where((i) => i.enabled).toList()..sort((a, b) => a.order.compareTo(b.order));

  /// 获取所有菜单项（按order排序）
  List<ContextMenuItemState> get sortedItems =>
    List.from(items)..sort((a, b) => a.order.compareTo(b.order));

  /// 检查某个菜单项是否启用
  bool isEnabled(String id) {
    final item = items.where((i) => i.id == id).firstOrNull;
    return item?.enabled ?? true;
  }

  ContextMenuConfig copyWith({List<ContextMenuItemState>? items}) =>
    ContextMenuConfig(items: items ?? this.items);

  Map<String, dynamic> toMap() => {
    'items': items.map((i) => i.toMap()).toList(),
  };

  factory ContextMenuConfig.fromMap(Map<String, dynamic> map) =>
    ContextMenuConfig(
      items: (map['items'] as List<dynamic>?)
        ?.map((i) => ContextMenuItemState.fromMap(i as Map<String, dynamic>))
        .toList() ?? [],
    );

  /// 创建默认配置
  factory ContextMenuConfig.defaults(List<ContextMenuItemDef> defs) =>
    ContextMenuConfig(
      items: defs.asMap().entries.map((e) =>
        ContextMenuItemState(
          id: e.value.id,
          enabled: e.value.defaultEnabled,
          order: e.key,
        )
      ).toList(),
    );
}

/// 预设菜单项定义
class PresetMenuItems {
  /// 普通游戏列表页面的菜单项
  static const List<ContextMenuItemDef> games = [
    ContextMenuItemDef(id: 'open_folder', label: '打开文件夹', icon: 'folder_open'),
    ContextMenuItemDef(id: 'move_folder', label: '移动文件夹', icon: 'drive_file_move'),
    ContextMenuItemDef(id: 'favorite', label: '收藏', icon: 'favorite'),
    ContextMenuItemDef(id: 'played', label: '增加游玩次数', icon: 'add_circle_outline'),
    ContextMenuItemDef(id: 'move_to_series', label: '移入自定义系列', icon: 'playlist_add'),
    ContextMenuItemDef(id: 'cover', label: '选择封面', icon: 'image'),
    ContextMenuItemDef(id: 'review', label: '评论', icon: 'rate_review_outlined'),
    ContextMenuItemDef(id: 'cleared', label: '标记已通关', icon: 'emoji_events'),
    ContextMenuItemDef(id: 'blacklist', label: '删除记录', icon: 'block'),
    ContextMenuItemDef(id: 'delete_folder', label: '删除本地文件夹', icon: 'folder_delete_outlined'),
  ];

  /// 已玩游戏/通关页面的菜单项
  static const List<ContextMenuItemDef> played = [
    ContextMenuItemDef(id: 'open_folder', label: '打开文件夹', icon: 'folder_open'),
    ContextMenuItemDef(id: 'move_folder', label: '移动文件夹', icon: 'drive_file_move'),
    ContextMenuItemDef(id: 'open_save', label: '打开存档位置', icon: 'folder_special'),
    ContextMenuItemDef(id: 'favorite', label: '收藏', icon: 'favorite'),
    ContextMenuItemDef(id: 'played', label: '减少游玩次数', icon: 'remove_circle_outline'),
    ContextMenuItemDef(id: 'move_to_series', label: '移入自定义系列', icon: 'playlist_add'),
    ContextMenuItemDef(id: 'cover', label: '选择封面', icon: 'image'),
    ContextMenuItemDef(id: 'review', label: '评论', icon: 'rate_review_outlined'),
    ContextMenuItemDef(id: 'uncleared', label: '取消标记已通关', icon: 'emoji_events_outlined'),
    ContextMenuItemDef(id: 'blacklist', label: '删除记录', icon: 'block'),
    ContextMenuItemDef(id: 'delete_folder', label: '删除本地文件夹', icon: 'folder_delete_outlined'),
  ];

  /// 根据模式获取预设定义
  static List<ContextMenuItemDef> getDefs(String mode) =>
    mode == 'played' ? played : games;
}
