import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/utils/game_data_paths.dart';
import 'package:hgame_manager/core/utils/scraped_image_file_cleaner.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ScrapedImageFileCleaner', () {
    late Directory tempDir;
    late Directory imageDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('scraped_image_cleaner_');
      imageDir = await GameDataPaths.ensureImagesDir(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> writeImage(String name) async {
      final file = File(path.join(imageDir.path, name));
      await file.writeAsBytes([1, 2, 3], flush: true);
      return file.path;
    }

    test('deletes numbered images not retained by the latest scrape', () async {
      final first = await writeImage('1.jpg');
      final second = await writeImage('2.jpg');
      await writeImage('3.jpg');

      final deleted = await ScrapedImageFileCleaner.cleanUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [first, second],
        referenceTexts: const [],
      );

      expect(deleted, 1);
      expect(await File(first).exists(), isTrue);
      expect(await File(second).exists(), isTrue);
      expect(await File(path.join(imageDir.path, '3.jpg')).exists(), isFalse);
    });

    test('removes old extension residue for the same image index', () async {
      final retained = await writeImage('1.jpg');
      await writeImage('1.png');

      final deleted = await ScrapedImageFileCleaner.cleanUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [retained],
        referenceTexts: const [],
      );

      expect(deleted, 1);
      expect(await File(retained).exists(), isTrue);
      expect(await File(path.join(imageDir.path, '1.png')).exists(), isFalse);
    });

    test('keeps non-numbered and referenced numbered images', () async {
      final retained = await writeImage('1.jpg');
      final referenced = await writeImage('2.jpg');
      final manual = await writeImage('manual-cover.jpg');

      final deleted = await ScrapedImageFileCleaner.cleanUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [retained],
        referenceTexts: ['正文引用: $referenced'],
      );

      expect(deleted, 0);
      expect(await File(retained).exists(), isTrue);
      expect(await File(referenced).exists(), isTrue);
      expect(await File(manual).exists(), isTrue);
    });

    test('keeps old images when no latest image is retained', () async {
      final oldImage = await writeImage('1.jpg');

      final deleted = await ScrapedImageFileCleaner.cleanUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: const [],
        referenceTexts: const [],
      );

      expect(deleted, 0);
      expect(await File(oldImage).exists(), isTrue);
    });
  });
}
