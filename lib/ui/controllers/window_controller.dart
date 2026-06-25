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

    var width = _prefs.getDouble('window_width') ?? defaultWindowWidth;
    var height = _prefs.getDouble('window_height') ?? defaultWindowHeight;
    var x = _prefs.getDouble('window_x');
    var y = _prefs.getDouble('window_y');
    _isMaximized = _prefs.getBool('window_maximized') ?? false;

    if (width < 100 || width > 10000 || height < 100 || height > 10000) {
      width = defaultWindowWidth;
      height = defaultWindowHeight;
    }

    if (x != null && (x < -10000 || x > 10000)) {
      x = null;
    }
    if (y != null && (y < -10000 || y > 10000)) {
      y = null;
    }

    WindowOptions windowOptions = WindowOptions(
      size: Size(width, height),
      minimumSize: const Size(1200, 700),
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setIcon('windows/runner/resources/app_icon.ico');
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      await windowManager.show();
      await windowManager.focus();
      if (_isMaximized) {
        await windowManager.maximize();
      }
    });
  }

  void _saveWindowSettings() {
    try {
      final isMax = _isMaximized;
      final size = _lastNormalSize ?? Size(defaultWindowWidth, defaultWindowHeight);
      final position = _lastNormalPosition ?? Offset.zero;

      _prefs.setValuesSync({
        'window_maximized': isMax,
        'window_width': size.width,
        'window_height': size.height,
        'window_x': position.dx,
        'window_y': position.dy,
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
  void onWindowMaximize() {
    _isMaximized = true;
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    _isMaximized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }
}
