import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../../core/providers/providers.dart';
import '../../../core/services/guide_window_service.dart';
import '../../theme/app_theme.dart';

/// 攻略浮窗全局快捷键管理弹窗
class GuideHotkeyDialog extends ConsumerStatefulWidget {
  const GuideHotkeyDialog({super.key});

  @override
  ConsumerState<GuideHotkeyDialog> createState() => _GuideHotkeyDialogState();
}

class _GuideHotkeyDialogState extends ConsumerState<GuideHotkeyDialog> {
  static const _actions = [
    (key: GuideWindowService.hotkeyToggleKey, label: '开启/关闭浮窗'),
    (key: GuideWindowService.hotkeyPinKey, label: '置顶浮窗'),
    (key: GuideWindowService.hotkeyScrollUpKey, label: '上滑'),
    (key: GuideWindowService.hotkeyScrollDownKey, label: '下滑'),
  ];

  final Map<String, HotKey> _hotkeys = {};

  /// 正在录制快捷键的功能键（null 表示未在录制）
  String? _recordingKey;

  /// 录制过程中当前按住的修饰键（仅用于展示）
  Set<HotKeyModifier> _heldModifiers = {};

  GuideWindowService get _service => ref.read(guideWindowServiceProvider);

  @override
  void initState() {
    super.initState();
    for (final action in _actions) {
      _hotkeys[action.key] = _service.loadHotkey(action.key);
    }
  }

  @override
  void dispose() {
    if (_recordingKey != null) {
      HardwareKeyboard.instance.removeHandler(_recordKeyEvent);
    }
    super.dispose();
  }

  bool _isSameHotkey(HotKey a, HotKey b) {
    final modifiersA = (a.modifiers ?? []).map((m) => m.name).toList()..sort();
    final modifiersB = (b.modifiers ?? []).map((m) => m.name).toList()..sort();
    return a.physicalKey.usbHidUsage == b.physicalKey.usbHidUsage &&
        modifiersA.join(',') == modifiersB.join(',');
  }

  // ---- 录制逻辑 ----
  // 自实现录制：修饰键（Ctrl/Shift/Alt 等）按下时不立即完成，
  // 直到按下一个普通键才组合完成，支持 Ctrl+A 这类组合键。

  void _startRecording(String storageKey) {
    if (_recordingKey != null) {
      HardwareKeyboard.instance.removeHandler(_recordKeyEvent);
    }
    setState(() {
      _recordingKey = storageKey;
      _heldModifiers = {};
    });
    HardwareKeyboard.instance.addHandler(_recordKeyEvent);
  }

  void _stopRecording() {
    HardwareKeyboard.instance.removeHandler(_recordKeyEvent);
    if (mounted) {
      setState(() {
        _recordingKey = null;
        _heldModifiers = {};
      });
    }
  }

  bool _recordKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return true; // 录制期间吞掉，避免按键泄露到其他控件
    final key = event.physicalKey;
    // Esc 取消录制
    if (key == PhysicalKeyboardKey.escape) {
      _stopRecording();
      return true;
    }
    final isModifier = HotKeyModifier.values
        .any((m) => m.physicalKeys.contains(key));
    if (isModifier) {
      // 修饰键按下仅更新展示，不完成录制
      setState(() => _heldModifiers = _currentlyHeldModifiers());
      return true;
    }
    final modifiers = _currentlyHeldModifiers();
    if (modifiers.isEmpty) {
      // 全局热键必须包含修饰键，否则会劫持所有普通按键输入
      AppTheme.showGlassToast(
        context,
        message: '请至少包含一个修饰键（Ctrl / Shift / Alt）',
        icon: Icons.warning_amber,
        iconColor: AppTheme.warningColor,
      );
      return true; // 继续录制
    }
    final hotKey = HotKey(key: key, modifiers: modifiers.toList());
    final storageKey = _recordingKey!;
    _stopRecording();
    _onHotkeyRecorded(storageKey, hotKey);
    return true;
  }

  Set<HotKeyModifier> _currentlyHeldModifiers() {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return HotKeyModifier.values
        .where((m) => m.physicalKeys.any(pressed.contains))
        .toSet();
  }

  Future<void> _onHotkeyRecorded(String storageKey, HotKey hotKey) async {
    // 与其他功能的快捷键冲突时拒绝
    final conflict = _actions.any((action) =>
        action.key != storageKey &&
        _hotkeys[action.key] != null &&
        _isSameHotkey(_hotkeys[action.key]!, hotKey));
    if (conflict) {
      AppTheme.showGlassToast(
        context,
        message: '该快捷键已被其他功能占用',
        icon: Icons.warning_amber,
        iconColor: AppTheme.warningColor,
      );
      return;
    }
    setState(() => _hotkeys[storageKey] = hotKey);
    await _service.saveHotkey(storageKey, hotKey);
    await _service.registerHotkeys();
  }

  Future<void> _resetToDefaults() async {
    _stopRecording();
    await _service.resetHotkeys();
    await _service.registerHotkeys();
    setState(() {
      final defaults = GuideWindowService.defaultHotkeys();
      for (final action in _actions) {
        _hotkeys[action.key] = defaults[action.key]!;
      }
    });
    if (mounted) {
      AppTheme.showGlassToast(
        context,
        message: '已恢复默认快捷键',
        icon: Icons.check_circle_outline,
        iconColor: AppTheme.successColor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(color: AppTheme.getBorderColor(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '快捷键为全局热键，游戏中也可使用。点击「修改」后，按住修饰键（Ctrl 等）再按目标键完成组合，Esc 取消。',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.getTextSecondary(context)
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ..._actions.map(_buildHotkeyRow),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(Icons.keyboard_outlined,
              color: AppTheme.getPrimaryColor(context), size: 24),
          const SizedBox(width: 12),
          Text(
            '攻略浮窗快捷键',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const Spacer(),
          IconButton(
            icon:
                Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHotkeyRow(
      ({String key, String label}) action) {
    final hotkey = _hotkeys[action.key]!;
    final isRecording = _recordingKey == action.key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              action.label,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
          ),
          Expanded(
            child: isRecording
                ? _buildRecordingIndicator()
                : HotKeyVirtualView(hotKey: hotkey),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () =>
                isRecording ? _stopRecording() : _startRecording(action.key),
            child: Text(
              isRecording ? '取消' : '修改',
              style: TextStyle(color: AppTheme.getPrimaryColor(context)),
            ),
          ),
        ],
      ),
    );
  }

  /// 录制中的展示：已按住的修饰键 + 提示
  Widget _buildRecordingIndicator() {
    final children = <Widget>[];
    for (final modifier in _heldModifiers) {
      children.add(_buildKeyChip(modifier.physicalKeys.first.keyLabel));
      children.add(Text(' + ',
          style: TextStyle(color: AppTheme.getTextSecondary(context))));
    }
    children.add(Text(
      _heldModifiers.isEmpty ? '请按下按键组合…' : '…',
      style: TextStyle(
        fontSize: 12,
        color: AppTheme.getTextSecondary(context),
        fontStyle: FontStyle.italic,
      ),
    ));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _buildKeyChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _resetToDefaults,
            child: Text('恢复默认',
                style:
                    TextStyle(color: AppTheme.getTextSecondary(context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: AppTheme.getTextColorOnPrimary(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
