import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/proxy_client.dart';
import '../../scraper/steam_html_converter.dart';
import 'app_logger.dart';
import 'concurrent_image_downloader.dart';
import 'version_check_service.dart';

class SteamService {
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

  static final _engineExePatterns = [
    'unity',
    'unreal',
    'godot',
    'renpy',
    'rpgmaker',
    'rpg_maker',
    'wolf',
    'wolfrpg',
  ];

  final _log = AppLogger.instance;

  Future<String?> extractGameName(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;

    String? gameName;
    final exeFiles = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.exe'))
        .toList();

    for (final exe in exeFiles) {
      final exeName = path.basename(exe.path).toLowerCase();
      final isGeneric = kGenericGameNames.any((w) => exeName.contains(w));
      if (isGeneric) continue;
      gameName = path.basenameWithoutExtension(exe.path);
      break;
    }

    gameName ??= path.basename(folderPath);
    gameName = gameName.replaceAll('_', ' ');
    return _cleanGameName(gameName);
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

  String buildSmartSearchName(String name) {
    var result = name.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    result = result.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return result;
  }

  Future<String?> findSteamAppId(String folderPath) async {
    final file = File(path.join(folderPath, 'steam_appid.txt'));
    if (await file.exists()) {
      final content = (await file.readAsString()).trim();
      if (content.isNotEmpty && RegExp(r'^\d+$').hasMatch(content)) {
        return content;
      }
    }
    return null;
  }

  Future<List<SteamSearchResult>> search(String keyword) async {
    final url = 'https://store.steampowered.com/api/storesearch/?term=${Uri.encodeComponent(keyword)}&l=zh&cc=US';

    _log.info('SteamService', '[search] 搜索关键词: "$keyword"');

    final client = await createProxyClientFromPrefs();
    try {
      final response = await client.get(Uri.parse(url), headers: {
        'Accept-Language': 'zh-CN,zh;q=0.9',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _log.warning('SteamService', '[search] 搜索失败: HTTP ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      final items = data['items'] as List<dynamic>? ?? [];

      final results = items.map((item) => SteamSearchResult(
        id: item['id'].toString(),
        name: item['name'] as String?,
        tinyImage: item['tiny_image'] as String?,
      )).toList();

      _log.info('SteamService', '[search] 找到 ${results.length} 个结果');
      return results;
    } catch (e) {
      _log.error('SteamService', '[search] 搜索异常', e);
      return [];
    } finally {
      client.close();
    }
  }

  Future<List<SteamSearchResult>> searchWithFallback(String folderPath) async {
    _log.info('SteamService', '[searchWithFallback] ========== 开始搜索 ==========');

    final gameName = await extractGameName(folderPath);
    if (gameName == null || gameName.isEmpty) {
      _log.warning('SteamService', '[searchWithFallback] 无法提取游戏名');
      return [];
    }

    _log.info('SteamService', '[searchWithFallback] 提取的游戏名: "$gameName"');

    // Step 1: Direct search with full name
    _log.info('SteamService', '[searchWithFallback] 第1轮搜索: "$gameName"');
    var results = await search(gameName);
    if (results.isNotEmpty) {
      _log.info('SteamService', '[searchWithFallback] 第1轮命中，搜索结束');
      return results;
    }

    // Step 2: Smart name construction
    final smartName = buildSmartSearchName(gameName);
    if (smartName != gameName) {
      _log.info('SteamService', '[searchWithFallback] 第2轮搜索(智能构建): "$smartName"');
      results = await search(smartName);
      if (results.isNotEmpty) {
        _log.info('SteamService', '[searchWithFallback] 第2轮命中，搜索结束');
        return results;
      }
    }

    // Step 3: Progressive word removal
    final parts = smartName.split(RegExp(r'\s+'));
    if (parts.length <= 1) {
      _log.info('SteamService', '[searchWithFallback] 只有一个词，无法继续缩短');
      return [];
    }

    for (int i = parts.length - 1; i >= 1; i--) {
      final shortened = parts.sublist(0, i).join(' ');
      _log.info('SteamService', '[searchWithFallback] 第${parts.length - i + 2}轮搜索: "$shortened"');
      results = await search(shortened);
      if (results.isNotEmpty) {
        _log.info('SteamService', '[searchWithFallback] 命中，搜索结束');
        return results;
      }
    }

    _log.info('SteamService', '[searchWithFallback] ========== 所有轮次均无结果 ==========');
    return [];
  }

  Future<SteamGameInfo?> fetchById(String id) async {
    final url = 'https://store.steampowered.com/api/appdetails/?appids=$id&l=zh';

    _log.info('SteamService', '[fetchById] 获取游戏信息: $id');

    final client = await createProxyClientFromPrefs();
    try {
      final response = await client.get(Uri.parse(url), headers: {
        'Accept-Language': 'zh-CN,zh;q=0.9',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _log.warning('SteamService', '[fetchById] 获取失败: HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      final appData = data[id];
      if (appData == null || appData['success'] != true) {
        _log.warning('SteamService', '[fetchById] API返回失败');
        return null;
      }

      final d = appData['data'];

      final title = d['name'] as String?;
      final shortDesc = d['short_description'] as String? ?? '';
      final detailedDesc = d['detailed_description'] as String? ?? '';

      final description = '$shortDesc\n\n${SteamHtmlConverter.convertToPlainText(detailedDesc)}';

      final genres = (d['genres'] as List<dynamic>? ?? [])
          .map((g) => g['description'] as String)
          .toList();

      final screenshots = <String>[];
      final headerImage = d['header_image'] as String?;
      if (headerImage != null && headerImage.isNotEmpty) {
        screenshots.add(headerImage);
      }
      for (final s in (d['screenshots'] as List<dynamic>? ?? [])) {
        final url = s['path_full'] as String?;
        if (url != null && url.isNotEmpty) {
          screenshots.add(url);
        }
      }

      final sourceUrl = 'https://store.steampowered.com/app/$id/';

      final developers = (d['developers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();

      _log.info('SteamService', '[fetchById] 解析成功: $title, 标签${genres.length}个, 截图${screenshots.length}张');

      return SteamGameInfo(
        title: title,
        description: description,
        tags: genres,
        screenshots: screenshots,
        sourceUrl: sourceUrl,
        developers: developers,
      );
    } catch (e) {
      _log.error('SteamService', '[fetchById] 获取异常', e);
      return null;
    } finally {
      client.close();
    }
  }

  Future<Map<String, String>> downloadAllImages(List<String> imageUrls, String saveDir) async {
    final imageHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Referer': 'https://store.steampowered.com/',
    };
    return await ConcurrentImageDownloader.downloadAll(
      imageUrls: imageUrls,
      saveDir: saveDir,
      headers: imageHeaders,
      maxConcurrency: 3,
    );
  }

  /// Extract [视频:url] markers from description text
  List<String> extractVideoUrls(String description) {
    final pattern = RegExp(r'\[视频:(https?://[^\]]+)\]');
    return pattern.allMatches(description).map((m) => m.group(1)!).toList();
  }

  /// Download videos found in description and return URL→localPath mapping
  Future<Map<String, String>> downloadVideosFromDescription(
      String description, String saveDir) async {
    final videoUrls = extractVideoUrls(description);
    final urlToLocal = <String, String>{};
    if (videoUrls.isEmpty) return urlToLocal;

    final imagesDir = Directory(path.join(saveDir, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    _log.info('SteamService',
        '[downloadVideos] 开始下载 ${videoUrls.length} 个视频');

    final client = await createProxyClientFromPrefs();
    try {
      for (int i = 0; i < videoUrls.length; i++) {
        final videoUrl = videoUrls[i];
        try {
          final response = await client
              .get(Uri.parse(videoUrl))
              .timeout(const Duration(seconds: 120));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            final ext = _getVideoExtension(videoUrl);
            final fileName = 'video_${i + 1}$ext';
            final filePath = path.join(imagesDir.path, fileName);
            await File(filePath).writeAsBytes(response.bodyBytes, flush: true);
            urlToLocal[videoUrl] = filePath;
            _log.info('SteamService',
                '[downloadVideos] 视频${i + 1} 下载成功: $fileName');
          }
        } catch (e) {
          _log.warning(
              'SteamService', '[downloadVideos] 视频${i + 1} 下载异常: $e');
        }
      }
    } finally {
      client.close();
    }

    _log.info('SteamService',
        '[downloadVideos] 下载完成: ${urlToLocal.length}/${videoUrls.length}');
    return urlToLocal;
  }

  String _getVideoExtension(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '.webm';
    final ext = path.extension(uri.path).split('?').first.toLowerCase();
    if (['.webm', '.mp4', '.avi', '.mkv'].contains(ext)) return ext;
    return '.webm';
  }
}

class SteamSearchResult {
  final String id;
  final String? name;
  final String? tinyImage;

  SteamSearchResult({required this.id, this.name, this.tinyImage});
}

class SteamGameInfo {
  final String? title;
  final String? description;
  final List<String> tags;
  final List<String> screenshots;
  final String sourceUrl;
  final List<String> developers;

  SteamGameInfo({
    this.title,
    this.description,
    this.tags = const [],
    this.screenshots = const [],
    required this.sourceUrl,
    this.developers = const [],
  });
}
