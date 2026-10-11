import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// 攻略浮窗状态（位置/大小/置顶/滚动位置）的独立存储。
///
/// 存储于 `<exe_dir>/hgame_manager_data/guide_window_state.json`，
/// 与 settings.json 分离，避免主窗口与浮窗子窗口并发写同一文件。
class GuideWindowState {
  GuideWindowState();

  double? x;
  double? y;
  double? width;
  double? height;
  bool alwaysOnTop = false;

  /// 窗口透明度（null 表示 1.0 不透明）
  double? opacity;

  /// 攻略文字大小覆盖（null 表示跟随应用详情页字号设置）
  double? fontSize;

  /// 各游戏的滚动位置（0.0-1.0），key 为游戏标识（id 或标题）
  final Map<String, double> scrollPositions = {};

  static const double defaultWidth = 480;
  static const double defaultHeight = 640;
  static const double minWidth = 320;
  static const double minHeight = 240;

  static Future<String> get _filePath async =>
      '${await AppPaths.rootDir}${Platform.pathSeparator}guide_window_state.json';

  static Future<GuideWindowState> load() async {
    final state = GuideWindowState();
    try {
      final file = File(await _filePath);
      if (!await file.exists()) return state;
      final raw = await file.readAsString();
      if (raw.isEmpty) return state;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state.x = (json['x'] as num?)?.toDouble();
      state.y = (json['y'] as num?)?.toDouble();
      state.width = (json['width'] as num?)?.toDouble();
      state.height = (json['height'] as num?)?.toDouble();
      state.alwaysOnTop = json['alwaysOnTop'] as bool? ?? false;
      state.opacity = (json['opacity'] as num?)?.toDouble();
      state.fontSize = (json['fontSize'] as num?)?.toDouble();
      final positions = json['scrollPositions'];
      if (positions is Map) {
        for (final entry in positions.entries) {
          final value = entry.value;
          if (value is num) {
            state.scrollPositions[entry.key.toString()] = value.toDouble();
          }
        }
      }
      // 校验尺寸合法性，异常值回退默认
      if (state.width != null &&
          (state.width! < minWidth || state.width! > 10000)) {
        state.width = null;
      }
      if (state.height != null &&
          (state.height! < minHeight || state.height! > 10000)) {
        state.height = null;
      }
      if (state.x != null && (state.x! < -10000 || state.x! > 10000)) {
        state.x = null;
      }
      if (state.y != null && (state.y! < -10000 || state.y! > 10000)) {
        state.y = null;
      }
    } catch (e) {
      debugPrint('[GuideWindow] state load error: $e');
    }
    return state;
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'alwaysOnTop': alwaysOnTop,
        'opacity': opacity,
        'fontSize': fontSize,
        'scrollPositions': scrollPositions,
      };

  Future<void> save() async {
    try {
      final file = File(await _filePath);
      await file.writeAsString(jsonEncode(toJson()), flush: true);
    } catch (e) {
      debugPrint('[GuideWindow] state save error: $e');
    }
  }

  double scrollRatioFor(String gameKey) => scrollPositions[gameKey] ?? 0;
}
