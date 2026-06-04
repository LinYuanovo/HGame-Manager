import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as path;

/// 全局日志服务 - 将应用日志写入文件，方便排错
///
/// 日志文件位置：exe所在目录/logs/app_YYYYMMDD.log
/// 自动删除3天前的日志
class AppLogger {
  static AppLogger? _instance;
  static AppLogger get instance => _instance ??= AppLogger._();
  AppLogger._();

  File? _logFile;
  bool _initialized = false;
  String? _logDir;

  /// 日志保留天数
  static const int _retainDays = 3;

  /// 初始化日志文件
  Future<void> init() async {
    if (_initialized) return;
    try {
      final exeDir = path.dirname(Platform.resolvedExecutable);
      _logDir = path.join(exeDir, 'logs');
      await Directory(_logDir!).create(recursive: true);

      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      _logFile = File(path.join(_logDir!, 'app_$dateStr.log'));
      _initialized = true;

      info('AppLogger', '日志系统初始化完成: ${_logFile?.path}');
      info('AppLogger', '应用版本: 1.0.8, 平台: ${Platform.operatingSystem}');

      // 清理过期日志
      _cleanOldLogs();
    } catch (e) {
      debugPrint('[AppLogger] 初始化失败: $e');
    }
  }

  /// 获取日志目录
  String? get logDir => _logDir;

  void _write(String tag, String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] [$level] [$tag] $message';
    if (kDebugMode) debugPrint(line);
    if (_logFile != null) {
      try {
        _logFile!.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    }
  }

  void info(String tag, String message) => _write(tag, 'INFO', message);
  void warning(String tag, String message) => _write(tag, 'WARN', message);
  void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    _write(tag, 'ERROR', message);
    if (error != null) _write(tag, 'ERROR', error.toString());
    if (stackTrace != null) _write(tag, 'ERROR', stackTrace.toString());
  }

  /// 清理超过保留天数的日志文件
  void _cleanOldLogs() {
    if (_logDir == null) return;
    try {
      final dir = Directory(_logDir!);
      if (!dir.existsSync()) return;

      final cutoff = DateTime.now().subtract(Duration(days: _retainDays));
      int deletedCount = 0;

      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith('.log')) {
          try {
            final stat = entity.statSync();
            if (stat.modified.isBefore(cutoff)) {
              entity.deleteSync();
              deletedCount++;
            }
          } catch (_) {}
        }
      }
      if (deletedCount > 0) {
        info('AppLogger', '已清理 $deletedCount 个过期日志文件（保留 $_retainDays 天）');
      }
    } catch (e) {
      debugPrint('[AppLogger] 清理日志失败: $e');
    }
  }
}
