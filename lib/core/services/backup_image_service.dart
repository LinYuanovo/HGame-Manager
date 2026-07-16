import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

class BackupImageAsset {
  final String originalPath;
  final String archivePath;
  final String filePath;

  const BackupImageAsset({
    required this.originalPath,
    required this.archivePath,
    required this.filePath,
  });
}

class BackupImageService {
  static const String _manifestName = 'images/manifest.json';

  Future<void> addToArchive(
    Archive archive,
    Iterable<String> imagePaths,
  ) async {
    final manifest = <String, String>{};
    final seen = <String>{};
    var index = 0;

    for (final imagePath in imagePaths) {
      final normalized = path.normalize(imagePath).toLowerCase();
      if (!seen.add(normalized)) continue;

      final file = File(imagePath);
      if (!await file.exists()) continue;

      final archivePath =
          'images/${index.toString().padLeft(4, '0')}_${path.basename(imagePath)}';
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile.noCompress(archivePath, bytes.length, bytes));
      manifest[imagePath] = archivePath;
      index++;
    }

    if (manifest.isEmpty) return;

    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile(_manifestName, manifestBytes.length, manifestBytes),
    );
  }

  Future<List<BackupImageAsset>> addIncrementalManifestToArchive(
    Archive archive,
    Iterable<String> imagePaths,
  ) async {
    final manifest = <String, String>{};
    final assets = <String, BackupImageAsset>{};
    final seen = <String>{};

    for (final imagePath in imagePaths) {
      final normalized = path.normalize(imagePath).toLowerCase();
      if (!seen.add(normalized)) continue;

      final file = File(imagePath);
      if (!await file.exists()) continue;

      final stat = await file.stat();
      final fingerprint = sha256.convert(
        utf8.encode(
          '$normalized|${stat.size}|${stat.modified.millisecondsSinceEpoch}',
        ),
      );
      final extension = path.extension(imagePath).toLowerCase();
      final archivePath =
          'images/$fingerprint${extension.isEmpty ? '.img' : extension}';
      manifest[imagePath] = archivePath;
      assets.putIfAbsent(
        archivePath,
        () => BackupImageAsset(
          originalPath: imagePath,
          archivePath: archivePath,
          filePath: imagePath,
        ),
      );
    }

    _addManifest(archive, manifest);
    return assets.values.toList();
  }

  Map<String, String> readManifest(Archive archive) {
    for (final file in archive) {
      if (file.name != _manifestName) continue;
      return Map<String, String>.from(
        jsonDecode(utf8.decode(file.content as List<int>)) as Map,
      );
    }
    return {};
  }

  void _addManifest(Archive archive, Map<String, String> manifest) {
    if (manifest.isEmpty) return;
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile(_manifestName, manifestBytes.length, manifestBytes),
    );
  }

  Future<Map<String, String>> restoreFromArchive(
    Archive archive,
    String destinationDir,
  ) async {
    final manifest = readManifest(archive);
    if (manifest.isEmpty) return {};
    final archiveFiles = <String, ArchiveFile>{
      for (final file in archive) file.name: file,
    };
    final destination = Directory(destinationDir);
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    final restoredPaths = <String, String>{};
    final restoreId = DateTime.now().microsecondsSinceEpoch;
    var index = 0;
    for (final entry in manifest.entries) {
      final source = archiveFiles[entry.value];
      if (source == null) continue;

      final fileName =
          'backup_${restoreId}_${index}_${path.basename(entry.value)}';
      final restoredPath = path.join(destinationDir, fileName);
      await File(restoredPath).writeAsBytes(source.content as List<int>);
      restoredPaths[entry.key] = restoredPath;
      index++;
    }

    return restoredPaths;
  }
}
