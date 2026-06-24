import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show VoidCallback;
import 'app_paths.dart';

/// JSON-file-based settings store that replaces [SharedPreferences].
///
/// All settings are persisted to <exe_dir>/hgame_manager_data/settings.json,
/// keeping data local to the installation directory (no C: AppData leakage).
///
/// API mirrors [SharedPreferences] so existing call sites need only
/// a type rename, not logic changes.
class AppSettings {
  static const String autoRenameFoldersKey = 'auto_rename_folders';
  static const String contextMenuGamesKey = 'context_menu_games';
  static const String contextMenuPlayedKey = 'context_menu_played';
  static const String noImageModeKey = 'no_image_mode';
  static const String keepPlayedInGamesKey = 'keep_played_in_games';

  Map<String, dynamic> _data = {};
  final String _filePath;
  bool _dirty = false;

  static AppSettings? _cachedInstance;

  AppSettings._(this._filePath);

  /// Load (or create) the settings file from disk.
  /// Returns a cached instance if one already exists.
  static Future<AppSettings> load() async {
    if (_cachedInstance != null) return _cachedInstance!;
    final filePath = await AppPaths.settingsFile;
    final settings = AppSettings._(filePath);
    await settings._loadFromFile();
    _cachedInstance = settings;
    return settings;
  }

  /// Invalidate the cached instance (useful after import/restore).
  static void invalidateCache() {
    _cachedInstance = null;
  }

  Future<void> _loadFromFile() async {
    try {
      final file = File(_filePath);
      if (await file.exists()) {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          try {
            _data = jsonDecode(raw) as Map<String, dynamic>;
          } catch (e) {
            // JSON 解析失败，尝试从备份恢复
            debugPrint('[AppSettings] JSON parse error, trying backup: $e');
            final backupFile = File('$_filePath.bak');
            if (await backupFile.exists()) {
              try {
                final backupRaw = await backupFile.readAsString();
                _data = jsonDecode(backupRaw) as Map<String, dynamic>;
                // 恢复备份
                await file.writeAsString(backupRaw, flush: true);
              } catch (_) {
                _data = {};
              }
            } else {
              _data = {};
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AppSettings] Load error: $e');
      _data = {};
    }
  }

  Future<void> _saveToFile() async {
    if (!_dirty) return;
    try {
      final file = File(_filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 保存前创建备份
      if (await file.exists()) {
        final backupFile = File('$_filePath.bak');
        try {
          await file.copy(backupFile.path);
        } catch (_) {}
      }
      
      final tempFile = File('$_filePath.tmp');
      // 清理可能残留的旧临时文件
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      await tempFile.writeAsString(jsonEncode(_data), flush: true);
      
      try {
        await tempFile.rename(_filePath);
      } catch (e) {
        // 如果 rename 失败（文件被占用），尝试先删除再重命名
        try {
          if (await file.exists()) {
            await file.delete();
          }
          await tempFile.rename(_filePath);
        } catch (e2) {
          // 如果还是失败，尝试直接写入目标文件
          await file.writeAsString(jsonEncode(_data), flush: true);
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
      _dirty = false;
    } catch (e) {
      debugPrint('[AppSettings] Save error: $e');
    }
  }

  // ---- Read methods (same signatures as SharedPreferences) ----

  String? getString(String key) => _data[key] as String?;

  int? getInt(String key) => _data[key] as int?;

  double? getDouble(String key) {
    final v = _data[key];
    if (v is int) return v.toDouble();
    return v as double?;
  }

  bool? getBool(String key) => _data[key] as bool?;

  List<String>? getStringList(String key) {
    final v = _data[key];
    if (v is List) return v.cast<String>();
    return null;
  }

  // ---- Write methods (same signatures as SharedPreferences) ----

  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    _dirty = true;
    await _saveToFile();
    return true;
  }

  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    _dirty = true;
    await _saveToFile();
    return true;
  }

  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    _dirty = true;
    await _saveToFile();
    return true;
  }

  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    _dirty = true;
    await _saveToFile();
    return true;
  }

  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    _dirty = true;
    await _saveToFile();
    return true;
  }

  Future<bool> remove(String key) async {
    _data.remove(key);
    _dirty = true;
    await _saveToFile();
    return true;
  }

  Future<bool> clear() async {
    _data.clear();
    _dirty = true;
    await _saveToFile();
    return true;
  }

  /// Force a save to disk (called on app exit / critical moments).
  Future<void> flush() async => _saveToFile();

  /// Batch update multiple key-value pairs and save once.
  /// This avoids multiple file writes when setting several values at once.
  Future<void> setValues(Map<String, dynamic> values) async {
    for (final entry in values.entries) {
      _data[entry.key] = entry.value;
    }
    _dirty = true;
    await _saveToFile();
  }

  /// Synchronous version for use in window close handlers.
  /// Uses synchronous file I/O to ensure data is written before window closes.
  void setValuesSync(Map<String, dynamic> values) {
    for (final entry in values.entries) {
      _data[entry.key] = entry.value;
    }
    _dirty = true;
    try {
      final file = File(_filePath);
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      file.writeAsStringSync(jsonEncode(_data), flush: true);
      _dirty = false;
    } catch (e) {
      // 忽略错误，窗口正在关闭
    }
  }

  /// Returns all keys currently stored.
  Set<String> get keys => _data.keys.toSet();

  /// Returns a copy of all settings as a Map.
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_data);

  /// Check if a key exists.
  bool containsKey(String key) => _data.containsKey(key);

  /// Reload from disk (useful after external import/restore).
  Future<void> reload() async => _loadFromFile();

  /// 根据游戏路径查找对应的整理目录
  /// 返回空字符串表示该游戏库未配置整理目录（不移动）
  static Future<String> getSortedPathForGame(String gamePath) async {
    final prefs = await AppSettings.load();
    final raw = prefs.getString('sorted_paths') ?? '';
    if (raw.isEmpty) return '';

    Map<String, String> mapping;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      mapping = decoded.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    } catch (_) {
      return '';
    }

    final normalizedGamePath = gamePath.replaceAll('/', '\\').toLowerCase();
    for (final entry in mapping.entries) {
      final libPath = entry.key.replaceAll('/', '\\').toLowerCase();
      final sortedPath = entry.value;
      if (sortedPath.isEmpty) continue;
      if (normalizedGamePath.startsWith(libPath)) {
        return entry.value;
      }
    }
    return '';
  }
}

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 300)});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
