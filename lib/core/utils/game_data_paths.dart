import 'dart:io';
import 'package:path/path.dart' as path;

class GameDataPaths {
  static const dataDirName = 'HGMDatas';
  static const imagesDirName = 'images';
  static const backupDirName = 'backup';

  /// 管理器图片命名前缀（游戏目录内区分管理器图与游戏自带资源图）
  static const scrapeImagePrefix = 'scrape_';
  static const manualImagePrefix = 'manual_';
  static const guideImagePrefix = 'guide_';

  /// 管理器视频命名前缀（Steam 描述内视频下载，位于 HGMDatas/images 下）
  static const videoImagePrefix = 'video_';

  static final _uuidStemPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// 文件名（含扩展名）是否为管理器命名规则：
  /// scrape_ / manual_ / guide_ / video_ 前缀或历史 UUID 命名。
  /// 纯数字（旧版刮削命名）不在此列——与游戏 CG 解包命名撞车，仅凭引用判定。
  static bool isManagedImageFileName(String fileName) {
    final stem = path.basenameWithoutExtension(fileName).toLowerCase();
    if (stem.startsWith(scrapeImagePrefix) ||
        stem.startsWith(manualImagePrefix) ||
        stem.startsWith(guideImagePrefix) ||
        stem.startsWith(videoImagePrefix)) {
      return true;
    }
    return _uuidStemPattern.hasMatch(stem);
  }

  /// 解析刮削编号图（scrape_N 或旧版纯数字 N）的序号；
  /// 非编号命名（manual_/guide_/UUID/游戏资源名）返回 null。
  /// 注意 stem 为 `scrape_1.tmp`（临时文件）时剩余部分非纯数字，自然返回 null。
  static int? parseScrapeImageIndex(String fileName) {
    var stem = path.basenameWithoutExtension(fileName).toLowerCase();
    if (stem.startsWith(scrapeImagePrefix)) {
      stem = stem.substring(scrapeImagePrefix.length);
    }
    return int.tryParse(stem);
  }

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

    // 仅回退到复数 images（管理器旧版布局）；
    // 单数 image 从未由管理器使用，是游戏常见资源目录，不得作为图片目录兜底
    final legacy = legacyImagesDir(gamePath);
    if (await legacy.exists()) return legacy;

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
        );
  }
}
