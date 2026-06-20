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
