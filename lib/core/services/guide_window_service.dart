import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../models/models.dart';
import '../utils/app_settings.dart';

/// 攻略浮窗内容载荷
class GuideWindowPayload {
  final String gameKey;
  final String title;
  final String content;

  const GuideWindowPayload({
    required this.gameKey,
    required this.title,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'gameKey': gameKey,
        'title': title,
        'content': content,
      };
}

/// 攻略浮窗主窗口侧管理服务（单例）。
///
/// 负责浮窗子窗口的创建/更新/关闭、滚动与置顶指令转发，
/// 以及 4 个全局快捷键（可在设置中自定义）的注册。
class GuideWindowService {
  GuideWindowService(this._prefs);

  final AppSettings _prefs;

  static const String hotkeyToggleKey = 'guide_window_hotkey_toggle';
  static const String hotkeyPinKey = 'guide_window_hotkey_pin';
  static const String hotkeyScrollUpKey = 'guide_window_hotkey_scroll_up';
  static const String hotkeyScrollDownKey = 'guide_window_hotkey_scroll_down';

  /// 是否注册全局快捷键的总开关（默认开启）
  static const String hotkeysEnabledKey = 'guide_window_hotkeys_enabled';

  /// 全局滚动步长（像素）
  static const double scrollStep = 300;

  String? _mainWindowId;
  String? _windowId;
  GuideWindowPayload? _lastPayload;
  StreamSubscription? _windowsChangedSub;
  bool _initialized = false;

  bool get isOpen => _windowId != null;

  /// 主窗口启动后调用一次：建立子窗口消息通道并注册全局快捷键
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final controller = await WindowController.fromCurrentEngine();
      _mainWindowId = controller.windowId;
      await controller.setWindowMethodHandler(_onSubWindowCall);
      _windowsChangedSub = onWindowsChanged.listen((_) => _syncWindowId());
      await registerHotkeys();
    } catch (e) {
      debugPrint('[GuideWindow] initialize error: $e');
    }
  }

  /// 子窗口发来的消息
  Future<dynamic> _onSubWindowCall(MethodCall call) async {
    if (call.method == 'guideWindowClosed') {
      _windowId = null;
    }
    return null;
  }

  /// 窗口列表变化时校验浮窗是否仍然存在（如 Alt+F4 被系统直接关闭）
  Future<void> _syncWindowId() async {
    if (_windowId == null) return;
    try {
      final all = await WindowController.getAll();
      if (!all.any((c) => c.windowId == _windowId)) {
        _windowId = null;
      }
    } catch (_) {}
  }

  /// 打开浮窗显示指定游戏攻略；浮窗已打开时切换内容并置于前台
  Future<void> openOrUpdate(Game game) async {
    final content = game.guide ?? '';
    if (content.isEmpty) return;
    final payload = GuideWindowPayload(
      gameKey: game.id?.toString() ?? game.path,
      title: game.title ?? '',
      content: content,
    );
    _lastPayload = payload;
    final existingId = _windowId;
    if (existingId != null) {
      try {
        final controller = WindowController.fromWindowId(existingId);
        await controller.invokeMethod('updateContent', payload.toJson());
        await controller.invokeMethod('focus');
        return;
      } catch (_) {
        _windowId = null;
      }
    }
    await _createWindow(payload);
  }

  /// CTRL+1：开启/关闭浮窗（重开时使用最后一次显示的内容）
  Future<void> toggleOpenClose() async {
    if (_windowId != null) {
      await closeWindow();
      return;
    }
    final payload = _lastPayload;
    if (payload == null) return;
    await _createWindow(payload);
  }

  Future<void> closeWindow() async {
    final id = _windowId;
    _windowId = null;
    if (id == null) return;
    try {
      await WindowController.fromWindowId(id).invokeMethod('closeWindow');
    } catch (_) {}
  }

  /// CTRL+2：切换浮窗置顶
  Future<void> togglePin() async {
    await _invokeOnWindow('togglePin');
  }

  /// CTRL+↑/↓：滚动浮窗内容
  Future<void> scroll(double delta) async {
    await _invokeOnWindow('scroll', {'delta': delta});
  }

  Future<void> _invokeOnWindow(String method, [dynamic arguments]) async {
    final id = _windowId;
    if (id == null) return;
    try {
      await WindowController.fromWindowId(id).invokeMethod(method, arguments);
    } catch (_) {}
  }

  Future<void> _createWindow(GuideWindowPayload payload) async {
    try {
      final controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({
            ...payload.toJson(),
            'mainWindowId': _mainWindowId ?? '',
          }),
        ),
      );
      _windowId = controller.windowId;
    } catch (e) {
      debugPrint('[GuideWindow] create window error: $e');
      _windowId = null;
    }
  }

  // ---- 快捷键配置 ----

  /// 默认快捷键：CTRL+1 开关、CTRL+2 置顶、CTRL+↑/↓ 滚动
  static Map<String, HotKey> defaultHotkeys() => {
        hotkeyToggleKey: HotKey(
          key: PhysicalKeyboardKey.digit1,
          modifiers: [HotKeyModifier.control],
        ),
        hotkeyPinKey: HotKey(
          key: PhysicalKeyboardKey.digit2,
          modifiers: [HotKeyModifier.control],
        ),
        hotkeyScrollUpKey: HotKey(
          key: PhysicalKeyboardKey.arrowUp,
          modifiers: [HotKeyModifier.control],
        ),
        hotkeyScrollDownKey: HotKey(
          key: PhysicalKeyboardKey.arrowDown,
          modifiers: [HotKeyModifier.control],
        ),
      };

  /// 读取某功能的快捷键配置（未配置时返回默认值）
  HotKey loadHotkey(String storageKey) {
    final raw = _prefs.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return HotKey.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return defaultHotkeys()[storageKey]!;
  }

  Future<void> saveHotkey(String storageKey, HotKey hotKey) async {
    await _prefs.setString(storageKey, jsonEncode(hotKey.toJson()));
  }

  Future<void> resetHotkeys() async {
    for (final key in defaultHotkeys().keys) {
      await _prefs.remove(key);
    }
  }

  bool get hotkeysEnabled => _prefs.getBool(hotkeysEnabledKey) ?? true;

  /// 按当前配置重新注册全部全局快捷键；总开关关闭时反注册全部
  Future<void> registerHotkeys() async {
    try {
      await hotKeyManager.unregisterAll();
      if (!hotkeysEnabled) return;
      await hotKeyManager.register(
        loadHotkey(hotkeyToggleKey),
        keyDownHandler: (_) => toggleOpenClose(),
      );
      await hotKeyManager.register(
        loadHotkey(hotkeyPinKey),
        keyDownHandler: (_) => togglePin(),
      );
      await hotKeyManager.register(
        loadHotkey(hotkeyScrollUpKey),
        keyDownHandler: (_) => scroll(-scrollStep),
      );
      await hotKeyManager.register(
        loadHotkey(hotkeyScrollDownKey),
        keyDownHandler: (_) => scroll(scrollStep),
      );
    } catch (e) {
      debugPrint('[GuideWindow] register hotkeys error: $e');
    }
  }

  Future<void> dispose() async {
    await _windowsChangedSub?.cancel();
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
}
