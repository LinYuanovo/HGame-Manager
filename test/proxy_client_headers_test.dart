import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/proxy_client.dart';

void main() {
  group('自定义解析器请求头配置', () {
    test('旧配置没有 userAgent 时使用默认 UA', () {
      final configs = jsonEncode([
        {
          'domain': 'example.com',
          'title': '//h1',
          'cookie': 'sid=old',
        }
      ]);

      final userAgent = resolveScrapeUserAgentFromConfig(
        'https://example.com/post/1',
        configs,
      );

      expect(userAgent, defaultScrapeUserAgent);
    });

    test('匹配自定义解析器域名时使用站点级 UA', () {
      final configs = jsonEncode([
        {
          'domain': 'example.com',
          'title': '//h1',
          'userAgent': 'Custom-UA/1.0',
        }
      ]);

      final userAgent = resolveScrapeUserAgentFromConfig(
        'https://www.example.com/post/1',
        configs,
      );

      expect(userAgent, 'Custom-UA/1.0');
    });

    test('域名不匹配时不使用其他自定义站点 UA', () {
      final configs = jsonEncode([
        {
          'domain': 'example.com',
          'title': '//h1',
          'userAgent': 'Custom-UA/1.0',
        }
      ]);

      final userAgent = resolveScrapeUserAgentFromConfig(
        'https://other.example.net/post/1',
        configs,
      );

      expect(userAgent, defaultScrapeUserAgent);
    });
  });
}
