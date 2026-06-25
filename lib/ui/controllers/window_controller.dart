import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/utils/app_settings.dart';

class WindowController extends ChangeNotifier with WindowListener {
  final AppSettings _prefs;
  bool _isMaximized = false;
  Size? _lastNormalSize;
  Offset? _lastNormalPosition;

  static const double defaultWindowWidth = 1400;
  static const double defaultWindowHeight = 900;

  WindowController(this._prefs);

  bool get isMaximized => _isMaximized;

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    _isMaximized = _prefs.getBool('window_maximized') ?? false;

    // 如果之前是最大化，使用保存的尺寸（最大化时的实际尺寸）
    // 如果不是最大化，使用保存的普通尺寸
    var width = _prefs.getDouble('window_width') ?? defaultWindowWidth;
    var height = _prefs.getDouble('window_height') ?? defaultWindowHeight;
    var x = _prefs.getDouble('window_x');
    var y = _prefs.getDouble('window_y');

    if (width < 100 || width > 10000 || height < 100 || height > 10000) {
      width = defaultWindowWidth;
      height = defaultWindowHeight;
    }
    if (x != null && (x < -10000 || x > 10000)) x = null;
    if (y != null && (y < -10000 || y > 10000)) y = null;

    _lastNormalSize = Size(width, height);
    if (x != null && y != null) {
      _lastNormalPosition = Offset(x, y);
    }

    // 设置窗口
    await windowManager.setMinimumSize(const Size(1200, 700));
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setIcon('windows/runner/resources/app_icon.ico');
    await windowManager.setSize(Size(width, height));
    if (x != null && y != null) {
      await windowManager.setPosition(Offset(x, y));
    }
    await windowManager.show();
    await windowManager.focus();
  }

  void _saveWindowSettings() {
    try {
      _prefs.setValuesSync({
        'window_maximized': _isMaximized,
        'window_width': _lastNormalSize?.width ?? defaultWindowWidth,
        'window_height': _lastNormalSize?.height ?? defaultWindowHeight,
        'window_x': _lastNormalPosition?.dx ?? 0,
        'window_y': _lastNormalPosition?.dy ?? 0,
      });
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  Future<void> close() async {
    _saveWindowSettings();
    exit(0);
  }

  Future<void> toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> minimize() async {
    await windowManager.minimize();
  }

  Future<void> startDragging() async {
    await windowManager.startDragging();
  }

  @override
  void onWindowClose() {
    _saveWindowSettings();
    exit(0);
  }

  @override
  void onWindowResize() async {
    final isMax = await windowManager.isMaximized();
    if (!isMax) {
      _lastNormalSize = await windowManager.getSize();
      _lastNormalPosition = await windowManager.getPosition();
    }
  }

  @override
  void onWindowMaximize() async {
    _isMaximized = true;
    // 保存最大化后的实际尺寸
    _lastNormalSize = await windowManager.getSize();
    _lastNormalPosition = await windowManager.getPosition();
    _saveWindowSettings();
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() async {
    _isMaximized = false;
    _saveWindowSettings();
    notifyListeners();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }
}
