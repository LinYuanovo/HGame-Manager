import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/proxy_client.dart';
import '../../scraper/html_parser.dart';
import '../../scraper/parse_utils.dart';
import 'app_logger.dart';
import 'package:html/parser.dart' as html_parser;

class DlsiteService {
  static final _idPattern = RegExp(r'\b(RJ|RE|VJ)\d{4,}\b', caseSensitive: false);
  static final _commonExeNames = [
    'unitycrashhandler64.exe',
    'unitycrashhandler32.exe',
    'crashpad_handler.exe',
    'crash_handler.exe',
    'game.exe',
    'launch.exe',
    'launcher.exe',
    'setup.exe',
    'uninstall.exe',
    'unins000.exe',
    'unins001.exe',
    'nw.exe',
    'cef_simple.exe',
    'renderdoc.exe',
    'vcredist_x64.exe',
    'vcredist_x86.exe',
    'dxwebsetup.exe',
    'oalinst.exe',
  ];

  final _scraper = HtmlScraper();
  final _log = AppLogger.instance;

  String? normalizeId(String input) {
    final match = _idPattern.firstMatch(input);
    if (match == null) return null;
    return match.group(0)!.toUpperCase();
  }

  String buildUrl(String id) {
    if (id.startsWith('VJ')) {
      return 'https://www.dlsite.com/pro/work/=/product_id/$id.html/?locale=zh_CN';
    }
    return 'https://www.dlsite.com/maniax/work/=/product_id/$id.html/?locale=zh_CN';
  }

  /// 从文件夹提取游戏名
  /// 1. 下划线替换为空格
  /// 2. 清理版本号和括号
  String? extractGameName(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return null;

    // 尝试从exe名提取
    String? gameName;
    final exeFiles = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    for (final exe in exeFiles) {
      final exeName = path.basename(exe.path).toLowerCase();
      if (_commonExeNames.contains(exeName)) continue;
      if (exeName.contains('unity') ||
          exeName.contains('unreal') ||
          exeName.contains('godot') ||
          exeName.contains('renpy')) {
        continue;
      }
      gameName = path.basenameWithoutExtension(exe.path);
      break;
    }

    // 回退到文件夹名
    gameName ??= path.basename(folderPath);

    // 1. 下划线替换为空格
    gameName = gameName.replaceAll('_', ' ');

    // 2. 清理版本号和括号
    gameName = _cleanGameName(gameName);

    return gameName.isEmpty ? null : gameName;
  }

  String _cleanGameName(String name) {
    var cleaned = name.replaceAll(
      RegExp(r'\s*(?:[Vv](?:er(?:sion)?)?|build)\s*\.?\d+(?:[\d.]*\d+)?\s*', caseSensitive: false),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[\[【\(（].*?[\]】\)）]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return cleaned;
  }

  Future<List<DlsiteSearchResult>> search(String keyword) async {
    final encodedKeyword = Uri.encodeComponent(keyword);
    final url = 'https://www.dlsite.com/maniax/fsr/=/language/jp/keyword/$encodedKeyword/';

    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildHeaders();
      final response = await client.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      client.close();

      if (response.statusCode != 200) {
        _log.warning('DlsiteService', 'Search failed: HTTP ${response.statusCode}');
        return [];
      }

      return _parseSearchResults(response.body);
    } catch (e) {
      _log.error('DlsiteService', 'Search error', e);
      return [];
    }
  }

  /// 搜索游戏，支持回退搜索
  /// 1. 直接用游戏名搜索（搜到即停）
  /// 2. 搜不到按照空格分词，倒序依次去掉空格搜索（中途命中即停）
  ///
  /// 例如游戏名 "SiNiSistar 2"：
  /// - 搜索 "SiNiSistar 2" → 无结果
  /// - 搜索 "SiNiSistar2" → 有结果，停止
  Future<List<DlsiteSearchResult>> searchWithFallback(String folderPath) async {
    final gameName = extractGameName(folderPath);
    if (gameName == null || gameName.isEmpty) return [];

    // 第一步：直接用完整游戏名搜索
    final results = await search(gameName);
    if (results.isNotEmpty) return results;

    // 第二步：按空格分词，倒序去掉空格搜索
    final parts = gameName.split(RegExp(r'\s+'));
    if (parts.length <= 1) return [];

    // 从最后一个空格开始，逐步合并后面的词
    for (int i = parts.length - 1; i >= 1; i--) {
      // 合并：前i个部分保持空格，后面的部分合并
      final merged = [...parts.sublist(0, i), parts.sublist(i).join()].join(' ');
      if (merged == gameName) continue; // 跳过和原始相同的
      final partialResults = await search(merged);
      if (partialResults.isNotEmpty) return partialResults;
    }

    // 最后尝试全部合并（无空格）
    final fullMerged = parts.join();
    if (fullMerged != gameName) {
      final finalResults = await search(fullMerged);
      if (finalResults.isNotEmpty) return finalResults;
    }

    return [];
  }

  List<DlsiteSearchResult> _parseSearchResults(String html) {
    final results = <DlsiteSearchResult>[];
    final document = html_parser.parse(html);

    final items = document.querySelectorAll('.search_result_img_box_inner');
    for (final item in items) {
      String? id = item.attributes['data-list_item_product_id'];
      if (id == null || id.isEmpty) {
        final link = item.querySelector('a');
        if (link != null) {
          final href = link.attributes['href'] ?? '';
          final idMatch = RegExp(r'(RJ|RE|VJ)\d+').firstMatch(href);
          id = idMatch?.group(0);
        }
      }
      if (id == null || id.isEmpty) continue;

      final nameEl = item.querySelector('.work_name a');
      String? name = nameEl?.attributes['title'] ?? nameEl?.text.trim();

      results.add(DlsiteSearchResult(id: id.toUpperCase(), name: name));
    }

    return results;
  }

  Future<GameInfo?> fetchById(String id) async {
    final normalizedId = normalizeId(id);
    if (normalizedId == null) {
      _log.warning('DlsiteService', 'Invalid ID: $id');
      return null;
    }

    final url = buildUrl(normalizedId);
    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildHeaders();
      final response = await client.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      client.close();

      if (response.statusCode != 200) {
        _log.warning('DlsiteService', 'Fetch failed: HTTP ${response.statusCode}');
        return null;
      }

      final gameInfo = _scraper.scrapeGameInfo(response.body, url);
      return gameInfo;
    } catch (e) {
      _log.error('DlsiteService', 'Fetch error for $id', e);
      return null;
    }
  }

  Future<GameInfo?> fetchByName(String name) async {
    final results = await search(name);
    if (results.isEmpty) return null;

    final exactMatch = results.firstWhere(
      (r) => r.name?.toLowerCase() == name.toLowerCase(),
      orElse: () => results.first,
    );

    return fetchById(exactMatch.id);
  }

  /// 获取搜索结果的封面图URL
  Future<String?> fetchCoverUrl(String id) async {
    final normalizedId = normalizeId(id);
    if (normalizedId == null) return null;

    final url = buildUrl(normalizedId);
    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildHeaders();
      final response = await client.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      client.close();

      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      
      // 从product-slider-data获取
      final productSlider = document.querySelector('.product-slider-data');
      if (productSlider != null) {
        final firstSlide = productSlider.querySelector('div[data-src]');
        if (firstSlide != null) {
          final dataSrc = firstSlide.attributes['data-src'];
          if (dataSrc != null && dataSrc.isNotEmpty) {
            return dataSrc.startsWith('//') ? 'https:$dataSrc' : dataSrc;
          }
        }
      }

      // 回退到og:image
      return document.querySelector('meta[property="og:image"]')?.attributes['content'];
    } catch (e) {
      return null;
    }
  }

  Future<String?> downloadCoverImage(String imageUrl, String saveDir) async {
    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildImageHeaders();
      final response = await client.get(Uri.parse(imageUrl), headers: headers)
          .timeout(const Duration(seconds: 30));
      client.close();

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final ext = _getExtensionFromUrl(imageUrl);
        final filePath = path.join(saveDir, 'cover$ext');
        await File(filePath).writeAsBytes(response.bodyBytes, flush: true);
        return filePath;
      }
      return null;
    } catch (e) {
      _log.error('DlsiteService', 'Download cover error', e);
      return null;
    }
  }

  Future<List<String>> downloadScreenshots(List<String> imageUrls, String saveDir) async {
    final downloadedPaths = <String>[];
    final imagesDir = Directory(path.join(saveDir, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final client = await createProxyClientFromPrefs();
    final headers = await _buildImageHeaders();

    for (int i = 0; i < imageUrls.length; i++) {
      try {
        final response = await client.get(Uri.parse(imageUrls[i]), headers: headers)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final ext = _getExtensionFromUrl(imageUrls[i]);
          final filePath = path.join(imagesDir.path, '${i + 1}$ext');
          await File(filePath).writeAsBytes(response.bodyBytes, flush: true);
          downloadedPaths.add(filePath);
        }
      } catch (e) {
        _log.warning('DlsiteService', 'Failed to download image ${i + 1}: $e');
      }
    }

    client.close();
    return downloadedPaths;
  }

  String _getExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '.jpg';
    final ext = path.extension(uri.path).toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) return ext;
    return '.jpg';
  }

  Future<Map<String, String>> _buildHeaders() async {
    return {
      'User-Agent': 'HGame-Manager/1.0',
      'Cookie': 'adultchecked=1; locale=zh_CN',
      'Accept-Language': 'ja,en;q=0.8',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
  }

  Future<Map<String, String>> _buildImageHeaders() async {
    return {
      'User-Agent': 'HGame-Manager/1.0',
      'Referer': 'https://www.dlsite.com/',
    };
  }
}

class DlsiteSearchResult {
  final String id;
  final String? name;

  DlsiteSearchResult({required this.id, this.name});
}
