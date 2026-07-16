import 'dart:io';

import 'package:path/path.dart' as path;

import 'game_data_paths.dart';

class ScrapedImageFileCleaner {
  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
  };

  static Future<int> cleanUnusedNumberedImages({
    required String gamePath,
    required Iterable<String> retainedImagePaths,
    required Iterable<String?> referenceTexts,
  }) async {
    final retained = retainedImagePaths
        .where((value) => value.isNotEmpty)
        .map(_normalizePath)
        .toSet();
    if (retained.isEmpty) return 0;

    final imagesDir = GameDataPaths.imagesDir(gamePath);
    if (!await imagesDir.exists()) return 0;

    var deleted = 0;
    await for (final entity in imagesDir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.tmp')) continue;
      if (!_isNumberedImage(entity.path)) continue;
      if (retained.contains(_normalizePath(entity.path))) continue;
      if (_isReferenced(entity.path, referenceTexts)) continue;

      await entity.delete();
      deleted++;
    }
    return deleted;
  }

  static bool _isNumberedImage(String filePath) {
    final stem = path.basenameWithoutExtension(filePath);
    final ext = path.extension(filePath).toLowerCase();
    return int.tryParse(stem) != null && _imageExtensions.contains(ext);
  }

  static bool _isReferenced(String filePath, Iterable<String?> texts) {
    final variants = {
      filePath,
      filePath.replaceAll('\\', '/'),
      filePath.replaceAll('\\', '\\\\'),
    };
    for (final text in texts) {
      if (text == null || text.isEmpty) continue;
      if (variants.any(text.contains)) return true;
    }
    return false;
  }

  static String _normalizePath(String value) =>
      path.normalize(value).toLowerCase();
}
