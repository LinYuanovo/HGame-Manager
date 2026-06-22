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
    'player.exe',
    'play.exe',
    'start.exe',
    'startup.exe',
    'config.exe',
    'setup.exe',
    'install.exe',
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
    'server.exe',
    'client.exe',
    'update.exe',
    'updater.exe',
    'tool.exe',
    'tools.exe',
    'editor.exe',
    'viewer.exe',
    'helper.exe',
    'crashreport.exe',
    'bugreport.exe',
    'feedback.exe',
  ];

  final _scraper = HtmlScraper();
  final _log = AppLogger.instance;

  String? normalizeId(String input) {
    final trimmed = input.trim();
    
    // 尝试从URL中提取ID
    final urlMatch = RegExp(r'(RJ|RE|VJ)\d{4,}', caseSensitive: false).firstMatch(trimmed);
    if (urlMatch != null) {
      return urlMatch.group(0)!.toUpperCase();
    }
    
    // 直接匹配ID格式
    final match = _idPattern.firstMatch(trimmed);
    if (match == null) return null;
    return match.group(0)!.toUpperCase();
  }

  String buildUrl(String id) {
    if (id.startsWith('VJ')) {
      return 'https://www.dlsite.com/pro/work/=/product_id/$id.html/?locale=zh_CN';
    }
    return 'https://www.dlsite.com/maniax/work/=/product_id/$id.html/?locale=zh_CN';
  }

  /// 从文件夹提取DLsite ID或游戏名
  /// 优先从文件夹名中提取ID（RJ/RE/VJ+数字）
  /// 如果没有ID，返回清理后的游戏名用于搜索
  Future<String?> extractIdOrGameName(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      _log.info('DlsiteService', '[extractIdOrGameName] 目录不存在: $folderPath');
      return null;
    }

    final folderName = path.basename(folderPath);
    _log.info('DlsiteService', '[extractIdOrGameName] 文件夹名: "$folderName"');

    // 1. 先检查文件夹名中是否包含DLsite ID
    final idFromFolder = normalizeId(folderName);
    if (idFromFolder != null) {
      _log.info('DlsiteService', '[extractIdOrGameName] 从文件夹名提取到ID: $idFromFolder');
      return idFromFolder;
    }

    // 2. 尝试从exe名提取游戏名
    String? gameName;
    String? source;
    final exeFiles = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    _log.info('DlsiteService', '[extractIdOrGameName] 找到 ${exeFiles.length} 个exe文件');

    for (final exe in exeFiles) {
      final exeName = path.basename(exe.path).toLowerCase();
      if (_commonExeNames.contains(exeName)) {
        _log.info('DlsiteService', '[extractIdOrGameName] 跳过通用exe: $exeName');
        continue;
      }
      if (exeName.contains('unity') ||
          exeName.contains('unreal') ||
          exeName.contains('godot') ||
          exeName.contains('renpy')) {
        _log.info('DlsiteService', '[extractIdOrGameName] 跳过引擎exe: $exeName');
        continue;
      }
      
      // 检查exe名是否包含ID
      final exeBaseName = path.basenameWithoutExtension(exe.path);
      final idFromExe = normalizeId(exeBaseName);
      if (idFromExe != null) {
        _log.info('DlsiteService', '[extractIdOrGameName] 从exe名提取到ID: $idFromExe');
        return idFromExe;
      }
      
      gameName = exeBaseName;
      source = 'exe: ${path.basename(exe.path)}';
      break;
    }

    // 3. 回退到文件夹名
    if (gameName == null) {
      gameName = folderName;
      source = '文件夹名';
    }

    _log.info('DlsiteService', '[extractIdOrGameName] 原始名称: "$gameName" (来源: $source)');

    // 4. 下划线替换为空格
    gameName = gameName.replaceAll('_', ' ');
    _log.info('DlsiteService', '[extractIdOrGameName] 下划线替换后: "$gameName"');

    // 5. 清理版本号和括号
    final cleaned = _cleanGameName(gameName);
    _log.info('DlsiteService', '[extractIdOrGameName] 清理后: "$cleaned"');

    return cleaned.isEmpty ? null : cleaned;
  }

  /// 从文件夹提取游戏名（仅用于搜索，不提取ID）
  Future<String?> extractGameName(String folderPath) async {
    final result = await extractIdOrGameName(folderPath);
    // 如果返回的是ID格式，说明应该用ID直接获取，不需要搜索
    if (result != null && normalizeId(result) != null) {
      return null; // 返回null表示应该用ID
    }
    return result;
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

  /// 使用关键词搜索，支持回退搜索
  /// 用于用户手动输入的关键词
  Future<List<DlsiteSearchResult>> searchWithKeyword(String keyword) async {
    _log.info('DlsiteService', '[searchWithKeyword] ========== 关键词搜索 ==========');
    _log.info('DlsiteService', '[searchWithKeyword] 输入关键词: "$keyword"');

    // 清理关键词
    final cleaned = keyword.replaceAll('_', ' ').trim();
    _log.info('DlsiteService', '[searchWithKeyword] 清理后: "$cleaned"');

    if (cleaned.isEmpty) return [];

    // 第一步：直接用完整关键词搜索
    _log.info('DlsiteService', '[searchWithKeyword] 第1轮搜索: "$cleaned"');
    final results = await search(cleaned);
    if (results.isNotEmpty) {
      _log.info('DlsiteService', '[searchWithKeyword] 第1轮命中 ${results.length} 个结果，搜索结束');
      return results;
    }
    _log.info('DlsiteService', '[searchWithKeyword] 第1轮无结果');

    // 第二步：按空格分词，逐步去掉后面的词
    final parts = cleaned.split(RegExp(r'\s+'));
    _log.info('DlsiteService', '[searchWithKeyword] 分词结果: $parts (${parts.length}个词)');

    if (parts.length <= 1) {
      _log.info('DlsiteService', '[searchWithKeyword] 只有一个词，无法继续缩短，搜索结束');
      return [];
    }

    // 从少一个词开始，逐步缩短
    for (int i = parts.length - 1; i >= 1; i--) {
      final shortened = parts.sublist(0, i).join(' ');
      _log.info('DlsiteService', '[searchWithKeyword] 第${parts.length - i + 1}轮搜索: "$shortened"');
      final partialResults = await search(shortened);
      if (partialResults.isNotEmpty) {
        _log.info('DlsiteService', '[searchWithKeyword] 命中 ${partialResults.length} 个结果，搜索结束');
        return partialResults;
      }
      _log.info('DlsiteService', '[searchWithKeyword] 无结果');
    }

    _log.info('DlsiteService', '[searchWithKeyword] ========== 所有轮次均无结果 ==========');
    return [];
  }

  Future<List<DlsiteSearchResult>> search(String keyword) async {
    final encodedKeyword = Uri.encodeComponent(keyword);
    final url = 'https://www.dlsite.com/maniax/fsr/=/language/jp/keyword/$encodedKeyword/';

    _log.info('DlsiteService', '[search] 搜索关键词: "$keyword"');
    _log.info('DlsiteService', '[search] 请求URL: $url');

    try {
      final client = await createProxyClientFromPrefs();
      final headers = await _buildHeaders();
      var response = await client.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      _log.info('DlsiteService', '[search] HTTP状态码: ${response.statusCode}');

      // 403时将空格替换为+号重试
      if (response.statusCode == 403 && keyword.contains(' ')) {
        final retryKeyword = keyword.replaceAll(' ', '+');
        final retryUrl = 'https://www.dlsite.com/maniax/fsr/=/language/jp/keyword/$retryKeyword/';
        _log.info('DlsiteService', '[search] 403被拒绝，空格替换为+号重试: "$retryKeyword"');
        _log.info('DlsiteService', '[search] 重试URL: $retryUrl');
        response = await client.get(Uri.parse(retryUrl), headers: headers)
            .timeout(const Duration(seconds: 15));
        _log.info('DlsiteService', '[search] 重试HTTP状态码: ${response.statusCode}');
      }

      client.close();

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
  /// 1. 如果文件夹名中包含ID（RJ/RE/VJ+数字），直接返回
  /// 2. 直接用游戏名搜索（搜到即停）
  /// 3. 搜不到按照空格分词，倒序依次去掉后面的词搜索（中途命中即停）
  ///
  /// 例如游戏名 "Game Name 2"：
  /// - 搜索 "Game Name 2" → 无结果
  /// - 搜索 "Game Name" → 无结果
  /// - 搜索 "Game" → 有结果，停止
  Future<List<DlsiteSearchResult>> searchWithFallback(String folderPath) async {
    _log.info('DlsiteService', '[searchWithFallback] ========== 开始搜索 ==========');
    _log.info('DlsiteService', '[searchWithFallback] 文件夹: $folderPath');

    final idOrName = await extractIdOrGameName(folderPath);
    if (idOrName == null || idOrName.isEmpty) {
      _log.warning('DlsiteService', '[searchWithFallback] 无法提取游戏名或ID，终止搜索');
      return [];
    }

    // 检查是否直接返回了ID
    final directId = normalizeId(idOrName);
    if (directId != null) {
      _log.info('DlsiteService', '[searchWithFallback] 检测到ID: $directId，直接返回');
      return [DlsiteSearchResult(id: directId, name: 'ID: $directId')];
    }

    final gameName = idOrName;
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

  /// 下载所有图片（封面+截图）到images文件夹
  /// 返回 URL -> 本地路径 的映射
  Future<Map<String, String>> downloadAllImages(List<String> imageUrls, String saveDir) async {
    final urlToLocal = <String, String>{};
    if (imageUrls.isEmpty) return urlToLocal;

    final imagesDir = Directory(path.join(saveDir, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    _log.info('DlsiteService', '[downloadAllImages] 开始下载 ${imageUrls.length} 张图片');

    final client = await createProxyClientFromPrefs();
    final headers = await _buildImageHeaders();

    for (int i = 0; i < imageUrls.length; i++) {
      final imageUrl = imageUrls[i];
      try {
        final response = await client.get(Uri.parse(imageUrl), headers: headers)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final ext = _getExtensionFromUrl(imageUrl);
          final fileName = '${i + 1}$ext';
          final filePath = path.join(imagesDir.path, fileName);
          await File(filePath).writeAsBytes(response.bodyBytes, flush: true);
          urlToLocal[imageUrl] = filePath;
          _log.info('DlsiteService', '[downloadAllImages] 图片${i + 1} 下载成功: $fileName');
        } else {
          _log.warning('DlsiteService', '[downloadAllImages] 图片${i + 1} 下载失败: HTTP ${response.statusCode}');
        }
      } catch (e) {
        _log.warning('DlsiteService', '[downloadAllImages] 图片${i + 1} 下载异常: $e');
      }
    }

    client.close();
    _log.info('DlsiteService', '[downloadAllImages] 下载完成: ${urlToLocal.length}/${imageUrls.length}');
    return urlToLocal;
  }

  /// 将描述中的图片URL替换为本地路径标记
  String replaceImageUrlsInDescription(String description, Map<String, String> urlToLocal) {
    var result = description;
    for (final entry in urlToLocal.entries) {
      result = result.replaceAll('[图片:${entry.key}]', '[图片:${entry.value}]');
    }
    return result;
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
