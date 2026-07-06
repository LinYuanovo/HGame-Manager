import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/models/models.dart';
import 'package:hgame_manager/core/utils/backup_image_reference_resolver.dart';
import 'package:path/path.dart' as path;

void main() {
  group('BackupImageReferenceResolver', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hgm_backup_ref_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rewrites missing cleared image references to backup images',
        () async {
      final backupImagesDir = await Directory(path.join(
        tempDir.path,
        'Cleared',
        'Backup',
        '[SLG] Game',
        'HGMDatas',
        'images',
      )).create(recursive: true);
      final backupImage = File(path.join(backupImagesDir.path, '2.gif'));
      await backupImage.writeAsBytes([1, 2, 3]);

      final oldImagePath = path.join(
        tempDir.path,
        'Cleared',
        '[SLG] DeletedGame',
        'HGMDatas',
        'images',
        '2.gif',
      );
      final game = Game(
        path: path.dirname(path.dirname(path.dirname(oldImagePath))),
        intro: '[图片:$oldImagePath]',
        images: [
          GameImage(gameId: 1, imagePath: backupImage.path),
        ],
      );

      final rewritten =
          await BackupImageReferenceResolver.rewriteGameReferences(game);

      expect(rewritten.intro, '[图片:${backupImage.path}]');
    });

    test('builds aliases from html lazy image attributes by file stem',
        () async {
      final backupImagesDir = await Directory(path.join(
        tempDir.path,
        'Cleared',
        'Backup',
        'Game',
        'HGMDatas',
        'images',
      )).create(recursive: true);
      final backupImage = File(path.join(backupImagesDir.path, '2.gif'));
      await backupImage.writeAsBytes([1, 2, 3]);

      final oldImagePath = path.join(
        tempDir.path,
        'Cleared',
        'DeletedGame',
        'HGMDatas',
        'images',
        '2.webp',
      );

      final aliases = await BackupImageReferenceResolver.buildAliases(
        contents: const [],
        html: '<img data-original="$oldImagePath">',
        images: [
          GameImage(gameId: 1, imagePath: backupImage.path),
        ],
      );

      expect(aliases[oldImagePath], backupImage.path);
    });
  });
}
