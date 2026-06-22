// lib/core/models/backup_entry.dart

/// 备份来源类型
enum BackupSource {
  manual,     // 手动备份（默认）
  preRestore, // 还原前自动备份
  imported,   // 用户导入的自定义备份
}

/// 备份条目数据模型
class BackupEntry {
  final String name;          // 显示名称（不含 .zip 后缀）
  final String fileName;      // 文件名（含 .zip 后缀）
  final int sizeBytes;        // 文件大小（字节）
  final DateTime? date;       // 备份日期
  final BackupSource source;  // 来源类型
  final String filePath;      // 完整本地路径

  const BackupEntry({
    required this.name,
    required this.fileName,
    required this.sizeBytes,
    this.date,
    this.source = BackupSource.manual,
    required this.filePath,
  });

  /// 格式化后的文件大小（如 137.4 KB）
  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 格式化后的日期（如 2026-06-22 13:00）
  String get dateFormatted {
    if (date == null) return '-';
    return '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')} ${date!.hour.toString().padLeft(2, '0')}:${date!.minute.toString().padLeft(2, '0')}';
  }
}