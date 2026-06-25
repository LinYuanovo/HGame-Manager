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

  /// 解析下载页面的结果
  class _ResolveResult {
    final String? directUrl;
    final List<Fan2dSaveFile> saveFiles;
    bool get hasSaveFiles => saveFiles.isNotEmpty;
    _ResolveResult.direct(this.directUrl) : saveFiles = [];
    _ResolveResult.saveFiles(this.saveFiles) : directUrl = null;
  }

  /// 解析下载页面，获取直连下载地址或 kind 页面的存档列表
  Future<_ResolveResult?> _resolveDirectDownloadUrl(String pageUrl) async {
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
