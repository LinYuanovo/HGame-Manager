import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/utils/app_settings.dart';
import '../../../core/models/rename_rule.dart';
import '../../theme/app_theme.dart';

class RenameManagerDialog extends StatefulWidget {
  const RenameManagerDialog({super.key});

  @override
  State<RenameManagerDialog> createState() => _RenameManagerDialogState();
}

class _RenameManagerDialogState extends State<RenameManagerDialog> {
  List<RenameRule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await AppSettings.load();
    final raw = prefs.getString(AppSettings.renameRulesKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(raw);
        _rules = list.map((m) => RenameRule.fromJson(m as Map<String, dynamic>)).toList();
        _loading = false;
        if (mounted) setState(() {});
        return;
      } catch (_) {
        // JSON解析失败时使用默认配置
      }
    }

    _rules = RenameRule.defaultRules();
    _loading = false;
    if (mounted) setState(() {});
  }

  Future<void> _saveConfig() async {
    final prefs = await AppSettings.load();
    final jsonStr = jsonEncode(_rules.map((e) => e.toJson()).toList());
    await prefs.setString(AppSettings.renameRulesKey, jsonStr);
  }

  void _resetToDefaults() {
    setState(() {
      _rules = RenameRule.defaultRules();
    });
  }

  /// 生成预览名称
  String _previewName() {
    final parts = <String>[];
    for (final rule in _rules) {
      if (!rule.enabled) continue;

      String value;
      switch (rule.id) {
        case 'game_id':
          value = 'RJ12345';
          break;
        case 'maker':
          value = '示例厂商';
          break;
        case 'series':
          value = '示例系列';
          break;
        case 'title':
          value = '示例游戏标题';
          break;
        case 'version':
          value = 'v1.0';
          break;
        default:
          value = '';
      }

      if (value.isNotEmpty) {
        parts.add(rule.wrapContent(value));
      }
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        height: 620,
        decoration: BoxDecoration(
          color: AppTheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
          border: Border.all(color: AppTheme.getBorderColor(context)),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildPreview(),
            Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _buildList()),
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
          Icon(Icons.drive_file_rename_outline, color: AppTheme.getPrimaryColor(context), size: 24),
          const SizedBox(width: 12),
          Text(
            '重命名规则管理',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundColor(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
        border: Border.all(color: AppTheme.getBorderColor(context).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('预览效果：', style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
          const SizedBox(height: 4),
          Text(
            _previewName(),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.getTextPrimary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _rules.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _rules.removeAt(oldIndex);
          _rules.insert(newIndex, item);
          for (int i = 0; i < _rules.length; i++) {
            _rules[i] = _rules[i].copyWith(order: i);
          }
        });
      },
      proxyDecorator: (Widget child, int index, Animation<double> animation) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
              child: child,
            ),
          ),
        );
      },
      itemBuilder: (context, index) {
        final rule = _rules[index];
        final isTitle = rule.id == 'title'; // 标题必须启用

        return Container(
          key: ValueKey(rule.id),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: rule.enabled
                ? AppTheme.getSurfaceColor(context)
                : AppTheme.getSurfaceColor(context).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            border: Border.all(
              color: rule.enabled
                  ? AppTheme.getBorderColor(context)
                  : AppTheme.getBorderColor(context).withValues(alpha: 0.5),
            ),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            ),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Icon(Icons.drag_handle, size: 20, color: AppTheme.getTextSecondary(context)),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  rule.name,
                  style: TextStyle(
                    fontSize: 15,
                    color: rule.enabled
                        ? AppTheme.getTextPrimary(context)
                        : AppTheme.getTextSecondary(context).withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 包裹符号输入
                SizedBox(
                  width: 40,
                  child: TextField(
                    controller: TextEditingController(text: rule.wrapBefore),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      hintText: '前',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _rules[index] = rule.copyWith(wrapBefore: value);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 40,
                  child: TextField(
                    controller: TextEditingController(text: rule.wrapAfter),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppTheme.getTextPrimary(context)),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      hintText: '后',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _rules[index] = rule.copyWith(wrapAfter: value);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // 启用开关
                Switch(
                  value: rule.enabled,
                  onChanged: isTitle
                      ? null
                      : (v) {
                          setState(() => _rules[index] = rule.copyWith(enabled: v));
                        },
                  activeThumbColor: AppTheme.getPrimaryColor(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _resetToDefaults,
            child: Text('恢复默认', style: TextStyle(color: AppTheme.getTextSecondary(context))),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () async {
              await _saveConfig();
              if (mounted) {
                Navigator.pop(context, true);
                AppTheme.showGlassToast(context, message: '重命名规则已保存', icon: Icons.check_circle, iconColor: AppTheme.successColor);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.getPrimaryColor(context),
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
