import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/metadata_translation_config.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/services/metadata_translation_service.dart';
import 'package:hgame_manager/core/services/scrape_apply_service.dart';
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
