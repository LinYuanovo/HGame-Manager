import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/proxy_client.dart';

void main() {
  test('维咔 Authorization 可从 Bearer、JWT 或请求头文本中提取', () {
    const token = 'aaa.bbb.ccc';
    expect(extractVikacgAuthorization('Bearer $token'), 'Bearer $token');
    expect(extractVikacgAuthorization('authorization: Bearer $token'),
        'Bearer $token');
    expect(extractVikacgAuthorization('cookie=x; authorization=$token'),
        'Bearer $token');
    expect(extractVikacgAuthorization('cookie=x'), isEmpty);
  });

  test('维咔 sec-ch-ua 与 UA 版本保持一致', () {
    expect(
      buildSecChUaForUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36'),
      '"Google Chrome";v="136", "Not_A Brand";v="8", "Chromium";v="136"',
    );
    expect(
      buildSecChUaForUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36 Edg/153.0.0.0'),
      '"Microsoft Edge";v="153", "Not_A Brand";v="8", "Chromium";v="153"',
    );
  });

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
