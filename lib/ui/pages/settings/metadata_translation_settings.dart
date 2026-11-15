import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/metadata_translation_config.dart';
import '../../../core/services/metadata_translation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';

class MetadataTranslationSettings extends StatefulWidget {
  final MetadataTranslationConfig config;
  final ValueChanged<MetadataTranslationConfig> onChanged;
  final MetadataTranslationService? service;

  const MetadataTranslationSettings({
    super.key,
    required this.config,
    required this.onChanged,
    this.service,
  });

  @override
  State<MetadataTranslationSettings> createState() =>
      _MetadataTranslationSettingsState();
}

class _MetadataTranslationSettingsState
    extends State<MetadataTranslationSettings> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _prompt;
  Completer<void>? _cancellation;
  bool _busy = false;
  bool _hideKey = true;
  String? _result;
  int _testId = 0;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.config.baseUrl);
    _model = TextEditingController(text: widget.config.model);
    _apiKey = TextEditingController(text: widget.config.apiKey);
    _prompt = TextEditingController(text: widget.config.prompt);
  }

  @override
  void dispose() {
    _cancellation?.complete();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _prompt.dispose();
    super.dispose();
  }

  MetadataTranslationConfig _config({bool? enabled, String? provider}) =>
      MetadataTranslationConfig(
        enabled: enabled ?? widget.config.enabled,
        provider: provider ?? widget.config.provider,
        baseUrl: _baseUrl.text,
        model: _model.text,
        apiKey: _apiKey.text,
        prompt: _prompt.text,
      );

  void _change({bool? enabled, String? provider}) {
    _testId++;
    _cancellation?.complete();
    _cancellation = null;
    setState(() {
      _busy = false;
      _result = null;
    });
    widget.onChanged(_config(enabled: enabled, provider: provider));
  }

  Future<void> _test() async {
    if (_busy) return;
    final config = _config();
    final testId = ++_testId;
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    final seconds = MetadataTranslationService.connectionTestTimeout.inSeconds;
    setState(() {
      _busy = true;
      _result = '正在测试连接，最多等待 $seconds 秒…';
    });
    try {
      final translated = await (widget.service ?? MetadataTranslationService())
          .testConnection(config, cancelled: cancellation.future);
      if (!mounted || testId != _testId) return;
      setState(() => _result =
          '连接成功（${config.provider == 'llm' ? 'LLM' : 'Google'}）：$translated');
    } on TimeoutException {
      if (!mounted || testId != _testId) return;
      setState(() => _result = '连接测试超时（$seconds 秒），请检查网络或稍后重试');
    } catch (_) {
      if (!mounted || testId != _testId) return;
      setState(() => _result = '测试失败，请检查接口配置和网络');
    } finally {
      if (mounted && testId == _testId) {
        setState(() {
          _busy = false;
          _cancellation = null;
        });
      }
    }
  }

  Widget _field(TextEditingController controller, String label,
      {String? hint, bool secret = false, bool multiline = false}) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: GlassConstants.fontControl,
          color: AppTheme.getTextPrimary(context),
        );
    final secondaryStyle = textStyle?.copyWith(
      color: AppTheme.getTextSecondary(context),
    );
    return Padding(
      padding: const EdgeInsets.only(top: GlassConstants.spacingMedium),
      child: TextField(
        controller: controller,
        onChanged: (_) => _change(),
        obscureText: secret && _hideKey,
        minLines: multiline ? 4 : null,
        maxLines: multiline ? 8 : 1,
        keyboardType: multiline ? TextInputType.multiline : null,
        autocorrect: false,
        style: textStyle,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: secondaryStyle,
          hintText: hint,
          hintStyle: secondaryStyle,
          hintMaxLines: multiline ? 8 : null,
          floatingLabelBehavior: multiline
              ? FloatingLabelBehavior.always
              : FloatingLabelBehavior.auto,
          suffixIcon: secret
              ? IconButton(
                  tooltip: _hideKey ? '显示密钥' : '隐藏密钥',
                  onPressed: () => setState(() => _hideKey = !_hideKey),
                  icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off,
                      size: GlassConstants.iconControl),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: GlassConstants.fontBody,
          color: AppTheme.getTextSecondary(context),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const ValueKey('metadata-translation-enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text('刮削后自动翻译为简体中文',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: GlassConstants.fontControl,
                    color: AppTheme.getTextPrimary(context),
                  )),
          value: widget.config.enabled,
          onChanged: (value) => _change(enabled: value),
        ),
        Text('翻译标题、简介、特点、更新日志和标签，保留原文供详情页切换查看。', style: secondary),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : GlassConstants.animFast,
          curve: GlassConstants.animCurve,
          alignment: Alignment.topLeft,
          child: widget.config.enabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: GlassConstants.spacingMedium),
                    Text('翻译服务', style: secondary),
                    const SizedBox(height: GlassConstants.spacingSmall),
                    AppDropdown<String>(
                      key: const ValueKey('metadata-translation-provider'),
                      value: widget.config.provider,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'google', child: Text('Google 翻译')),
                        DropdownMenuItem(
                            value: 'llm', child: Text('LLM（OpenAI 兼容接口）')),
                      ],
                      onChanged: (value) {
                        if (value != null) _change(provider: value);
                      },
                    ),
                    const SizedBox(height: GlassConstants.spacingSmall),
                    Text(
                        widget.config.provider == 'llm'
                            ? '正式翻译时，LLM 不可用会尝试 Google；全部失败时保留原文。'
                            : 'Google 翻译无需密钥，使用应用的网络代理设置。',
                        style: secondary),
                    if (widget.config.provider == 'llm') ...[
                      _field(_baseUrl, '接口地址',
                          hint: 'https://服务地址/v1 或完整 chat/completions 地址'),
                      _field(_model, '模型名称'),
                      _field(_apiKey, 'API Key（服务无需鉴权时可留空）', secret: true),
                      _field(_prompt, '翻译 Prompt（留空使用默认）',
                          hint: MetadataTranslationConfig.defaultPrompt,
                          multiline: true),
                    ],
                    const SizedBox(height: GlassConstants.spacingMedium),
                    Text('启用后会将游戏文字发送到翻译服务。修改后点击设置页底部“保存”生效。',
                        style: secondary),
                    const SizedBox(height: GlassConstants.spacingSmall),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        key: const ValueKey('metadata-translation-test'),
                        onPressed: _busy ? null : _test,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: GlassConstants.iconSmall,
                                child: CircularProgressIndicator(
                                    strokeWidth: GlassConstants.spacingMicro))
                            : const Icon(Icons.network_check,
                                size: GlassConstants.iconAction),
                        label: const Text('测试连接'),
                      ),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: GlassConstants.spacingSmall),
                      Semantics(
                          liveRegion: true,
                          child: SelectableText(_result!, style: secondary)),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
