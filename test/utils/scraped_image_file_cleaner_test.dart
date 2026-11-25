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

    test('收集本次配图之外的编号图供用户确认', () async {
      final first = await writeImage('1.jpg');
      final second = await writeImage('2.jpg');
      await writeImage('3.jpg');

      final unused = await ScrapedImageFileCleaner.findUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [first, second],
        referenceTexts: const [],
      );

      expect(unused, [path.join(imageDir.path, '3.jpg')]);
      expect(await File(first).exists(), isTrue);
      expect(await File(second).exists(), isTrue);
      expect(await File(path.join(imageDir.path, '3.jpg')).exists(), isTrue);
    });

    test('收集同编号的旧扩展名图片', () async {
      final retained = await writeImage('1.jpg');
      await writeImage('1.png');

      final unused = await ScrapedImageFileCleaner.findUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [retained],
        referenceTexts: const [],
      );

      expect(unused, [path.join(imageDir.path, '1.png')]);
      expect(await File(retained).exists(), isTrue);
      expect(await File(path.join(imageDir.path, '1.png')).exists(), isTrue);
    });

    test('正文引用和非编号图继续保留', () async {
      final retained = await writeImage('1.jpg');
      final referenced = await writeImage('2.jpg');
      final manual = await writeImage('manual-cover.jpg');

      final unused = await ScrapedImageFileCleaner.findUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [retained],
        referenceTexts: ['正文引用: $referenced'],
      );

      expect(unused, isEmpty);
      expect(await File(retained).exists(), isTrue);
      expect(await File(referenced).exists(), isTrue);
      expect(await File(manual).exists(), isTrue);
    });

    test('本次配图为空时仍收集未引用的编号图', () async {
      final oldImage = await writeImage('1.jpg');
      final referenced = await writeImage('scrape_2.jpg');
      final manual = await writeImage('manual_1.jpg');

      final unused = await ScrapedImageFileCleaner.findUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: const [],
        referenceTexts: ['正文引用: $referenced'],
      );

      expect(unused, [oldImage]);
      expect(await File(oldImage).exists(), isTrue);
      expect(await File(referenced).exists(), isTrue);
      expect(await File(manual).exists(), isTrue);
    });

    test('收集未引用的 scrape 前缀编号图', () async {
      final retained = await writeImage('scrape_1.jpg');
      await writeImage('scrape_3.jpg');

      final unused = await ScrapedImageFileCleaner.findUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [retained],
        referenceTexts: const [],
      );

      expect(unused, [path.join(imageDir.path, 'scrape_3.jpg')]);
      expect(await File(retained).exists(), isTrue);
      expect(await File(path.join(imageDir.path, 'scrape_3.jpg')).exists(),
          isTrue);
    });

    test('手动图和攻略图继续保留', () async {
      // manual_/guide_ 手动图不属于刮削编号图清理范围，永久保留
      final manual = await writeImage('manual_1.jpg');
      final guide = await writeImage('guide_01.jpg');
      await writeImage('scrape_2.jpg');

      final unused = await ScrapedImageFileCleaner.findUnusedNumberedImages(
        gamePath: tempDir.path,
        retainedImagePaths: [manual],
        referenceTexts: const [],
      );

      expect(unused, [path.join(imageDir.path, 'scrape_2.jpg')]);
      expect(await File(manual).exists(), isTrue);
      expect(await File(guide).exists(), isTrue);
      expect(await File(path.join(imageDir.path, 'scrape_2.jpg')).exists(),
          isTrue);
    });
  });
}
