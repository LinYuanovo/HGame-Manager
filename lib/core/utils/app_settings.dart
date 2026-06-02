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
          _data = jsonDecode(raw) as Map<String, dynamic>;
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
      final tempFile = File('$_filePath.tmp');
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

  /// Returns all keys currently stored.
  Set<String> get keys => _data.keys.toSet();

  /// Returns a copy of all settings as a Map.
  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_data);

  /// Check if a key exists.
  bool containsKey(String key) => _data.containsKey(key);

  /// Reload from disk (useful after external import/restore).
  Future<void> reload() async => _loadFromFile();
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
