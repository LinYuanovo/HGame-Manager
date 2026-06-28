/// 重命名规则配置
class RenameRule {
  final String id;           // 规则ID（如 'game_id', 'maker', 'series', 'title', 'version'）
  final String name;         // 显示名称
  final bool enabled;        // 是否启用
  final int order;           // 排序顺序
  final String wrapBefore;   // 前包裹符号（如 '['）
  final String wrapAfter;    // 后包裹符号（如 ']'）

  const RenameRule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.order = 0,
    this.wrapBefore = '',
    this.wrapAfter = '',
  });

  /// 默认规则列表
  static List<RenameRule> defaultRules() {
    return [
      const RenameRule(id: 'game_id', name: '游戏ID', order: 0, wrapBefore: '[', wrapAfter: ']'),
      const RenameRule(id: 'maker', name: '游戏厂商', order: 1, wrapBefore: '[', wrapAfter: ']'),
      const RenameRule(id: 'series', name: '系列标签', order: 2, wrapBefore: '[', wrapAfter: ']'),
      const RenameRule(id: 'title', name: '游戏标题', order: 3, enabled: true),
      const RenameRule(id: 'version', name: '游戏版本', order: 4, enabled: true),
    ];
  }

  factory RenameRule.fromJson(Map<String, dynamic> json) {
    return RenameRule(
      id: json['id'] as String,
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
      wrapBefore: json['wrapBefore'] as String? ?? '',
      wrapAfter: json['wrapAfter'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'order': order,
    'wrapBefore': wrapBefore,
    'wrapAfter': wrapAfter,
  };

  RenameRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    int? order,
    String? wrapBefore,
    String? wrapAfter,
  }) {
    return RenameRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      wrapBefore: wrapBefore ?? this.wrapBefore,
      wrapAfter: wrapAfter ?? this.wrapAfter,
    );
  }

  /// 对内容应用包裹符号
  String wrapContent(String content) {
    if (wrapBefore.isEmpty && wrapAfter.isEmpty) return content;
    return '$wrapBefore$content$wrapAfter';
  }
}
