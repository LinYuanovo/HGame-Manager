import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/utils/app_settings.dart';
import '../../core/database/database_helper.dart';

class WindowController extends ChangeNotifier with WindowListener {
  final AppSettings _prefs;
  bool _isMaximized = false;
  Size? _lastNormalSize;
  Offset? _lastNormalPosition;
  bool _isClosing = false;

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

    // 验证窗口大小有效性
    if (width < 100 || width > 10000 || height < 100 || height > 10000) {
      width = defaultWindowWidth;
      height = defaultWindowHeight;
    }

    // 验证窗口位置有效性（防止超出屏幕范围）
    if (x != null && (x < -10000 || x > 10000)) {
      x = null;
    }
    if (y != null && (y < -10000 || y > 10000)) {
      y = null;
    }

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
    if (_isClosing) return;
    _isClosing = true;

    try {
      final isMax = _isMaximized;
      final size = _lastNormalSize ?? Size(defaultWindowWidth, defaultWindowHeight);
      final position = _lastNormalPosition ?? Offset.zero;

      // 同步保存设置（使用 flush 确保立即写入）
      _prefs.setValues({
        'window_maximized': isMax,
        'window_width': size.width,
        'window_height': size.height,
        'window_x': position.dx,
        'window_y': position.dy,
      });

      // 关闭数据库
      await DatabaseHelper.close();

      // 使用原生方式退出应用，兼容 Windows 7
      await SystemNavigator.pop();
    } catch (e) {
      debugPrint('Error during close: $e');
      // 强制退出
      exit(0);
    }
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
