import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hgame_manager/core/services/backup_image_service.dart';

void main() {
  test('备份图片可打包并恢复到新的本地目录', () async {
    final tempDir = await Directory.systemTemp.createTemp('hgm_backup_image_');
    final source = File('${tempDir.path}${Platform.pathSeparator}cover.png');
    final restoredDir =
        Directory('${tempDir.path}${Platform.pathSeparator}restored');
    await source.writeAsBytes([1, 2, 3, 4]);

    try {
      final archive = Archive();
      final service = BackupImageService();
      await service.addToArchive(archive, [source.path]);
      final imageFile = archive.files.firstWhere(
        (file) => file.name != 'images/manifest.json',
      );
      expect(imageFile.compression, CompressionType.none);
      final zipBytes = ZipEncoder().encode(archive);
      final decodedArchive = ZipDecoder().decodeBytes(zipBytes);
      final restored = await service.restoreFromArchive(
        decodedArchive,
        restoredDir.path,
      );

      expect(restored.keys, contains(source.path));
      final restoredFile = File(restored[source.path]!);
      expect(await restoredFile.exists(), isTrue);
      expect(await restoredFile.readAsBytes(), [1, 2, 3, 4]);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('增量清单只记录图片引用，不把图片重复写入主备份', () async {
    final tempDir = await Directory.systemTemp.createTemp('hgm_backup_delta_');
    final source = File('${tempDir.path}${Platform.pathSeparator}cover.png');
    await source.writeAsBytes([1, 2, 3, 4]);

    try {
      final archive = Archive();
      final service = BackupImageService();
      final assets = await service.addIncrementalManifestToArchive(
        archive,
        [source.path, source.path],
      );

      expect(assets, hasLength(1));
      expect(archive.files.map((file) => file.name), ['images/manifest.json']);
      expect(service.readManifest(archive).keys, [source.path]);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
