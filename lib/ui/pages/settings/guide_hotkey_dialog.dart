import 'package:flutter/material.dart';
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

  GuideWindowService get _service => ref.read(guideWindowServiceProvider);

  @override
  void initState() {
    super.initState();
    for (final action in _actions) {
      _hotkeys[action.key] = _service.loadHotkey(action.key);
    }
  }

  bool _isSameHotkey(HotKey a, HotKey b) {
    final modifiersA = (a.modifiers ?? []).map((m) => m.name).toList()..sort();
    final modifiersB = (b.modifiers ?? []).map((m) => m.name).toList()..sort();
    return a.physicalKey.usbHidUsage == b.physicalKey.usbHidUsage &&
        modifiersA.join(',') == modifiersB.join(',');
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
      setState(() => _recordingKey = null);
      return;
    }
    setState(() {
      _hotkeys[storageKey] = hotKey;
      _recordingKey = null;
    });
    await _service.saveHotkey(storageKey, hotKey);
    await _service.registerHotkeys();
  }

  Future<void> _resetToDefaults() async {
    await _service.resetHotkeys();
    await _service.registerHotkeys();
    setState(() {
      final defaults = GuideWindowService.defaultHotkeys();
      for (final action in _actions) {
        _hotkeys[action.key] = defaults[action.key]!;
      }
      _recordingKey = null;
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
                '快捷键为全局热键，游戏中也可使用。点击「修改」后按下新的按键组合即可。',
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
                ? HotKeyRecorder(
                    initalHotKey: hotkey,
                    onHotKeyRecorded: (recorded) =>
                        _onHotkeyRecorded(action.key, recorded),
                  )
                : HotKeyVirtualView(hotKey: hotkey),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(
                () => _recordingKey = isRecording ? null : action.key),
            child: Text(
              isRecording ? '取消' : '修改',
              style: TextStyle(color: AppTheme.getPrimaryColor(context)),
            ),
          ),
        ],
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
