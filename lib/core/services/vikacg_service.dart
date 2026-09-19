import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../scraper/parse_utils.dart';
import '../../scraper/site_parsers.dart';
import '../utils/proxy_client.dart';
import 'app_logger.dart';

/// 维咔 API 不可用时返回 null，由页面继续执行 HTML 兜底。
class VikAcgService {
  final http.Client? client;
  VikAcgService({this.client});

  static Future<bool> supportsUrl(String url) => isVikacgUrl(url);

  Future<GameInfo?> fetchByUrl(String postUrl) async {
    final uri = Uri.tryParse(postUrl);
    if (uri == null) return null;
    final id = RegExp(r'^/p/(\d+)/?$').firstMatch(uri.path)?.group(1);
    if (id == null) return null;
    http.Client? requestClient;
    try {
      requestClient =
          client ?? await createProxyClientFromPrefs(domain: uri.host);
      final headers = await buildScrapeHeaders(postUrl);
      headers.addAll({
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
      });
      headers.remove('Sec-Fetch-User');
      headers.remove('Upgrade-Insecure-Requests');
      final response = await requestClient
          .post(
            uri.replace(
                path: '/api/vikacg/v1/getPost', query: '', fragment: ''),
            headers: headers,
            body: jsonEncode({'id': int.parse(id)}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        AppLogger.instance
            .warning('VikAcg', 'API 返回 HTTP ${response.statusCode}，使用 HTML 兜底');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final result = decoded is Map<String, dynamic>
          ? parseApiResponse(decoded, postUrl)
          : null;
      if (result == null) {
        AppLogger.instance.warning('VikAcg', 'API 正文不可用，使用 HTML 兜底');
      }
      return result;
    } catch (_) {
      AppLogger.instance.warning('VikAcg', 'API 请求或解析失败，使用 HTML 兜底');
      return null;
    } finally {
      if (client == null) requestClient?.close();
    }
  }

  GameInfo? parseApiResponse(Map<String, dynamic> response, String url) {
    if (response['status'] != 'success') return null;
    final post = response['data'];
    if (post is! Map<String, dynamic>) return null;
    final title = post['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final contents = <String>{};
    void collect(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        contents.add(value.trim());
      } else if (value is List) {
        for (final item in value) {
          collect(item);
        }
      } else if (value is Map) {
        if (value['locked'] == true) return;
        for (final key in const ['content', 'html', 'text', 'value']) {
          collect(value[key]);
        }
      }
    }

    collect(post['content']);
    collect(post['hidden_content']);
    if (contents.isEmpty) return null;
    final document = html_parser
        .parse('<html><head></head><body><article></article></body></html>');
    document.head!.append(Element.tag('meta')
      ..attributes['property'] = 'og:title'
      ..attributes['content'] = title);
    final article = document.querySelector('article')!;
    for (final content in contents) {
      if (RegExp(r'<[a-zA-Z][^>]*>').hasMatch(content)) {
        article.append(html_parser.parseFragment(content));
      } else {
        for (final line in content.split('\n')) {
          article.append(Element.tag('p')..text = line);
        }
      }
    }
    // 与站点 transPhotoURL 的 photo://0 映射保持一致。
    for (final img in article.querySelectorAll('img')) {
      for (final key in const ['src', 'data-src', 'data-original']) {
        final src = img.attributes[key];
        if (src != null && src.startsWith('photo://0/')) {
          img.attributes[key] =
              src.replaceFirst('photo://0/', 'https://p0.picjs.xyz/');
        }
      }
    }
    final parsed = VikAcgParser().parseGameInfo(document, url);
    if (parsed == null || parsed.description?.trim().isNotEmpty != true)
      return null;
    final tags = post['tags'];
    if (tags is List) {
      for (final item in tags) {
        final name =
            item is String ? item : (item is Map ? item['name'] : null);
        if (name is String &&
            name.trim().isNotEmpty &&
            !parsed.tags.contains(name.trim())) {
          parsed.tags.add(name.trim());
        }
      }
    }
    return parsed;
  }
}
