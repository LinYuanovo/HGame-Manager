import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/app_settings.dart';
import 'package:hgame_manager/core/utils/proxy_client.dart';

void main() {
  group('DLsite 请求凭据', () {
    late Directory temporary;
    late AppSettings settings;
    const cookie = 'session=test-session==';
    const source = 'https://www.dlsite.com/maniax/work/=/product_id/RJ100001.html';

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('hgm_dlsite_headers_');
      settings = await AppSettings.loadFromFileForTest(
          '${temporary.path}/settings.json');
      await settings.setString('cookie_dlsite', cookie);
    });

    tearDown(() async {
      await settings.flush();
      AppSettings.invalidateCache();
      await temporary.delete(recursive: true);
    });

    test('通用页面请求读取 DLsite Cookie，主机匹配不受路径及相似域名干扰', () async {
      for (final url in [source, 'https://DLSITE.COM/', 'https://www.dlsite.com./']) {
        expect((await buildScrapeHeaders(url))['Cookie'], cookie);
      }
      for (final url in [
        'https://example.test/dlsite.com/',
        'https://dlsite.com.example.test/',
        'https://dlsite.com@example.test/',
      ]) {
        expect((await buildScrapeHeaders(url))['Cookie'], isNull);
      }
    });

    test('官方图片请求保留登录 Cookie 和来源，外部图片不携带凭据', () async {
      final headers = await buildScrapeImageHeaders(source);
      expect(headers['Cookie'], cookie);
      expect(headers['Referer'], source);
      for (final image in [
        'https://img.dlsite.jp/cover.jpg',
        'https://media.dlsite.com/sample.jpg',
        'https://www.dlsite.com/cover.jpg',
        'https://img.dlsite.jp./cover.jpg',
      ]) {
        final scoped = scopeScrapeImageHeaders(image, headers);
        expect(scoped['Cookie'], cookie);
        expect(scoped['Referer'], source);
      }
      for (final image in [
        'https://external.example/cover.jpg',
        'https://img.dlsite.jp.example.test/cover.jpg',
        'https://img.dlsite.jp@example.test/cover.jpg',
        'http://img.dlsite.jp/cover.jpg',
      ]) {
        final scoped = scopeScrapeImageHeaders(image, headers);
        expect(scoped['Cookie'], isNull);
        expect(scoped['Referer'], source);
      }
      expect(headers['Cookie'], cookie);
      await settings.setString('cookie_dlsite', '');
      expect((await buildScrapeImageHeaders(source))['Cookie'], isNull);
    });

    test('其他站点的图片请求头保持原行为', () {
      final headers = {'Referer': 'https://example.test/', 'Cookie': 'sid=other'};
      expect(scopeScrapeImageHeaders('https://cdn.example.test/a.jpg', headers),
          headers);
    });
  });

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

  group('normalizeSystemProxyServer', () {
    test('单值原样返回', () {
      expect(normalizeSystemProxyServer('127.0.0.1:7897'), '127.0.0.1:7897');
    });

    test('分协议格式取 https 条目', () {
      expect(
        normalizeSystemProxyServer(
            'http=127.0.0.1:7890;https=127.0.0.1:7891'),
        '127.0.0.1:7891',
      );
    });

    test('分协议仅有 http 时取 http 条目', () {
      expect(
        normalizeSystemProxyServer('socks=127.0.0.1:1080;http=10.0.0.1:80'),
        '10.0.0.1:80',
      );
    });

    test('仅 socks 等其他协议时返回 null', () {
      expect(normalizeSystemProxyServer('socks=127.0.0.1:1080'), isNull);
    });

    test('空值返回 null', () {
      expect(normalizeSystemProxyServer(''), isNull);
      expect(normalizeSystemProxyServer('  '), isNull);
    });
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
