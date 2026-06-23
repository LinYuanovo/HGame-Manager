import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:html/parser.dart' as html_parser;
import '../models/backup_entry.dart';
import '../services/backup_service.dart';
import '../utils/proxy_client.dart';
import '../utils/app_settings.dart';

class Fan2dSearchResult {
  final String title;
  final String downloadUrl;

  Fan2dSearchResult({required this.title, required this.downloadUrl});
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
    final client = await createProxyClientFromPrefs();
    try {
      final headers = await buildScrapeHeaders('https://$_defaultDomain/domain');
      final response = await client.get(
        Uri.parse('https://$_defaultDomain/domain'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = response.body;
        // 纯正则匹配：从 <li> 行中提取包含"新增"或"中转"的域名
        final pattern = RegExp(r'<li>\s*(https?://[^\s<&]+)/?\s*(?:&nbsp;)?\s*(?:<span[^>]*>)?\s*(新增|中转)', caseSensitive: false);
        final domains = <String>[];
        final allMatches = pattern.allMatches(body).toList();
        if (kDebugMode) debugPrint('[Fan2d] 正则匹配到 ${allMatches.length} 个结果');
        for (final m in allMatches) {
          final fullMatch = m.group(0) ?? '';
          final url = m.group(1) ?? '';
          final tag = m.group(2) ?? '';
          final domain = url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');
          if (kDebugMode) {
            debugPrint('[Fan2d] fullMatch: "${fullMatch.length > 100 ? fullMatch.substring(0, 100) : fullMatch}"');
            debugPrint('[Fan2d] url="$url" tag="$tag" -> domain="$domain"');
            final start = (m.start - 80).clamp(0, body.length);
            final end = (m.end + 80).clamp(0, body.length);
            debugPrint('[Fan2d] context: "${body.substring(start, end)}"');
          }
          domains.add(domain);
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
          } catch (_) {}
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
      } catch (_) {}
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

  Future<List<Fan2dSearchResult>> _doSearch(String domain, String keyword) async {
    final url = 'https://$domain/subjects/search?keyword=${Uri.encodeComponent(keyword)}';
    if (kDebugMode) debugPrint('[Fan2d] 搜索: $url');

    final client = await createProxyClientFromPrefs();
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

  /// 下载存档并导入到游戏的备份目录
  Future<BackupEntry?> downloadAndImport({
    required String downloadPageUrl,
    required String gamePath,
  }) async {
    if (kDebugMode) debugPrint('[Fan2d] 下载: $downloadPageUrl');

    final directUrl = await _resolveDirectDownloadUrl(downloadPageUrl);
    if (directUrl == null) {
      if (kDebugMode) debugPrint('[Fan2d] 未找到直连下载链接');
      return null;
    }
    if (kDebugMode) debugPrint('[Fan2d] 直连: $directUrl');

    final tempDir = await Directory.systemTemp.createTemp('fan2d_');
    final rarPath = '${tempDir.path}${Platform.pathSeparator}download.rar';

    try {
      final client = await createProxyClientFromPrefs();
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
      } catch (_) {}
    }
  }

  /// 解析下载页面，获取直连下载地址
  Future<String?> _resolveDirectDownloadUrl(String pageUrl) async {
    final client = await createProxyClientFromPrefs();
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

  /// 从 HTML 中解析下载链接，递归处理 /kind/ 中间页
  Future<String?> _parseDownloadLink(String html, String pageUrl) async {
    final document = html_parser.parse(html);

    // 查找"直连下载"链接
    final links = document.querySelectorAll('a');
    for (final link in links) {
      final text = link.text.trim();
      if (text.contains('直连下载')) {
        final href = link.attributes['href'] ?? '';
        if (href.isNotEmpty) {
          final resolved = _resolveUrl(pageUrl, href);
          if (kDebugMode) debugPrint('[Fan2d] 找到直连下载: $resolved');
          return resolved;
        }
      }
    }

    // 没有"直连下载"，检查 /kind/ 链接并递归解析
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      if (href.contains('/kind/')) {
        final resolved = _resolveUrl(pageUrl, href);
        if (kDebugMode) debugPrint('[Fan2d] 中间页: $resolved');
        return _resolveDirectDownloadUrl(resolved);
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
