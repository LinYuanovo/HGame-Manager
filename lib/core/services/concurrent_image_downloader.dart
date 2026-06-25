import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../utils/proxy_client.dart';
import 'app_logger.dart';

class ConcurrentImageDownloader {
  static final _log = AppLogger.instance;

  static Future<Map<String, String>> downloadAll({
    required List<String> imageUrls,
    required String saveDir,
    Map<String, String>? headers,
    int maxConcurrency = 3,
    int startIndex = 0,
  }) async {
    final urlToLocal = <String, String>{};
    if (imageUrls.isEmpty) return urlToLocal;

    final imagesDir = Directory(path.join(saveDir, 'images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    _log.info('ImageDownloader', '开始并发下载 ${imageUrls.length} 张图片，并发数: $maxConcurrency');

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
      _downloadSingle(
        url: imageUrls[idx],
        savePath: path.join(imagesDir.path, '${idx + 1 + startIndex}${_getExtensionFromUrl(imageUrls[idx])}'),
        headers: headers,
      ).then((success) {
        activeCount--;
        completedCount++;
        if (success != null) {
          urlToLocal[imageUrls[idx]] = success;
        }
        _log.info('ImageDownloader', '进度: $completedCount/${imageUrls.length}');

        if (!degraded && success == null) {
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
    _log.info('ImageDownloader', '下载完成: ${urlToLocal.length}/${imageUrls.length}');
    return urlToLocal;
  }

  static Future<String?> _downloadSingle({
    required String url,
    required String savePath,
    Map<String, String>? headers,
  }) async {
    try {
      final client = await createProxyClientFromPrefs();
      try {
        final response = await client.get(
          Uri.parse(url),
          headers: headers ?? {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 429) {
          _log.warning('ImageDownloader', '429 限流: $url');
          await Future.delayed(const Duration(seconds: 5));
          final retryResponse = await client.get(
            Uri.parse(url),
            headers: headers,
          ).timeout(const Duration(seconds: 30));
          if (retryResponse.statusCode == 200 && retryResponse.bodyBytes.isNotEmpty) {
            await File(savePath).writeAsBytes(retryResponse.bodyBytes, flush: true);
            return savePath;
          }
          return null;
        }

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await File(savePath).writeAsBytes(response.bodyBytes, flush: true);
          return savePath;
        }
        return null;
      } finally {
        client.close();
      }
    } catch (e) {
      _log.warning('ImageDownloader', '下载异常: $e');
      return null;
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
