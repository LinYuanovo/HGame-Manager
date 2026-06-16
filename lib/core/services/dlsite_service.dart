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

  String? extractGameNameFromFolder(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return null;

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

      var gameName = path.basenameWithoutExtension(exe.path);
      gameName = _cleanGameName(gameName);
      if (gameName.isNotEmpty) return gameName;
    }

    final folderName = path.basename(folderPath);
    return _cleanGameName(folderName);
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
