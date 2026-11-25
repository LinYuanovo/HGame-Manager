import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../utils/game_data_paths.dart';
import '../utils/proxy_client.dart';
import 'app_logger.dart';
import 'image_service.dart';

enum _DownloadStatus { saved, missing, failed }

class ConcurrentImageDownloader {
  static final _log = AppLogger.instance;

  static Future<Map<String, String>> downloadAll({
    required List<String> imageUrls,
    required String saveDir,
    Map<String, String>? headers,
    int maxConcurrency = 3,
    int startIndex = 0,
    bool useTempFiles = false,
    void Function(int completed, int total)? onProgress,
    void Function(String url)? onMissing,
  }) async {
    final urlToLocal = <String, String>{};
    if (imageUrls.isEmpty) return urlToLocal;

    final imagesDir = await GameDataPaths.ensureImagesDir(saveDir);

    _log.info('ImageDownloader',
        '开始并发下载 ${imageUrls.length} 张图片，并发数: $maxConcurrency');

    int activeCount = 0;
    int completedCount = 0;
    bool degraded = false;
    final completer = Completer<void>();
    final queue = List.generate(imageUrls.length, (i) => i);

    void processNext() {
      if (queue.isEmpty) {
        if (activeCount == 0 && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final idx = queue.removeAt(0);
      activeCount++;
      final url = imageUrls[idx];
      final ext = _getExtensionFromUrl(url);
      final suffix = useTempFiles ? '.tmp' : '';
      final savePath = path.join(imagesDir.path,
          '${GameDataPaths.scrapeImagePrefix}${idx + 1 + startIndex}$suffix$ext');
      _downloadSingle(
        url: url,
        savePath: savePath,
        headers: headers,
      ).then((status) {
        activeCount--;
        completedCount++;
        onProgress?.call(completedCount, imageUrls.length);
        if (status == _DownloadStatus.saved) {
          urlToLocal[url] = savePath;
        } else if (status == _DownloadStatus.missing) {
          onMissing?.call(url);
        }
        _log.info('ImageDownloader', '进度: $completedCount/${imageUrls.length}');

        if (!degraded && status == _DownloadStatus.failed) {
          degraded = true;
          _log.warning('ImageDownloader', '下载失败，降级为单线程模式');
        }

        if (degraded) {
          if (activeCount == 0) {
            processNext();
          }
        } else {
          processNext();
        }
      });
    }

    final initialCount = maxConcurrency.clamp(1, imageUrls.length);
    for (int i = 0; i < initialCount; i++) {
      processNext();
    }

    await completer.future;
    _log.info(
        'ImageDownloader', '下载完成: ${urlToLocal.length}/${imageUrls.length}');
    return urlToLocal;
  }

  static Future<_DownloadStatus> _downloadSingle({
    required String url,
    required String savePath,
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.tryParse(url);
      final domain = uri?.host;
      final requestHeaders = headers == null
          ? <String, String>{
              'User-Agent': defaultScrapeUserAgent,
              'Accept':
                  'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            }
          : scopeScrapeImageHeaders(url, headers);
      final client = await createProxyClientFromPrefs(domain: domain);
      try {
        var response = await client
            .get(
              Uri.parse(url),
              headers: requestHeaders,
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 429) {
          _log.warning('ImageDownloader', '429 限流: $url');
          await Future.delayed(const Duration(seconds: 5));
          response = await client
              .get(
                Uri.parse(url),
                headers: requestHeaders,
              )
              .timeout(const Duration(seconds: 30));
        }

        final code = response.statusCode;
        if (code == HttpStatus.notFound || code == HttpStatus.gone) {
          _log.warning('ImageDownloader', '源站图片不存在，已跳过 (HTTP $code): $url');
          return _DownloadStatus.missing;
        }
        if (code != HttpStatus.ok || response.bodyBytes.isEmpty) {
          _log.warning('ImageDownloader',
              '图片下载失败 (HTTP $code${code == HttpStatus.ok ? '，响应为空' : ''}): $url');
          return _DownloadStatus.failed;
        }
        await File(savePath).writeAsBytes(response.bodyBytes, flush: true);
        await ImageService.invalidateFileCache(savePath);
        return _DownloadStatus.saved;
      } finally {
        client.close();
      }
    } catch (e) {
      _log.warning('ImageDownloader', '下载异常: $url $e');
      return _DownloadStatus.failed;
    }
  }

  static String _getExtensionFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '.jpg';
    final ext = path.extension(uri.path).split('?').first.toLowerCase();
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) return ext;
    return '.jpg';
  }
}
