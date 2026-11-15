import 'dart:convert';

import '../utils/app_settings.dart';

class MetadataTranslationConfig {
  static const settingsKey = 'metadata_translation';
  static const defaultPrompt = '你是游戏元信息翻译器。将输入文字逐项翻译为简体中文。'
      '保留专有名词、数字和格式，已是简体中文的内容原样返回。';

  final bool enabled;
  final String provider;
  final String baseUrl;
  final String model;
  final String apiKey;
  final String prompt;

  const MetadataTranslationConfig({
    this.enabled = false,
    this.provider = 'google',
    this.baseUrl = '',
    this.model = '',
    this.apiKey = '',
    this.prompt = '',
  });

  factory MetadataTranslationConfig.fromMap(Map<String, dynamic> json) {
    return MetadataTranslationConfig(
      enabled: json['enabled'] == true,
      provider: json['provider'] == 'llm' ? 'llm' : 'google',
      baseUrl: json['base_url'] as String? ?? '',
      model: json['model'] as String? ?? '',
      apiKey: json['api_key'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'provider': provider,
        'base_url': baseUrl.trim(),
        'model': model.trim(),
        'api_key': apiKey.trim(),
        'prompt': prompt.trim(),
      };

  String get effectivePrompt =>
      prompt.trim().isEmpty ? defaultPrompt : prompt.trim();

  Uri get completionsUri {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        model.trim().isEmpty) {
      throw const FormatException('请填写有效的 LLM 接口地址和模型名称');
    }
    var endpointPath = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (!endpointPath.endsWith('/chat/completions')) {
      if (endpointPath.isEmpty) endpointPath = '/v1';
      endpointPath += '/chat/completions';
    }
    return uri.replace(path: endpointPath);
  }

  static MetadataTranslationConfig fromSettings(AppSettings settings) {
    try {
      final json = jsonDecode(settings.getString(settingsKey) ?? '{}');
      return MetadataTranslationConfig.fromMap(json as Map<String, dynamic>);
    } catch (_) {
      return const MetadataTranslationConfig();
    }
  }
}
