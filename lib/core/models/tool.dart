class Tool {
  final int? id;
  final String name;
  final String path;
  final int sortOrder;
  final DateTime? createdAt;

  const Tool({
    this.id,
    required this.name,
    required this.path,
    this.sortOrder = 0,
    this.createdAt,
  });

  Tool copyWith({
    int? id,
    String? name,
    String? path,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return Tool(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'path': path,
      'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory Tool.fromMap(Map<String, dynamic> map) {
    return Tool(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      path: map['path'] as String? ?? '',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tool && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
