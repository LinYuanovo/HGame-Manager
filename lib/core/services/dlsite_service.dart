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

  List<String> extractKeywords(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

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

    // 将下划线替换为空格
    gameName = gameName.replaceAll('_', ' ');

    // 清理版本号和括号
    gameName = _cleanGameName(gameName);
    if (gameName.isEmpty) return [];

    // 提取关键词（参考VersionCheckService）
    return _extractKeywords(gameName);
  }

  List<String> _extractKeywords(String title) {
    final tokens = title.split(RegExp(r'\s+'));

    const filterWords = ['官中', '+', '存档', '汉化', 'steam', '官方', '中文', '英文', '日文'];
    final filtered = tokens.where((t) {
      return !filterWords.any((w) => t.toLowerCase().contains(w.toLowerCase()));
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

    return merged.where((k) => k.isNotEmpty).toList();
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

  /// 搜索游戏，支持回退搜索（先完整关键词，再截断关键词）
  Future<List<DlsiteSearchResult>> searchWithFallback(String folderPath) async {
    final keywords = extractKeywords(folderPath);
    if (keywords.isEmpty) return [];

    // 第一轮：完整关键词搜索
    final allResults = <DlsiteSearchResult>[];
    final seenIds = <String>{};

    for (final keyword in keywords) {
      final results = await search(keyword);
      for (final r in results) {
        if (!seenIds.contains(r.id)) {
          seenIds.add(r.id);
          allResults.add(r);
        }
      }
    }

    if (allResults.isNotEmpty) return allResults;

    // 第二轮：截断关键词搜索（取前4个字符）
    final secondaryKeywords = keywords
        .where((k) => k.length > 4)
        .map((k) => k.substring(0, 4))
        .toList();

    for (final keyword in secondaryKeywords) {
      final results = await search(keyword);
      for (final r in results) {
        if (!seenIds.contains(r.id)) {
          seenIds.add(r.id);
          allResults.add(r);
        }
      }
    }

    return allResults;
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
      'Cookie': 'adultchecked=1; locale=ja',
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
