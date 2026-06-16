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
    if (!dir.existsSync()) {
      _log.info('DlsiteService', '[extractGameName] 目录不存在: $folderPath');
      return null;
    }

    // 尝试从exe名提取
    String? gameName;
    String? source;
    final exeFiles = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    _log.info('DlsiteService', '[extractGameName] 找到 ${exeFiles.length} 个exe文件');

    for (final exe in exeFiles) {
      final exeName = path.basename(exe.path).toLowerCase();
      if (_commonExeNames.contains(exeName)) {
        _log.info('DlsiteService', '[extractGameName] 跳过通用exe: $exeName');
        continue;
      }
      if (exeName.contains('unity') ||
          exeName.contains('unreal') ||
          exeName.contains('godot') ||
          exeName.contains('renpy')) {
        _log.info('DlsiteService', '[extractGameName] 跳过引擎exe: $exeName');
        continue;
      }
      gameName = path.basenameWithoutExtension(exe.path);
      source = 'exe: ${path.basename(exe.path)}';
      break;
    }

    // 回退到文件夹名
    if (gameName == null) {
      gameName = path.basename(folderPath);
      source = '文件夹名';
    }

    _log.info('DlsiteService', '[extractGameName] 原始名称: "$gameName" (来源: $source)');

    // 1. 下划线替换为空格
    gameName = gameName.replaceAll('_', ' ');
    _log.info('DlsiteService', '[extractGameName] 下划线替换后: "$gameName"');

    // 2. 清理版本号和括号
    final cleaned = _cleanGameName(gameName);
    _log.info('DlsiteService', '[extractGameName] 清理后: "$cleaned"');

    return cleaned.isEmpty ? null : cleaned;
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

    _log.info('DlsiteService', '[search] 搜索关键词: "$keyword"');
    _log.info('DlsiteService', '[search] 请求URL: $url');

    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildHeaders();
      final response = await client.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      client.close();

      _log.info('DlsiteService', '[search] HTTP状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        _log.warning('DlsiteService', '[search] 搜索失败: HTTP ${response.statusCode}');
        return [];
      }

      final results = _parseSearchResults(response.body);
      _log.info('DlsiteService', '[search] 解析到 ${results.length} 个结果');
      for (int i = 0; i < results.length && i < 5; i++) {
        _log.info('DlsiteService', '[search]   结果[$i]: ${results[i].id} - ${results[i].name}');
      }
      if (results.length > 5) {
        _log.info('DlsiteService', '[search]   ... 还有 ${results.length - 5} 个结果');
      }

      return results;
    } catch (e) {
      _log.error('DlsiteService', '[search] 搜索异常', e);
      return [];
    }
  }

  /// 搜索游戏，支持回退搜索
  /// 1. 直接用游戏名搜索（搜到即停）
  /// 2. 搜不到按照空格分词，倒序依次去掉后面的词搜索（中途命中即停）
  ///
  /// 例如游戏名 "Game Name 2"：
  /// - 搜索 "Game Name 2" → 无结果
  /// - 搜索 "Game Name" → 无结果
  /// - 搜索 "Game" → 有结果，停止
  Future<List<DlsiteSearchResult>> searchWithFallback(String folderPath) async {
    _log.info('DlsiteService', '[searchWithFallback] ========== 开始搜索 ==========');
    _log.info('DlsiteService', '[searchWithFallback] 文件夹: $folderPath');

    final gameName = extractGameName(folderPath);
    if (gameName == null || gameName.isEmpty) {
      _log.warning('DlsiteService', '[searchWithFallback] 无法提取游戏名，终止搜索');
      return [];
    }

    _log.info('DlsiteService', '[searchWithFallback] 提取的游戏名: "$gameName"');

    // 第一步：直接用完整游戏名搜索
    _log.info('DlsiteService', '[searchWithFallback] 第1轮搜索: "$gameName"');
    final results = await search(gameName);
    if (results.isNotEmpty) {
      _log.info('DlsiteService', '[searchWithFallback] 第1轮命中 ${results.length} 个结果，搜索结束');
      return results;
    }
    _log.info('DlsiteService', '[searchWithFallback] 第1轮无结果');

    // 第二步：按空格分词，逐步去掉后面的词
    final parts = gameName.split(RegExp(r'\s+'));
    _log.info('DlsiteService', '[searchWithFallback] 分词结果: $parts (${parts.length}个词)');

    if (parts.length <= 1) {
      _log.info('DlsiteService', '[searchWithFallback] 只有一个词，无法继续缩短，搜索结束');
      return [];
    }

    // 从少一个词开始，逐步缩短
    for (int i = parts.length - 1; i >= 1; i--) {
      final shortened = parts.sublist(0, i).join(' ');
      _log.info('DlsiteService', '[searchWithFallback] 第${parts.length - i + 1}轮搜索: "$shortened"');
      final partialResults = await search(shortened);
      if (partialResults.isNotEmpty) {
        _log.info('DlsiteService', '[searchWithFallback] 命中 ${partialResults.length} 个结果，搜索结束');
        return partialResults;
      }
      _log.info('DlsiteService', '[searchWithFallback] 无结果');
    }

    _log.info('DlsiteService', '[searchWithFallback] ========== 所有轮次均无结果 ==========');
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
      _log.warning('DlsiteService', '[fetchById] 无效的ID: $id');
      return null;
    }

    final url = buildUrl(normalizedId);
    _log.info('DlsiteService', '[fetchById] 获取游戏信息: $normalizedId');
    _log.info('DlsiteService', '[fetchById] 请求URL: $url');

    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildHeaders();
      final response = await client.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      client.close();

      _log.info('DlsiteService', '[fetchById] HTTP状态码: ${response.statusCode}');

      if (response.statusCode != 200) {
        _log.warning('DlsiteService', '[fetchById] 获取失败: HTTP ${response.statusCode}');
        return null;
      }

      final gameInfo = _scraper.scrapeGameInfo(response.body, url);
      if (gameInfo != null) {
        _log.info('DlsiteService', '[fetchById] 解析成功');
        _log.info('DlsiteService', '[fetchById]   标题: ${gameInfo.title}');
        _log.info('DlsiteService', '[fetchById]   标签: ${gameInfo.tags}');
        _log.info('DlsiteService', '[fetchById]   截图数: ${gameInfo.screenshots.length}');
        _log.info('DlsiteService', '[fetchById]   描述长度: ${gameInfo.description?.length ?? 0}');
      } else {
        _log.warning('DlsiteService', '[fetchById] 解析返回null');
      }

      return gameInfo;
    } catch (e) {
      _log.error('DlsiteService', '[fetchById] 获取异常', e);
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
