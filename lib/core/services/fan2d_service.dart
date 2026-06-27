import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:html/parser.dart' as html_parser;
import '../models/backup_entry.dart';
import '../services/backup_service.dart';
import '../utils/proxy_client.dart';
import '../utils/app_settings.dart';
import 'version_check_service.dart';

class Fan2dSearchResult {
  final String title;
  final String downloadUrl;

  Fan2dSearchResult({required this.title, required this.downloadUrl});
}

/// 存档文件条目（kind 页面解析出的具体存档）
class Fan2dSaveFile {
  final String title;
  final String downloadUrl;

  Fan2dSaveFile({required this.title, required this.downloadUrl});
}

/// 2DFan攻略搜索结果
class Fan2dGuideResult {
  final String title;
  final String guideUrl;

  Fan2dGuideResult({required this.title, required this.guideUrl});
}

/// 2DFan walkthrough结果
class Fan2dWalkthrough {
  final String title;
  final String url;

  Fan2dWalkthrough({required this.title, required this.url});
}

/// 2DFan攻略刮削结果
class Fan2dGuideScrapeResult {
  final String? content;
  final List<Fan2dWalkthrough> walkthroughs;

  Fan2dGuideScrapeResult({this.content, this.walkthroughs = const []});

  bool get hasWalkthroughs => walkthroughs.length > 1;
}

/// downloadAndImport 的返回结果
class Fan2dDownloadResult {
  final BackupEntry? entry;
  final List<Fan2dSaveFile> saveFiles;

  bool get hasSaveFiles => saveFiles.isNotEmpty;
  bool get hasEntry => entry != null;

  Fan2dDownloadResult.entry(this.entry) : saveFiles = [];
  Fan2dDownloadResult.saveFiles(this.saveFiles) : entry = null;
  Fan2dDownloadResult.empty() : entry = null, saveFiles = [];
}

class _ResolveResult {
  final String? directUrl;
  final List<Fan2dSaveFile> saveFiles;
  bool get hasSaveFiles => saveFiles.isNotEmpty;
  _ResolveResult.direct(this.directUrl) : saveFiles = [];
  _ResolveResult.saveFiles(this.saveFiles) : directUrl = null;
}

class Fan2dService {
  static const _defaultDomain = 'fan2d.top';
  static const _fallbackDomain = '2dfan.com';

  Future<String> _getDomain() async {
    final prefs = await AppSettings.load();
    return prefs.getString('domain_2dfan') ?? '';
  }

  /// 检测可用的 2DFan 域名并保存
  Future<String> detectAndSaveDomain() async {
    final prefs = await AppSettings.load();
    final client = await createProxyClientFromPrefs(domain: _defaultDomain);
    try {
      final headers = await buildScrapeHeaders('https://$_defaultDomain/domain');
      final response = await client.get(
        Uri.parse('https://$_defaultDomain/domain'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final pattern = RegExp(r'<li>\s*(https?://[^\s<&]+)/?\s*(?:&nbsp;)?\s*(?:<span[^>]*>)?\s*(新增|中转)', caseSensitive: false);
        final domains = <String>[];
        for (final m in pattern.allMatches(response.body)) {
          final url = m.group(1) ?? '';
          domains.add(url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), ''));
        }

        for (final domain in domains) {
          try {
            final testResponse = await client.get(
              Uri.parse('https://$domain/'),
              headers: headers,
            ).timeout(const Duration(seconds: 15));
            if (testResponse.statusCode == 200) {
              if (kDebugMode) debugPrint('[Fan2d] 可用域名: $domain');
              await prefs.setString('domain_2dfan', domain);
              return domain;
            }
          } catch (e) {
            if (kDebugMode) debugPrint('[Fan2d] 域名测试失败: $domain, $e');
          }
        }
      }

      // 回退尝试 2dfan.com
      try {
        final fallbackHeaders = await buildScrapeHeaders('https://$_fallbackDomain/');
        final testResponse = await client.get(
          Uri.parse('https://$_fallbackDomain/'),
          headers: fallbackHeaders,
        ).timeout(const Duration(seconds: 15));
        if (testResponse.statusCode == 200) {
          if (kDebugMode) debugPrint('[Fan2d] 使用回退域名: $_fallbackDomain');
          await prefs.setString('domain_2dfan', _fallbackDomain);
          return _fallbackDomain;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Fan2d] 回退域名测试失败: $_fallbackDomain, $e');
      }
    } finally {
      client.close();
    }

    throw Exception('无法连接到 2DFan');
  }

  /// 搜索关键词，返回结果列表
  Future<List<Fan2dSearchResult>> search(String keyword) async {
    final domain = await _getDomain();
    if (domain.isEmpty) {
      final detected = await detectAndSaveDomain();
      return _doSearch(detected, keyword);
    }
    return _doSearch(domain, keyword);
  }

  /// 带回退的搜索：优先用启动器名搜索，无结果再用 title 分词逐个尝试，命中即停
  Future<List<Fan2dSearchResult>> searchWithFallback({
    required String gamePath,
    String? gameLauncher,
    required String gameTitle,
  }) async {
    if (gameLauncher != null && gameLauncher.isNotEmpty) {
      final launcherName = gameLauncher.replaceAll('\\', '/').split('/').last;
      final nameWithoutExt = launcherName.contains('.')
          ? launcherName.substring(0, launcherName.lastIndexOf('.'))
          : launcherName;

      final lowerName = nameWithoutExt.toLowerCase();
      final isGeneric = kGenericGameNames.any((w) => lowerName == w || lowerName.contains(w));

      if (nameWithoutExt.isNotEmpty && !isGeneric) {
        if (kDebugMode) debugPrint('[Fan2d] 尝试启动器名搜索: $nameWithoutExt');
        final results = await search(nameWithoutExt);
        if (results.isNotEmpty) return results;
      }
    }

    final keywords = _extractKeywords(gameTitle);
    for (final keyword in keywords) {
      if (kDebugMode) debugPrint('[Fan2d] 尝试关键词搜索: $keyword');
      final results = await search(keyword);
      if (results.isNotEmpty) return results;
    }

    return [];
  }

  /// 从标题中提取关键词（复用 VersionCheckService 的分词逻辑）
  List<String> _extractKeywords(String title) {
    final tokens = title.split(RegExp(r'\s+'));

    final filtered = tokens.where((t) {
      final lower = t.toLowerCase();
      return !kGenericGameNames.any((w) => lower == w || lower.contains(w));
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

  Future<List<Fan2dSearchResult>> _doSearch(String domain, String keyword) async {
    final url = 'https://$domain/subjects/search?keyword=${Uri.encodeComponent(keyword)}';
    if (kDebugMode) debugPrint('[Fan2d] 搜索: $url');

    final client = await createProxyClientFromPrefs(domain: domain);
    try {
      final headers = await buildScrapeHeaders(url);
      final response = await client.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[Fan2d] 搜索 HTTP ${response.statusCode}');
        return [];
      }

      final document = html_parser.parse(response.body);
      final items = document.querySelectorAll('li.media');
      if (kDebugMode) debugPrint('[Fan2d] 找到 ${items.length} 个结果');

      final results = <Fan2dSearchResult>[];
      for (final item in items) {
        final titleEl = item.querySelector('h4.media-heading a');
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        String? downloadUrl;
        final resourcesEl = item.querySelector('p#resources');
        if (resourcesEl != null) {
          final links = resourcesEl.querySelectorAll('a');
          for (final link in links) {
            final text = link.text.trim();
            if (text.contains('存档')) {
              downloadUrl = link.attributes['href'];
              break;
            }
          }
        }

        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          if (!downloadUrl.startsWith('http')) {
            downloadUrl = 'https://$domain$downloadUrl';
          }
          results.add(Fan2dSearchResult(title: title, downloadUrl: downloadUrl));
        }
      }
      return results;
    } finally {
      client.close();
    }
  }

  /// 搜索2DFan攻略
  Future<List<Fan2dGuideResult>> searchGuides(String keyword) async {
    final domain = await _getDomain();
    if (domain.isEmpty) {
      final detected = await detectAndSaveDomain();
      return _doGuideSearch(detected, keyword);
    }
    return _doGuideSearch(domain, keyword);
  }

  /// 带回退的攻略搜索：优先用启动器名搜索，无结果再用 title 分词逐个尝试
  Future<List<Fan2dGuideResult>> searchGuidesWithFallback({
    required String gamePath,
    String? gameLauncher,
    required String gameTitle,
  }) async {
    if (gameLauncher != null && gameLauncher.isNotEmpty) {
      final launcherName = gameLauncher.replaceAll('\\', '/').split('/').last;
      final nameWithoutExt = launcherName.contains('.')
          ? launcherName.substring(0, launcherName.lastIndexOf('.'))
          : launcherName;

      final lowerName = nameWithoutExt.toLowerCase();
      final isGeneric = kGenericGameNames.any((w) => lowerName == w || lowerName.contains(w));

      if (nameWithoutExt.isNotEmpty && !isGeneric) {
        if (kDebugMode) debugPrint('[Fan2d] 尝试启动器名搜索攻略: $nameWithoutExt');
        final results = await searchGuides(nameWithoutExt);
        if (results.isNotEmpty) return results;
      }
    }

    final keywords = _extractKeywords(gameTitle);
    for (final keyword in keywords) {
      if (kDebugMode) debugPrint('[Fan2d] 尝试关键词搜索攻略: $keyword');
      final results = await searchGuides(keyword);
      if (results.isNotEmpty) return results;
    }

    return [];
  }

  Future<List<Fan2dGuideResult>> _doGuideSearch(String domain, String keyword) async {
    final url = 'https://$domain/subjects/search?keyword=${Uri.encodeComponent(keyword)}';
    if (kDebugMode) debugPrint('[Fan2d] 攻略搜索: $url');

    final client = await createProxyClientFromPrefs(domain: domain);
    try {
      final headers = await buildScrapeHeaders(url);
      final response = await client.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[Fan2d] 攻略搜索 HTTP ${response.statusCode}');
        return [];
      }

      final document = html_parser.parse(response.body);
      final items = document.querySelectorAll('li.media');
      if (kDebugMode) debugPrint('[Fan2d] 攻略搜索找到 ${items.length} 个结果');

      final results = <Fan2dGuideResult>[];
      for (final item in items) {
        final titleEl = item.querySelector('h4.media-heading a');
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        // 参考下载存档的实现：在 p#resources 中查找攻略按钮
        // XPath: /html/body/div[5]/div/div[1]/div/div/div[2]/ul/li[i]/div/p[4]/span[2]/a
        String? guideUrl;
        final resourcesEl = item.querySelector('p#resources');
        if (resourcesEl != null) {
          final spans = resourcesEl.querySelectorAll('span');
          for (final span in spans) {
            final text = span.text.trim();
            if (text.contains('攻略')) {
              guideUrl ??= span.querySelector('a')?.attributes['href'];
              if (kDebugMode) debugPrint('[Fan2d] 找到攻略按钮: $text -> $guideUrl');
              break;
            }
          }
          final links = resourcesEl.querySelectorAll('a');
          for (final link in links) {
            final text = link.text.trim();
            if (kDebugMode) debugPrint('[Fan2d] : $text');
            if (text.contains('攻略')) {
              guideUrl = link.attributes['href'];
              if (kDebugMode) debugPrint('[Fan2d] 找到攻略按钮: $text -> $guideUrl');
              break;
            }
          }
        }

        // 如果 p#resources 中没找到，遍历所有 p 标签查找
        if (guideUrl == null || guideUrl.isEmpty) {
          final pTags = item.querySelectorAll('p');
          for (final p in pTags) {
            final links = p.querySelectorAll('a');
            for (final link in links) {
              final text = link.text.trim();
              final href = link.attributes['href'] ?? '';
              if (text.contains('攻略') || href.contains('/topics/')) {
                guideUrl = href;
                if (kDebugMode) debugPrint('[Fan2d] 从其他p标签找到攻略: $text -> $guideUrl');
                break;
              }
            }
            if (guideUrl != null && guideUrl.isNotEmpty) break;
          }
        }

        if (guideUrl != null && guideUrl.isNotEmpty) {
          if (!guideUrl.startsWith('http')) {
            guideUrl = 'https://$domain$guideUrl';
          }
          if (kDebugMode) debugPrint('[Fan2d] 攻略URL: $guideUrl');
          results.add(Fan2dGuideResult(title: title, guideUrl: guideUrl));
        }
      }
      if (kDebugMode) debugPrint('[Fan2d] 攻略搜索完成，共 ${results.length} 个结果');
      return results;
    } finally {
      client.close();
    }
  }

  /// 获取2DFan攻略内容并转为Markdown
  /// 如果有多个walkthrough，返回列表让用户选择
  Future<Fan2dGuideScrapeResult> scrapeGuideContent(String guideUrl) async {
    if (kDebugMode) debugPrint('[Fan2d] 刮削攻略: $guideUrl');
    final client = await createProxyClientFromPrefs(domain: Uri.parse(guideUrl).host);
    try {
      final headers = await buildScrapeHeaders(guideUrl);
      final response = await client.get(Uri.parse(guideUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[Fan2d] 攻略页面 HTTP ${response.statusCode}');
        return Fan2dGuideScrapeResult();
      }

      final document = html_parser.parse(response.body);

      // 检查是否有 walkthroughs（多个攻略子页面）
      // XPath: /html/body/div[5]/div/div[1]/div/div/div[2]/div
      final contentDiv = document.querySelector('div.block-content') ?? document.querySelector('.topic-content');
      final walkthroughs = <Fan2dWalkthrough>[];

      if (contentDiv != null) {
        final links = contentDiv.querySelectorAll('a');
        for (final link in links) {
          final href = link.attributes['href'] ?? '';
          final text = link.text.trim();
          if (href.contains('/topics/') && !href.endsWith(guideUrl.split('/').last)) {
            final fullUrl = href.startsWith('http') ? href : 'https://${Uri.parse(guideUrl).host}$href';
            walkthroughs.add(Fan2dWalkthrough(title: text.isNotEmpty ? text : '攻略 ${walkthroughs.length + 1}', url: fullUrl));
            if (kDebugMode) debugPrint('[Fan2d] 找到walkthrough: $text -> $href');
          }
        }
      }

      // 如果有多个walkthrough，返回列表让用户选择
      if (walkthroughs.length > 1) {
        if (kDebugMode) debugPrint('[Fan2d] 有 ${walkthroughs.length} 个walkthrough，返回列表');
        return Fan2dGuideScrapeResult(walkthroughs: walkthroughs);
      }

      // 如果只有一个或没有walkthrough，直接刮削当前页面
      final content = _extractGuideMarkdown(document, guideUrl);
      return Fan2dGuideScrapeResult(content: content);
    } catch (e) {
      if (kDebugMode) debugPrint('[Fan2d] 攻略刮削异常: $e');
      return Fan2dGuideScrapeResult();
    } finally {
      client.close();
    }
  }

  /// 刮削指定的walkthrough页面
  Future<String?> scrapeWalkthrough(String walkthroughUrl) async {
    if (kDebugMode) debugPrint('[Fan2d] 刮削walkthrough: $walkthroughUrl');
    final client = await createProxyClientFromPrefs(domain: Uri.parse(walkthroughUrl).host);
    try {
      final headers = await buildScrapeHeaders(walkthroughUrl);
      final response = await client.get(Uri.parse(walkthroughUrl), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (kDebugMode) debugPrint('[Fan2d] walkthrough页面 HTTP ${response.statusCode}');
        return null;
      }

      final document = html_parser.parse(response.body);
      return _extractGuideMarkdown(document, walkthroughUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('[Fan2d] walkthrough刮削异常: $e');
      return null;
    } finally {
      client.close();
    }
  }

  String _extractGuideMarkdown(dynamic document, String baseUrl) {
    final buffer = StringBuffer();

    // 尝试多种选择器找到攻略内容容器
    dynamic contentDiv;
    final selectors = [
      '#topic-content',
      '.topic-content',
      '.control-group.topic-content',
      '.block-content .control-group',
      '.block-content',
    ];

    for (final selector in selectors) {
      contentDiv = document.querySelector(selector);
      if (contentDiv != null) {
        if (kDebugMode) debugPrint('[Fan2d] 使用选择器 "$selector" 找到内容容器');
        break;
      }
    }

    if (contentDiv == null) {
      if (kDebugMode) {
        debugPrint('[Fan2d] 未找到攻略内容容器，尝试所有div');
        // 打印页面结构帮助调试
        final allDivs = document.querySelectorAll('div');
        debugPrint('[Fan2d] 页面共有 ${allDivs.length} 个div');
        for (final div in allDivs.take(20)) {
          debugPrint('[Fan2d]   div class="${div.className}" id="${div.id}"');
        }
      }
      return '';
    }

    // 打印找到的容器HTML帮助调试
    if (kDebugMode) {
      final html = contentDiv.outerHtml;
      debugPrint('[Fan2d] 容器HTML长度: ${html.length}');
      debugPrint('[Fan2d] 容器HTML前2000字符:\n$html');
      debugPrint('[Fan2d] 容器子元素数量: ${contentDiv.children.length}');
      for (final child in contentDiv.children) {
        debugPrint('[Fan2d]   子元素: <${child.localName}> class="${child.className}" text="${child.text.substring(0, child.text.length > 50 ? 50 : child.text.length)}..."');
      }
    }

    // 递归提取所有文本内容
    _extractElement(contentDiv, buffer);

    final result = buffer.toString().trim();
    if (kDebugMode) debugPrint('[Fan2d] 提取到 ${result.length} 字符内容');
    return result;
  }

  void _extractElement(dynamic element, StringBuffer buffer) {
    for (final child in element.children) {
      final tag = child.localName;
      if (tag == 'p') {
        final img = child.querySelector('img');
        if (img != null) {
          var src = img.attributes['data-original'] ?? img.attributes['data-src'] ?? img.attributes['src'] ?? '';
          if (src.startsWith('//')) src = 'https:$src';
          if (src.isNotEmpty) buffer.write('\n![图片]($src)\n');
        } else {
          final text = _cleanText(child.text);
          if (text.isNotEmpty) buffer.write('$text\n\n');
        }
      } else if (tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4') {
        final level = tag.substring(1);
        buffer.write('\n${'#' * int.parse(level)} ${_cleanText(child.text)}\n\n');
      } else if (tag == 'ul' || tag == 'ol') {
        for (final li in child.querySelectorAll('li')) {
          buffer.write('- ${_cleanText(li.text)}\n');
        }
        buffer.write('\n');
      } else if (tag == 'table') {
        _extractTable(child, buffer);
      } else if (tag == 'div' || tag == 'section' || tag == 'article' || tag == 'td') {
        _extractElement(child, buffer);
      } else if (tag == 'img') {
        var src = child.attributes['data-original'] ?? child.attributes['data-src'] ?? child.attributes['src'] ?? '';
        if (src.startsWith('//')) src = 'https:$src';
        if (src.isNotEmpty) buffer.write('\n![图片]($src)\n');
      } else if (tag == 'br') {
        buffer.write('\n');
      }
    }
  }

  void _extractTable(dynamic table, StringBuffer buffer) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return;

    buffer.write('\n');
    for (final row in rows) {
      final cells = row.querySelectorAll('td, th');
      if (cells.isEmpty) continue;

      final cellTexts = <String>[];
      for (final cell in cells) {
        cellTexts.add(_cleanText(cell.text));
      }
      buffer.write('${cellTexts.join(" | ")}\n');
    }
    buffer.write('\n');
  }

  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .trim();
  }

  /// 下载存档并导入到游戏的备份目录
  /// 遇到 kind 页面时返回存档列表供用户选择
  Future<Fan2dDownloadResult> downloadAndImport({
    required String downloadPageUrl,
    required String gamePath,
  }) async {
    if (kDebugMode) debugPrint('[Fan2d] 下载: $downloadPageUrl');

    final resolveResult = await _resolveDirectDownloadUrl(downloadPageUrl);

    if (resolveResult == null) {
      if (kDebugMode) debugPrint('[Fan2d] 未找到直连下载链接');
      return Fan2dDownloadResult.empty();
    }

    // 如果是 kind 页面，返回存档列表让用户选择
    if (resolveResult.hasSaveFiles) {
      if (kDebugMode) debugPrint('[Fan2d] kind 页面，${resolveResult.saveFiles.length} 个存档待选');
      return Fan2dDownloadResult.saveFiles(resolveResult.saveFiles);
    }

    final directUrl = resolveResult.directUrl;
    if (directUrl == null) return Fan2dDownloadResult.empty();

    return Fan2dDownloadResult.entry(await _doDownloadAndImport(directUrl, gamePath));
  }

  /// 下载指定的存档文件并导入
  Future<BackupEntry?> downloadSaveFile({
    required String saveFileUrl,
    required String gamePath,
  }) async {
    if (kDebugMode) debugPrint('[Fan2d] 下载存档: $saveFileUrl');
    final resolveResult = await _resolveDirectDownloadUrl(saveFileUrl);
    final directUrl = resolveResult?.directUrl;
    if (directUrl == null) {
      if (kDebugMode) debugPrint('[Fan2d] 未找到直连下载链接');
      return null;
    }
    return _doDownloadAndImport(directUrl, gamePath);
  }

  Future<BackupEntry?> _doDownloadAndImport(String directUrl, String gamePath) async {
    if (kDebugMode) debugPrint('[Fan2d] 直连: $directUrl');

    final tempDir = await Directory.systemTemp.createTemp('fan2d_');
    final rarPath = '${tempDir.path}${Platform.pathSeparator}download.rar';

    try {
      final client = await createProxyClientFromPrefs(domain: Uri.parse(directUrl).host);
      try {
        final headers = await buildScrapeHeaders(directUrl);
        final response = await client.get(
          Uri.parse(directUrl),
          headers: headers,
        ).timeout(const Duration(minutes: 5));
        await File(rarPath).writeAsBytes(response.bodyBytes);
      } finally {
        client.close();
      }

      if (kDebugMode) debugPrint('[Fan2d] 下载完成: $rarPath');

      final extractDir = '${tempDir.path}${Platform.pathSeparator}extracted';
      await Directory(extractDir).create(recursive: true);

      final success = await _extractRar(rarPath, extractDir);
      if (!success) {
        if (kDebugMode) debugPrint('[Fan2d] 解压失败');
        return null;
      }

      final backupService = BackupService();
      final entry = await backupService.importBackup(
        gamePath: gamePath,
        sourcePath: extractDir,
        targetName: '下载存档',
      );
      return entry;
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // 临时目录清理失败时忽略
      }
    }
  }

  /// 解析下载页面，获取直连下载地址或 kind 页面的存档列表
  Future<_ResolveResult?> _resolveDirectDownloadUrl(String pageUrl) async {
    final client = await createProxyClientFromPrefs(domain: Uri.parse(pageUrl).host);
    try {
      final headers = await buildScrapeHeaders(pageUrl);
      final response = await client.get(
        Uri.parse(pageUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;
      return _parseDownloadLink(response.body, pageUrl);
    } catch (e) {
      if (kDebugMode) debugPrint('[Fan2d] 解析下载页面异常: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// 从 HTML 中解析下载链接
  /// 优先找"直连下载"，其次判断是否为 kind 页面（含多个存档），最后找 /kind/ 链接
  _ResolveResult? _parseDownloadLink(String html, String pageUrl) {
    final document = html_parser.parse(html);

    // 1. 查找"直连下载"链接
    final links = document.querySelectorAll('a');
    for (final link in links) {
      final text = link.text.trim();
      if (text.contains('直连下载')) {
        final href = link.attributes['href'] ?? '';
        if (href.isNotEmpty) {
          final resolved = _resolveUrl(pageUrl, href);
          if (kDebugMode) debugPrint('[Fan2d] 找到直连下载: $resolved');
          return _ResolveResult.direct(resolved);
        }
      }
    }

    // 2. 检查是否为 kind 页面（含多个具体存档列表）
    final downloadItems = document.querySelectorAll('ul.download-list li.media');
    if (downloadItems.isNotEmpty) {
      final saveFiles = <Fan2dSaveFile>[];
      for (final item in downloadItems) {
        final titleEl = item.querySelector('h4.media-heading a');
        final title = titleEl?.text.trim() ?? '';
        final href = titleEl?.attributes['href'] ?? '';
        if (title.isNotEmpty && href.isNotEmpty) {
          saveFiles.add(Fan2dSaveFile(
            title: title,
            downloadUrl: _resolveUrl(pageUrl, href),
          ));
        }
      }
      if (saveFiles.isNotEmpty) {
        if (kDebugMode) debugPrint('[Fan2d] kind 页面，找到 ${saveFiles.length} 个存档');
        return _ResolveResult.saveFiles(saveFiles);
      }
    }

    // 3. 查找 /kind/ 链接并递归
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      if (href.contains('/kind/')) {
        final resolved = _resolveUrl(pageUrl, href);
        if (kDebugMode) debugPrint('[Fan2d] 中间页: $resolved');
        return null; // 返回 null，调用方会处理
      }
    }

    return null;
  }

  String _resolveUrl(String baseUrl, String href) {
    if (href.startsWith('http')) return href;
    final uri = Uri.parse(baseUrl);
    if (href.startsWith('/')) {
      return '${uri.scheme}://${uri.host}$href';
    }
    return '${uri.scheme}://${uri.host}/${uri.path.substring(0, uri.path.lastIndexOf('/') + 1)}$href';
  }

  /// 使用系统 WinRAR 解压 RAR 文件
  Future<bool> _extractRar(String rarPath, String extractDir) async {
    final winrarPaths = [
      r'C:\Program Files\WinRAR\UnRAR.exe',
      r'C:\Program Files (x86)\WinRAR\UnRAR.exe',
      r'D:\Program Files\WinRAR\UnRAR.exe',
      r'D:\Program Files (x86)\WinRAR\UnRAR.exe',
    ];

    String? unrarPath;
    for (final p in winrarPaths) {
      if (File(p).existsSync()) {
        unrarPath = p;
        break;
      }
    }

    final executable = unrarPath ?? 'unrar';
    final args = ['x', '-o+', '-y', rarPath, '$extractDir${Platform.pathSeparator}'];

    if (kDebugMode) debugPrint('[Fan2d] 解压: $executable ${args.join(' ')}');

    try {
      final result = await Process.run(executable, args)
          .timeout(const Duration(seconds: 60));
      if (kDebugMode) {
        debugPrint('[Fan2d] 解压退出码: ${result.exitCode}');
        if (result.stdout.toString().isNotEmpty) {
          debugPrint('[Fan2d] stdout: ${result.stdout}');
        }
        if (result.stderr.toString().isNotEmpty) {
          debugPrint('[Fan2d] stderr: ${result.stderr}');
        }
      }
      return result.exitCode == 0;
    } catch (e) {
      if (kDebugMode) debugPrint('[Fan2d] 解压异常: $e');
      return false;
    }
  }
}
