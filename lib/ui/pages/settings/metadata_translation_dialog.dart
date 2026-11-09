import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/models/metadata_translation_config.dart';
import '../../../core/services/metadata_translation_service.dart';
import '../../../core/utils/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';

class MetadataTranslationDialog extends StatefulWidget {
  final AppSettings settings;

  const MetadataTranslationDialog({super.key, required this.settings});

  @override
  State<MetadataTranslationDialog> createState() =>
      _MetadataTranslationDialogState();
}

class _MetadataTranslationDialogState extends State<MetadataTranslationDialog> {
  late bool _enabled;
  late String _provider;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  bool _busy = false;
  bool _hideKey = true;
  String? _result;

  @override
  void initState() {
    super.initState();
    final config = MetadataTranslationConfig.fromSettings(widget.settings);
    _enabled = config.enabled;
    _provider = config.provider;
    _baseUrl = TextEditingController(text: config.baseUrl);
    _model = TextEditingController(text: config.model);
    _apiKey = TextEditingController(text: config.apiKey);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  MetadataTranslationConfig _config({bool? enabled}) =>
      MetadataTranslationConfig(
        enabled: enabled ?? _enabled,
        provider: _provider,
        baseUrl: _baseUrl.text,
        model: _model.text,
        apiKey: _apiKey.text,
      );

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = '正在测试翻译连接…';
    });
    final notices = <String>[];
    try {
      final result = await MetadataTranslationService().translate(
        {'intro': 'Explore a peaceful village and meet new friends.'},
        _config(enabled: true),
        onNotice: (message) {
          notices.add(message);
          if (mounted) setState(() => _result = notices.join('\n'));
        },
      );
      if (!mounted) return;
      final translation = result[MetadataTranslationService.metadataKey];
      setState(() => _result = [
            ...notices,
            if (translation != null)
              '连接成功（${translation['provider'] == 'llm' ? 'LLM' : 'Google'}）：${result['intro']}',
          ].join('\n'));
    } catch (_) {
      if (mounted) setState(() => _result = '测试失败，请检查接口配置和网络');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final config = _config();
    if (config.enabled && config.provider == 'llm') {
      try {
        config.completionsUri;
      } catch (_) {
        setState(() => _result = '请填写有效的 LLM 接口地址和模型名称');
        return;
      }
    }
    setState(() => _busy = true);
    await widget.settings.setString(
        MetadataTranslationConfig.settingsKey, jsonEncode(config.toMap()));
    await widget.settings.flush();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, bool secret = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: GlassConstants.spacingMedium),
      child: TextField(
        controller: controller,
        enabled: !_busy,
        obscureText: secret && _hideKey,
        autocorrect: false,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.getTextPrimary(context),
            ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: AppTheme.getSurfaceColor(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassConstants.radiusSmall),
            borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
          ),
          suffixIcon: secret
              ? IconButton(
                  tooltip: _hideKey ? '显示密钥' : '隐藏密钥',
                  onPressed:
                      _busy ? null : () => setState(() => _hideKey = !_hideKey),
                  icon: Icon(
                    _hideKey ? Icons.visibility : Icons.visibility_off,
                    color: AppTheme.getTextSecondary(context),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: AppTheme.getSurfaceColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassConstants.radiusLarge),
        ),
        title: const Text('元信息自动翻译'),
        content: SizedBox(
          width: GlassConstants.dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('刮削后自动翻译为简体中文'),
                  activeThumbColor: AppTheme.getPrimaryColor(context),
                  value: _enabled,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                Text(
                  '翻译标题、简介、特点、更新日志和标签。原文随游戏保存，可在详情页切换查看。启用后会将这些文字发送到所选翻译服务。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.getTextSecondary(context),
                      ),
                ),
                const SizedBox(height: GlassConstants.spacingMedium),
                AppDropdown<String>(
                  value: _provider,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'google', child: Text('Google 翻译')),
                    DropdownMenuItem(
                        value: 'llm', child: Text('LLM（OpenAI 兼容接口）')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _provider = value!;
                            _result = null;
                          }),
                ),
                const SizedBox(height: GlassConstants.spacingMedium),
                Text(
                  _provider == 'llm'
                      ? 'LLM 不可用时会尝试 Google 并提示；全部失败时保留原文。'
                      : 'Google 翻译无需密钥，使用应用的网络代理设置。网络不可达或服务限流时会提示并保留原文。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.getTextSecondary(context),
                      ),
                ),
                if (_provider == 'llm') ...[
                  _field(_baseUrl, '接口地址',
                      hint: 'https://服务地址/v1 或完整 chat/completions 地址'),
                  _field(_model, '模型名称'),
                  _field(_apiKey, 'API Key（服务无需鉴权时可留空）', secret: true),
                ],
                if (_result != null) ...[
                  const SizedBox(height: GlassConstants.spacingMedium),
                  Semantics(
                    liveRegion: true,
                    child: SelectableText(_result!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.getTextPrimary(context),
                            )),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : _test, child: const Text('测试连接')),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.getPrimaryColor(context),
              foregroundColor: AppTheme.getTextColorOnPrimary(context),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
