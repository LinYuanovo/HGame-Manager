import 'dart:io';
import 'package:path/path.dart' as path;

class GameDataPaths {
  static const dataDirName = 'HGMDatas';
  static const imagesDirName = 'images';
  static const backupDirName = 'backup';

  static Directory dataDir(String gamePath) =>
      Directory(path.join(gamePath, dataDirName));

  static File metadataFile(String gamePath) =>
      File(path.join(dataDir(gamePath).path, 'metadata.json'));

  static File sourceUrlFile(String gamePath) =>
      File(path.join(dataDir(gamePath).path, 'source_url.txt'));

  static Directory imagesDir(String gamePath) =>
      Directory(path.join(dataDir(gamePath).path, imagesDirName));

  static Directory backupDir(String gamePath) =>
      Directory(path.join(dataDir(gamePath).path, backupDirName));

  static File legacyMetadataFile(String gamePath) =>
      File(path.join(gamePath, 'metadata.json'));

  static File legacySourceUrlFile(String gamePath) =>
      File(path.join(gamePath, 'source_url.txt'));

  static Directory legacyImagesDir(String gamePath) =>
      Directory(path.join(gamePath, 'images'));

  static Directory legacySingularImageDir(String gamePath) =>
      Directory(path.join(gamePath, 'image'));

  static Directory legacyBackupDir(String gamePath) =>
      Directory(path.join(gamePath, 'HGMBackup'));

  static Future<File> existingMetadataFile(String gamePath) async {
    final current = metadataFile(gamePath);
    if (await current.exists()) return current;

    final legacy = legacyMetadataFile(gamePath);
    if (await legacy.exists()) return legacy;

    return current;
  }

  static Future<File> existingSourceUrlFile(String gamePath) async {
    final current = sourceUrlFile(gamePath);
    if (await current.exists()) return current;

    final legacy = legacySourceUrlFile(gamePath);
    if (await legacy.exists()) return legacy;

    return current;
  }

  static Future<Directory> existingImagesDir(String gamePath) async {
    final current = imagesDir(gamePath);
    if (await current.exists()) return current;

    final legacy = legacyImagesDir(gamePath);
    if (await legacy.exists()) return legacy;

    final singular = legacySingularImageDir(gamePath);
    if (await singular.exists()) return singular;

    return current;
  }

  static Future<Directory> existingBackupDir(String gamePath) async {
    final current = backupDir(gamePath);
    if (await current.exists()) return current;

    final legacy = legacyBackupDir(gamePath);
    if (await legacy.exists()) return legacy;

    return current;
  }

  static Future<Directory> ensureDataDir(String gamePath) async {
    final dir = dataDir(gamePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> ensureImagesDir(String gamePath) async {
    final dir = imagesDir(gamePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> ensureBackupDir(String gamePath) async {
    final dir = backupDir(gamePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static bool isManagedImagePath(String gamePath, String filePath) {
    final normalizedPath = path.normalize(filePath).toLowerCase();
    return normalizedPath.startsWith(
          '${path.normalize(imagesDir(gamePath).path).toLowerCase()}${path.separator}',
        ) ||
        normalizedPath.startsWith(
          '${path.normalize(legacyImagesDir(gamePath).path).toLowerCase()}${path.separator}',
        ) ||
        normalizedPath.startsWith(
          '${path.normalize(legacySingularImageDir(gamePath).path).toLowerCase()}${path.separator}',
        );
  }
}
