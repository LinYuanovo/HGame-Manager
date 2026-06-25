import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:html/parser.dart' as html_parser;
import '../utils/proxy_client.dart';
import '../../scraper/parse_utils.dart';

const List<String> kGenericGameNames = [
  'game', 'launcher', 'start', 'launch', 'play', 'player',
  'config', 'setup', 'install', 'update', 'updater',
  'server', 'client', 'tool', 'tools', 'editor', 'viewer',
  'helper', 'crashreport', 'bugreport', 'feedback',
  'unity', 'unreal', 'godot', 'renpy', 'rpgmaker', 'rpg',
  'wolf', 'wolfrpg', 'nw', 'cef_simple', 'renderdoc',
  'vcredist_x64', 'vcredist_x86', 'dxwebsetup', 'oalinst',
  'crashpad_handler', 'crash_handler', 'unitycrashhandler64',
  'unitycrashhandler32', 'unins000', 'unins001',
  '与工具一同启动', '启动', '游戏', '工具', '设置', '配置',
];

class VersionCheckResult {
  final String siteName;
  final String? maxVersion;
  final String? downloadUrl;
  final String? postTitle;

  VersionCheckResult({
    required this.siteName,
    this.maxVersion,
    this.downloadUrl,
    this.postTitle,
  });
}

class VersionCheckService {
  List<String> extractKeywords(String title) {
    final tokens = title.split(RegExp(r'\s+'));

    const filterWords = [
      '官中', '+', '存档', '汉化', 'steam', '官方',
    ];

    final filtered = tokens.where((t) {
      final lower = t.toLowerCase();
      if (filterWords.any((w) => lower.contains(w.toLowerCase()))) return false;
      if (kGenericGameNames.any((w) => lower == w)) return false;
      return true;
    }).toList();

    final subTokens = <String>[];
    for (final token in filtered) {
      subTokens.addAll(token.split(RegExp(r'[/\-]')));
    }

    final merged = <String>[];
    final buffer = StringBuffer();

    for (final token in subTokens) {
      if (token.isEmpty) continue;
      final isEnglish = RegExp(r'^[a-zA-Z0-9\s]+$').hasMatch(token);
      if (isEnglish) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(token);
      } else {
        if (buffer.isNotEmpty) {
          merged.add(buffer.toString().trim());
          buffer.clear();
        }
        merged.add(token);
      }
    }
    if (buffer.isNotEmpty) {
      merged.add(buffer.toString().trim());
    }

    return merged.where((k) => k.isNotEmpty && k.length > 1).toList();
  }

  int compareVersions(String v1, String v2) {
    final parts1 = _parseVersionParts(v1);
    final parts2 = _parseVersionParts(v2);

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) return p1.compareTo(p2);
    }
    return 0;
  }

  List<int> _parseVersionParts(String version) {
    final cleaned = version.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return [];
    return cleaned.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  Future<VersionCheckResult?> searchAcgYing(String keyword) async {
    final domain = await getEffectiveDomain('acgying');
    if (domain.isEmpty) return null;

    final url = 'https://$domain?s=$keyword';
    if (kDebugMode) debugPrint('[VersionCheck] 嘤嘤怪搜索: keyword=$keyword, url=$url');
    try {
      final client = await createProxyClientFromPrefs();
      final headers = await buildScrapeHeaders(url);
      final response = await client.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 15));
      client.close();

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[VersionCheck] 嘤嘤怪 HTTP ${response.statusCode}');
        return null;
      }

      final document = html_parser.parse(response.body);
      final items = document.querySelectorAll('div.post-list-view h2.post-list-title a');
      if (kDebugMode) debugPrint('[VersionCheck] 嘤嘤怪 找到 ${items.length} 个结果');

      String? maxVersion;
      String? bestUrl;
      String? bestTitle;

      for (final item in items) {
        final title = item.text.trim();
        final href = item.attributes['href'] ?? '';
        if (title.isEmpty || href.isEmpty) continue;

        final version = extractVersion(title);
        if (version != null) {
          if (maxVersion == null || compareVersions(version, maxVersion) > 0) {
            maxVersion = version;
            bestUrl = href;
            bestTitle = title;
          }
        }
      }

      if (maxVersion != null && bestUrl != null) {
        if (kDebugMode) debugPrint('[VersionCheck] 嘤嘤怪 最佳: $bestTitle v$maxVersion');
        return VersionCheckResult(
          siteName: '嘤嘤怪',
          maxVersion: maxVersion,
          downloadUrl: bestUrl,
          postTitle: bestTitle ?? '',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VersionCheck] 嘤嘤怪 异常: $e');
    }
    return null;
  }

  Future<VersionCheckResult?> searchFeiXue(String keyword) async {
    final domain = await getEffectiveDomain('feixue');
    if (domain.isEmpty) return null;

    if (kDebugMode) debugPrint('[VersionCheck] 飞雪ACG搜索: keyword=$keyword');
    try {
      final client = await createProxyClientFromPrefs();
      final headers = await buildScrapeHeaders('https://$domain/');

      final forumResponse = await client.get(
        Uri.parse('https://$domain/forum-43-1.html'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (forumResponse.statusCode != 200) {
        client.close();
        if (kDebugMode) debugPrint('[VersionCheck] 飞雪ACG 论坛页面 HTTP ${forumResponse.statusCode}');
        return null;
      }

      String? formhash;
      final formhashMatch = RegExp(r'formhash=([a-f0-9]+)').firstMatch(forumResponse.body);
      if (formhashMatch != null) {
        formhash = formhashMatch.group(1);
      }
      if (formhash == null) {
        client.close();
        if (kDebugMode) debugPrint('[VersionCheck] 飞雪ACG 未找到formhash');
        return null;
      }

      final searchHeaders = Map<String, String>.from(headers);
      searchHeaders['Content-Type'] = 'application/x-www-form-urlencoded';

      final postResponse = await client.post(
        Uri.parse('https://$domain/search.php?searchsubmit=yes'),
        headers: searchHeaders,
        body: 'mod=forum&formhash=$formhash&srchtype=title&srhfid=43&srhlocality=forum%3A%3Aforumdisplay&srchtxt=${Uri.encodeComponent(keyword)}&searchsubmit=true',
      ).timeout(const Duration(seconds: 15));

      String? redirectUrl;
      if (postResponse.statusCode == 301 || postResponse.statusCode == 302) {
        redirectUrl = postResponse.headers['location'];
      } else if (postResponse.statusCode == 200) {
        redirectUrl = postResponse.request?.url.toString();
      }

      if (redirectUrl == null) {
        client.close();
        return null;
      }

      final fullRedirectUrl = redirectUrl.startsWith('http')
          ? redirectUrl
          : 'https://$domain/$redirectUrl';

      final resultsResponse = await client.get(
        Uri.parse(fullRedirectUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      client.close();

      if (resultsResponse.statusCode != 200) return null;

      final document = html_parser.parse(resultsResponse.body);
      final items = document.querySelectorAll('li.pbw h3.xs3 a');
      if (kDebugMode) debugPrint('[VersionCheck] 飞雪ACG 找到 ${items.length} 个结果');

      String? maxVersion;
      String? bestUrl;
      String? bestTitle;

      for (final item in items) {
        final rawTitle = item.text.trim();
        final href = item.attributes['href'] ?? '';
        if (rawTitle.isEmpty || href.isEmpty) continue;

        final title = rawTitle.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        final version = extractVersion(title);
        if (version != null) {
          if (maxVersion == null || compareVersions(version, maxVersion) > 0) {
            maxVersion = version;
            bestUrl = href.startsWith('http') ? href : 'https://$domain/$href';
            bestTitle = title;
          }
        }
      }

      if (maxVersion != null && bestUrl != null) {
        if (kDebugMode) debugPrint('[VersionCheck] 飞雪ACG 最佳: $bestTitle v$maxVersion');
        return VersionCheckResult(
          siteName: '飞雪ACG',
          maxVersion: maxVersion,
          downloadUrl: bestUrl,
          postTitle: bestTitle ?? '',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VersionCheck] 飞雪ACG 异常: $e');
    }
    return null;
  }

  Future<VersionCheckResult?> searchVikAcg(String keyword) async {
    final domain = await getEffectiveDomain('vikacg');
    if (domain.isEmpty) return null;

    if (kDebugMode) debugPrint('[VersionCheck] 维咔ACG搜索: keyword=$keyword');
    try {
      final client = await createProxyClientFromPrefs();
      final headers = await buildScrapeHeaders('https://$domain/');
      headers['Content-Type'] = 'application/json';

      final response = await client.post(
        Uri.parse('https://$domain/api/vikacg/v1/comprehensiveSearch'),
        headers: headers,
        body: jsonEncode({
          'search': keyword,
          'order': 'related',
          'sort': 'desc',
          'page_count': 20,
          'paged': 1,
          'tags': null,
          'rating': null,
        }),
      ).timeout(const Duration(seconds: 15));

      client.close();

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[VersionCheck] 维咔ACG HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final list = data['data']?['list'] as List<dynamic>? ?? [];
      if (kDebugMode) debugPrint('[VersionCheck] 维咔ACG 找到 ${list.length} 个结果');

      String? maxVersion;
      String? bestUrl;
      String? bestTitle;

      for (final item in list) {
        final detail = item['detail'];
        if (detail == null) continue;
        final title = (detail['title'] as String?)?.trim() ?? '';
        final id = detail['id'];
        if (title.isEmpty || id == null) continue;

        final version = extractVersion(title);
        if (version != null) {
          if (maxVersion == null || compareVersions(version, maxVersion) > 0) {
            maxVersion = version;
            bestUrl = 'https://www.vikacg.cc/p/$id';
            bestTitle = title;
          }
        }
      }

      if (maxVersion != null && bestUrl != null) {
        if (kDebugMode) debugPrint('[VersionCheck] 维咔ACG 最佳: $bestTitle v$maxVersion');
        return VersionCheckResult(
          siteName: '维咔ACG',
          maxVersion: maxVersion,
          downloadUrl: bestUrl,
          postTitle: bestTitle ?? '',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[VersionCheck] 维咔ACG 异常: $e');
    }
    return null;
  }

  Future<VersionCheckResult?> checkForUpdate(String gameTitle, String currentVersion) async {
    final keywords = extractKeywords(gameTitle);
    if (keywords.isEmpty) {
      if (kDebugMode) debugPrint('[VersionCheck] 无有效关键词: $gameTitle');
      return null;
    }
    if (kDebugMode) debugPrint('[VersionCheck] 开始检查更新: "$gameTitle" 当前版本=$currentVersion 关键词=$keywords');

    final allResults = <VersionCheckResult>[];

    for (final keyword in keywords) {
      final vikacgResult = await searchVikAcg(keyword);
      if (vikacgResult != null) allResults.add(vikacgResult);

      final feixueResult = await searchFeiXue(keyword);
      if (feixueResult != null) allResults.add(feixueResult);

      final acgyingResult = await searchAcgYing(keyword);
      if (acgyingResult != null) allResults.add(acgyingResult);
    }

    if (allResults.isEmpty) {
      if (kDebugMode) debugPrint('[VersionCheck] 第一轮无结果，尝试次级关键词');
      final secondaryKeywords = keywords
          .where((k) => k.length > 4)
          .map((k) => k.substring(0, 4))
          .toList();

      for (final keyword in secondaryKeywords) {
        final vikacgResult = await searchVikAcg(keyword);
        if (vikacgResult != null) allResults.add(vikacgResult);

        final feixueResult = await searchFeiXue(keyword);
        if (feixueResult != null) allResults.add(feixueResult);

        final acgyingResult = await searchAcgYing(keyword);
        if (acgyingResult != null) allResults.add(acgyingResult);
      }
    }

    if (allResults.isEmpty) {
      if (kDebugMode) debugPrint('[VersionCheck] 所有站点均无结果');
      return null;
    }

    VersionCheckResult? best;
    for (final result in allResults) {
      if (best == null || (result.maxVersion != null && best.maxVersion != null && compareVersions(result.maxVersion!, best.maxVersion!) > 0)) {
        best = result;
      }
    }

    if (best != null && currentVersion.isNotEmpty && best.maxVersion != null) {
      if (compareVersions(best.maxVersion!, currentVersion) <= 0) {
        if (kDebugMode) debugPrint('[VersionCheck] 当前版本已是最新: $currentVersion >= ${best.maxVersion}');
        return null;
      }
    }

    if (kDebugMode && best != null) debugPrint('[VersionCheck] 发现新版本: ${best.siteName} ${best.maxVersion} (${best.postTitle})');
    return best;
  }
}
