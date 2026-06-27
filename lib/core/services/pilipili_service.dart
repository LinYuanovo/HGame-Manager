import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import '../utils/proxy_client.dart';
import '../utils/app_settings.dart';

class PilipiliSearchResult {
  final String title;
  final int articleId;
  final String author;
  final int viewCount;
  final String summary;

  PilipiliSearchResult({
    required this.title,
    required this.articleId,
    required this.author,
    required this.viewCount,
    required this.summary,
  });
}

class PilipiliService {
  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const _mixinKeyEncTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
    33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40,
    61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11,
    36, 20, 34, 44, 52
  ];

  Future<String> _getCookie() async {
    final prefs = await AppSettings.load();
    return prefs.getString('cookie_pilipili') ?? '';
  }

  String _getMixinKey(String orig) {
    return _mixinKeyEncTab.map((i) => orig[i]).join('').substring(0, 32);
  }

  Map<String, String> _encWbi(Map<String, dynamic> params, String imgKey, String subKey) {
    final mixinKey = _getMixinKey(imgKey + subKey);
    final currTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    params['wts'] = currTime.toString();
    // Ensure all values are strings
    final stringParams = params.map((k, v) => MapEntry(k, v.toString()));
    final sortedParams = Map.fromEntries(stringParams.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    final filteredParams = sortedParams.map((k, v) => MapEntry(k, v.replaceAll(RegExp(r"!'()*"), '')));
    final query = Uri(queryParameters: filteredParams).query;
    final wbiSign = md5.convert(utf8.encode(query + mixinKey)).toString();
    filteredParams['w_rid'] = wbiSign;
    return filteredParams;
  }

  Future<Map<String, String>> _getWbiKeys() async {
    final cookie = await _getCookie();
    final client = await createProxyClientFromPrefs(domain: 'api.bilibili.com');
    try {
      final response = await client.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: {'User-Agent': _userAgent, 'Cookie': cookie},
      ).timeout(const Duration(seconds: 15));
      final json = jsonDecode(response.body);
      final imgUrl = json['data']['wbi_img']['img_url'] as String;
      final subUrl = json['data']['wbi_img']['sub_url'] as String;
      final imgKey = imgUrl.split('/').last.split('.').first;
      final subKey = subUrl.split('/').last.split('.').first;
      return {'imgKey': imgKey, 'subKey': subKey};
    } finally {
      client.close();
    }
  }

  /// 获取API错误信息
  String _getErrorMessage(int code, String message) {
    switch (code) {
      case -352:
        return '可能是未填写cookie(设置中填写)，如已填写请重新获取cookie或换号尝试';
      case -509:
        return '可能是未填写cookie(设置中填写) 请求过于频繁，请稍后再试';
      case -400:
        return '请求错误';
      case -404:
        return '啥都木有';
      default:
        return message.isNotEmpty ? message : '未知错误 ($code)';
    }
  }

  Future<List<PilipiliSearchResult>> searchArticles(String keyword, {int page = 1}) async {
    final wbiKeys = await _getWbiKeys();
    final cookie = await _getCookie();
    final params = {
      'search_type': 'article',
      'keyword': keyword,
      'page': page.toString(),
      'order': 'totalrank',
    };
    final signedParams = _encWbi(params, wbiKeys['imgKey']!, wbiKeys['subKey']!);
    final uri = Uri.https('api.bilibili.com', '/x/web-interface/wbi/search/type', signedParams);
    final client = await createProxyClientFromPrefs(domain: 'api.bilibili.com');
    try {
      final response = await client.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Cookie': cookie},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final json = jsonDecode(response.body);
      final code = json['code'] as int;
      if (code != 0) {
        final errorMsg = _getErrorMessage(code, json['message'] as String? ?? '');
        if (kDebugMode) debugPrint('[Pilipili] 搜索失败: code=$code, $errorMsg');
        throw Exception(errorMsg);
      }
      final articles = json['data']['result'] as List<dynamic>? ?? [];
      if (kDebugMode) debugPrint('[Pilipili] 搜索到 ${articles.length} 篇文章');
      return articles.map((a) => PilipiliSearchResult(
        title: (a['title'] as String).replaceAll(RegExp(r'<[^>]+>'), ''),
        articleId: a['id'] as int,
        author: a['author'] as String? ?? '',
        viewCount: a['view'] as int? ?? 0,
        summary: a['desc'] as String? ?? '',
      )).toList();
    } finally {
      client.close();
    }
  }

  Future<String?> getArticleContent(int articleId) async {
    if (kDebugMode) debugPrint('[Pilipili] 获取文章内容: cv$articleId');
    final wbiKeys = await _getWbiKeys();
    final cookie = await _getCookie();
    final params = {
      'id': articleId.toString(),
      'gaia_source': 'main_web',
    };
    final signedParams = _encWbi(params, wbiKeys['imgKey']!, wbiKeys['subKey']!);
    final uri = Uri.https('api.bilibili.com', '/x/article/view', signedParams);
    final client = await createProxyClientFromPrefs(domain: 'api.bilibili.com');
    try {
      final response = await client.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Cookie': cookie},
      ).timeout(const Duration(seconds: 15));
      if (kDebugMode) debugPrint('[Pilipili] 文章API响应: ${response.statusCode}');
      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[Pilipili] 文章请求失败: HTTP ${response.statusCode}');
        throw Exception('HTTP ${response.statusCode}');
      }
      final json = jsonDecode(response.body);
      final code = json['code'] as int;
      if (kDebugMode) debugPrint('[Pilipili] 文章API code: $code, message: ${json['message']}');
      if (code != 0) {
        final errorMsg = _getErrorMessage(code, json['message'] as String? ?? '');
        if (kDebugMode) debugPrint('[Pilipili] 文章API错误: $errorMsg');
        throw Exception(errorMsg);
      }
      final data = json['data'];
      if (data == null) {
        if (kDebugMode) debugPrint('[Pilipili] 文章数据为空');
        return null;
      }
      final contentType = data['type'] as int? ?? 0;
      final content = data['content'] as String? ?? '';
      if (kDebugMode) debugPrint('[Pilipili] 文章类型: $contentType, 内容长度: ${content.length}');
      if (content.isEmpty) {
        if (kDebugMode) debugPrint('[Pilipili] 文章内容为空');
        return null;
      }
      if (contentType == 0) {
        if (kDebugMode) debugPrint('[Pilipili] 解析HTML格式内容');
        return _htmlToMarkdown(content);
      }
      if (contentType == 3) {
        if (kDebugMode) debugPrint('[Pilipili] 解析Delta格式内容');
        return _deltaToMarkdown(content);
      }
      if (kDebugMode) debugPrint('[Pilipili] 未知内容类型: $contentType, 返回原始内容');
      return content;
    } catch (e) {
      if (kDebugMode) debugPrint('[Pilipili] 获取文章内容异常: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  String _htmlToMarkdown(String html) {
    var text = html;
    // 处理 figure > img 结构（支持多种src属性）
    text = text.replaceAllMapped(
      RegExp(r'<figure[^>]*>.*?<img[^>]*(?:data-original|data-src|src)="([^"]+)"[^>]*/?>.*?</figure>', dotAll: true),
      (m) {
        var url = m[1] ?? '';
        if (url.startsWith('//')) url = 'https:$url';
        return '\n![图片]($url)\n';
      },
    );
    // 处理独立的 img 标签
    text = text.replaceAllMapped(
      RegExp(r'<img[^>]*(?:data-original|data-src|src)="([^"]+)"[^>]*/?>'),
      (m) {
        var url = m[1] ?? '';
        if (url.startsWith('//')) url = 'https:$url';
        return '\n![图片]($url)\n';
      },
    );
    text = text.replaceAllMapped(RegExp(r'<h1[^>]*>(.*?)</h1>'), (m) => '\n# ${m[1]}\n');
    text = text.replaceAllMapped(RegExp(r'<h2[^>]*>(.*?)</h2>'), (m) => '\n## ${m[1]}\n');
    text = text.replaceAllMapped(RegExp(r'<h3[^>]*>(.*?)</h3>'), (m) => '\n### ${m[1]}\n');
    text = text.replaceAllMapped(RegExp(r'<strong[^>]*>(.*?)</strong>'), (m) => '**${m[1]}**');
    text = text.replaceAllMapped(RegExp(r'<b[^>]*>(.*?)</b>'), (m) => '**${m[1]}**');
    text = text.replaceAllMapped(RegExp(r'<em[^>]*>(.*?)</em>'), (m) => '*${m[1]}*');
    text = text.replaceAllMapped(RegExp(r'<li[^>]*>(.*?)</li>'), (m) => '- ${m[1]}\n');
    text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>'), '\n');
    text = text.replaceAll(RegExp(r'</p>'), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text.replaceAll(RegExp(r'&nbsp;'), ' ');
    text = text.replaceAll(RegExp(r'&lt;'), '<');
    text = text.replaceAll(RegExp(r'&gt;'), '>');
    text = text.replaceAll(RegExp(r'&amp;'), '&');
    text = text.replaceAll(RegExp(r'&#39;'), "'");
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _deltaToMarkdown(String deltaStr) {
    try {
      final delta = jsonDecode(deltaStr) as Map<String, dynamic>;

      // 处理 paragraphs 格式（opus.content.paragraphs）
      if (delta.containsKey('paragraphs')) {
        return _paragraphsToMarkdown(delta['paragraphs'] as List<dynamic>? ?? []);
      }

      // 处理 ops 格式（Quill Delta）
      if (delta.containsKey('ops')) {
        return _opsToMarkdown(delta['ops'] as List<dynamic>? ?? []);
      }

      return deltaStr;
    } catch (e) {
      if (kDebugMode) debugPrint('[Pilipili] 解析Delta失败: $e');
      return deltaStr;
    }
  }

  String _paragraphsToMarkdown(List<dynamic> paragraphs) {
    final buffer = StringBuffer();
    for (final para in paragraphs) {
      final paraType = para['para_type'] as int? ?? 1;

      if (paraType == 2) {
        // 图片类型
        final pic = para['pic'] as Map<String, dynamic>?;
        if (pic != null) {
          final pics = pic['pics'] as List<dynamic>? ?? [];
          for (final p in pics) {
            final url = p['url'] as String? ?? '';
            if (url.isNotEmpty) {
              buffer.write('\n![图片]($url)\n');
            }
          }
        }
      } else if (paraType == 1 || paraType == 9) {
        // 文本类型（1=普通文本，9=标题）
        final textObj = para['text'] as Map<String, dynamic>?;
        if (textObj != null) {
          final nodes = textObj['nodes'] as List<dynamic>? ?? [];
          final textBuffer = StringBuffer();
          for (final node in nodes) {
            final word = node['word'] as Map<String, dynamic>?;
            if (word != null) {
              textBuffer.write(word['words'] as String? ?? '');
            }
          }
          final text = textBuffer.toString();
          if (text.trim().isNotEmpty) {
            // 标题类型
            if (paraType == 9) {
              final format = para['format'] as Map<String, dynamic>?;
              final headingType = format?['heading_type'] as int? ?? 1;
              final prefix = '#' * headingType;
              buffer.write('\n$prefix $text\n');
            } else {
              buffer.write('$text\n');
            }
          }
        }
      }
    }
    return buffer.toString().trim();
  }

  String _opsToMarkdown(List<dynamic> ops) {
    final buffer = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      if (insert is String) {
        buffer.write(insert);
      } else if (insert is Map) {
        if (insert.containsKey('native-image')) {
          final img = insert['native-image'] as Map<String, dynamic>;
          final url = img['url'] as String? ?? '';
          if (url.isNotEmpty) buffer.write('\n![图片]($url)\n');
        } else if (insert.containsKey('image')) {
          final url = insert['image'] as String? ?? '';
          if (url.isNotEmpty) buffer.write('\n![图片]($url)\n');
        }
      }
    }
    return buffer.toString().trim();
  }
}
