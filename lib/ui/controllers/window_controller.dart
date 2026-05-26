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

    final width = _prefs.getDouble('window_width') ?? defaultWindowWidth;
    final height = _prefs.getDouble('window_height') ?? defaultWindowHeight;
    final x = _prefs.getDouble('window_x');
    final y = _prefs.getDouble('window_y');
    _isMaximized = _prefs.getBool('window_maximized') ?? false;

    await windowManager.setMinimumSize(const Size(1200, 700));

    if (_isMaximized) {
      await windowManager.setSize(Size(width, height));
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      await windowManager.maximize();
    } else {
      await windowManager.setSize(Size(width, height));
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
    }

    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setIcon('windows/runner/resources/app_icon.ico');
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> close() async {
    final isMax = await windowManager.isMaximized();
    Size size;
    Offset position;

    if (isMax && _lastNormalSize != null) {
      size = _lastNormalSize!;
      position = _lastNormalPosition ?? await windowManager.getPosition();
    } else {
      size = await windowManager.getSize();
      position = await windowManager.getPosition();
    }

    await _prefs.setBool('window_maximized', isMax);
    await _prefs.setDouble('window_width', size.width);
    await _prefs.setDouble('window_height', size.height);
    await _prefs.setDouble('window_x', position.dx);
    await _prefs.setDouble('window_y', position.dy);

    await windowManager.destroy();
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
  void onWindowClose() async {
    await close();
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
