import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/services/metadata_translation_service.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
import 'package:hgame_manager/core/utils/media_reference_parser.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _llm = MetadataTranslationConfig(
  enabled: true,
  provider: 'llm',
  baseUrl: 'https://llm.example.test/v1',
  model: 'test-model',
  apiKey: 'test-secret',
);

http.Response _llmResponse(List<String> texts) => http.Response(
      jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': jsonEncode({'texts': texts}),
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('LLM 使用保存的自定义 Prompt，空白和旧设置使用默认 Prompt', () async {
    for (final prompt in [null, '', '   ', '使用自然的中文，保留人名。\n避免书面语。']) {
      final stored = MetadataTranslationConfig.fromMap({
        ..._llm.toMap(),
        'prompt': prompt,
      });
      final restored = MetadataTranslationConfig.fromMap(stored.toMap());
      final expected = prompt == null || prompt.trim().isEmpty
          ? MetadataTranslationConfig.defaultPrompt
          : prompt;
      expect(restored.effectivePrompt, expected);
      final service = MetadataTranslationService(
        clientFactory: () async => MockClient((request) async {
          final body = jsonDecode(request.body);
          final system = body['messages'][0]['content'] as String;
          expect(system, startsWith('$expected\n\n'));
          expect(system, contains('只返回 JSON 对象 {"texts":["译文"]}'));
          expect(system, contains('条目数量和顺序必须完全一致'));
          return _llmResponse(['探索']);
        }),
      );
      final result = await service.translate({'intro': 'Explore'}, restored);
      expect(result['intro'], '探索');
      expect(jsonEncode(result), isNot(contains(expected)));
    }
    final legacy = Map<String, dynamic>.from(_llm.toMap())..remove('prompt');
    expect(MetadataTranslationConfig.fromMap(legacy).effectivePrompt,
        MetadataTranslationConfig.defaultPrompt);
  });

  test('图片和视频的方括号目录路径不进入翻译请求', () async {
    const imagePath = r'C:\Games\[Group] Village\HGMDatas\images\scrape_1.png';
    const videoPath = r'C:\Games\[Group] Village\HGMDatas\images\video_1.mp4';
    final sent = <String>[];
    final service = MetadataTranslationService(
      clientFactory: () async => MockClient((request) async {
        final body = jsonDecode(request.body);
        final texts =
            (jsonDecode(body['messages'][1]['content'])['texts'] as List)
                .cast<String>();
        sent.addAll(texts);
        return _llmResponse(texts.map((text) => '探索').toList());
      }),
    );
    final source = {
      'intro': 'Explore\n[图片:$imagePath]\n[视频:$videoPath]',
      'features': 'Explore [图片:$imagePath] Explore',
    };
    final result = await service.translate(source, _llm);
    expect(sent, ['Explore']);
    expect(MediaReferenceParser.extractImagePaths(result['intro'] as String),
        [imagePath]);
    expect(MediaReferenceParser.extractVideoPaths(result['intro'] as String),
        [videoPath]);
    expect(result['features'], '探索 [图片:$imagePath] 探索');
    expect(MetadataTranslationService.originalFrom(result), source);
  });

  test('翻译 Markdown 链接文字并保留图片、代码和链接目标', () async {
    final sent = <String>[];
    final service = MetadataTranslationService(
      clientFactory: () async => MockClient((request) async {
        final body = jsonDecode(request.body);
        final texts =
            (jsonDecode(body['messages'][1]['content'])['texts'] as List)
                .cast<String>();
        sent.addAll(texts);
        return _llmResponse(texts.map((text) => '阅读指南').toList());
      }),
    );
    const source =
        '[Read the guide](https://example.test/guide_(new)?lang=en "Guide")\n'
        '![Cover](C:/Games/[Group]/cover_(1).png)\n'
        '`[Read the guide](https://example.test/code)`';
    final result = await service.translate({'intro': source}, _llm);
    expect(sent, ['Read the guide']);
    expect(
        result['intro'],
        '[阅读指南](https://example.test/guide_(new)?lang=en "Guide")\n'
        '![Cover](C:/Games/[Group]/cover_(1).png)\n'
        '`[Read the guide](https://example.test/code)`');
  });

  test('Google 也翻译仅含 Markdown 链接的正文', () async {
    final service = MetadataTranslationService(
      clientFactory: () async => MockClient((request) async {
        expect(request.url.queryParameters['q'], 'Read the guide');
        return http.Response(
            jsonEncode([
              [
                ['阅读指南', 'Read the guide'],
              ]
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final result = await service.translate(
      {'intro': '[Read the guide](https://example.test/guide)'},
      const MetadataTranslationConfig(enabled: true),
    );
    expect(result['intro'], '[阅读指南](https://example.test/guide)');
  });

  test('翻译保留目录分类标识、媒体引用和原文', () async {
    final source = {
      'title': 'A village',
      'intro': 'Explore\n[图片:C:\\Games\\A\\HGMDatas\\images\\scrape_1.jpg]',
      'intro_html':
          '<p>Explore</p><img src="https://images.example.test/a.jpg">',
      'tags': ['RPG', 'SLG', 'Adventure'],
      'series': 'RPG',
    };
    final before = jsonEncode(source);
    const translations = {
      'A village': '一个村庄',
      'Explore': '探索',
      'RPG': '角色扮演',
      'SLG': '策略',
      'Adventure': '冒险',
    };
    final service = MetadataTranslationService(
      clientFactory: () async => MockClient((request) async {
        final body = jsonDecode(request.body);
        final texts =
            (jsonDecode(body['messages'][1]['content'])['texts'] as List)
                .cast<String>();
        return _llmResponse(
            texts.map((text) => translations[text] ?? text).toList());
      }),
    );
    final translated = await service.translate(source, _llm);
    expect(translated['title'], '一个村庄');
    expect(translated['intro'],
        contains('[图片:C:\\Games\\A\\HGMDatas\\images\\scrape_1.jpg]'));
    expect(translated['intro_html'], contains('<p>探索</p>'));
    expect(translated['intro_html'],
        contains('src="https://images.example.test/a.jpg"'));
    expect(translated['tags'], ['RPG', 'SLG', '冒险']);
    expect(translated['series'], 'RPG');
    final tags = (translated['tags'] as List)
        .cast<String>()
        .map(
          (name) => Tag(name: name, type: Tag.typeCustom),
        )
        .toList();
    expect(ScrapeApplyService.resolveCategoryName(tags), 'RPG');
    expect(MetadataTranslationService.originalFrom(translated), source);
    expect(jsonEncode(source), before);
  });

  test('LLM 鉴权失败后 Google 兜底不携带密钥', () async {
    final notices = <String>[];
    final requests = <http.Request>[];
    final service = MetadataTranslationService(
      clientFactory: () async => MockClient((request) async {
        requests.add(request);
        if (request.url.host == 'llm.example.test') {
          expect(request.headers['authorization'], 'Bearer ${_llm.apiKey}');
          return http.Response('', 401);
        }
        expect(request.headers['authorization'], isNull);
        expect(request.url.queryParameters['q'], 'Explore');
        return http.Response(
            jsonEncode([
              [
                ['探索', 'Explore', null, null]
              ],
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final result = await service
        .translate({'intro': 'Explore'}, _llm, onNotice: notices.add);
    expect(requests.length, 2);
    expect(result['intro'], '探索');
    expect(result['translation']['provider'], 'google');
    expect(notices.single, contains('兜底'));
  });

  test('LLM 条目缺失且 Google 失败时返回完整原文', () async {
    final source = {'title': 'Village', 'intro': 'Explore'};
    final notices = <String>[];
    final service = MetadataTranslationService(
      clientFactory: () async => MockClient((request) async {
        if (request.url.host == 'llm.example.test') return _llmResponse(['村庄']);
        return http.Response('', 429);
      }),
    );
    final result = await service.translate(source, _llm, onNotice: notices.add);
    expect(identical(result, source), isTrue);
    expect(notices.length, 2);
    expect(notices.last, contains('保留原文'));
  });

  test('已有原文快照时重复调用不再次请求翻译', () async {
    final source = {
      'intro': '探索',
      'translation': {
        'original': {'intro': 'Explore'}
      },
    };
    final service = MetadataTranslationService(clientFactory: () async {
      fail('已有译文不应创建请求客户端');
    });
    expect(identical(await service.translate(source, _llm), source), isTrue);
  });
}
