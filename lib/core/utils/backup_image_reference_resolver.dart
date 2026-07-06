import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/models.dart';
import 'media_reference_parser.dart';
import 'path_reference_rewriter.dart';

class BackupImageReferenceResolver {
  const BackupImageReferenceResolver._();

  static final _htmlImageSrcPattern = RegExp(
    r'''(?:data-original|data-src|src)=["']([^"']+)["']''',
    caseSensitive: false,
  );

  static Future<Map<String, String>> buildAliases({
    required Iterable<String?> contents,
    String? html,
    required List<GameImage> images,
  }) async {
    final existingImagesByName = <String, String>{};
    final existingImagesByStem = <String, String>{};
    for (final image in images) {
      final imagePath = image.imagePath;
      if (imagePath.isEmpty || !await File(imagePath).exists()) continue;
      existingImagesByName.putIfAbsent(
        _basenameKey(imagePath),
        () => imagePath,
      );
      existingImagesByStem.putIfAbsent(_stemKey(imagePath), () => imagePath);
    }
    if (existingImagesByName.isEmpty) return {};

    final referencedPaths = <String>{};
    for (final content in contents) {
      if (content == null || content.isEmpty) continue;
      for (final imagePath in MediaReferenceParser.extractImagePaths(content)) {
        referencedPaths.add(imagePath);
      }
    }
    if (html != null && html.isNotEmpty) {
      for (final match in _htmlImageSrcPattern.allMatches(html)) {
        final imagePath = match.group(1);
        if (imagePath != null && imagePath.isNotEmpty) {
          referencedPaths.add(imagePath);
        }
      }
    }

    final aliases = <String, String>{};
    for (final oldPath in referencedPaths) {
      if (_isRemotePath(oldPath) || await File(oldPath).exists()) continue;
      final replacement = existingImagesByName[_basenameKey(oldPath)] ??
          existingImagesByStem[_stemKey(oldPath)];
      if (replacement != null) {
        aliases[oldPath] = replacement;
      }
    }
    return aliases;
  }

  static Future<Game> rewriteGameReferences(Game game) async {
    final aliases = await buildAliases(
      contents: [game.intro, game.features, game.changelog, game.guide],
      images: game.images,
    );
    if (aliases.isEmpty) return game;

    return game.copyWith(
      intro: PathReferenceRewriter.replace(game.intro, aliases),
      features: PathReferenceRewriter.replace(game.features, aliases),
      changelog: PathReferenceRewriter.replace(game.changelog, aliases),
      guide: PathReferenceRewriter.replace(game.guide, aliases),
    );
  }

  static bool _isRemotePath(String value) =>
      value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('//');

  static String _basenameKey(String filePath) =>
      path.basename(filePath).toLowerCase();

  static String _stemKey(String filePath) {
    final fileName = _basenameKey(filePath);
    final extension = path.extension(fileName);
    if (extension.isEmpty) return fileName;
    return fileName.substring(0, fileName.length - extension.length);
  }
}
